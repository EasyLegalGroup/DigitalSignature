/**
 * PenneoAuthService
 * Handles OAuth 2.0 authentication with Penneo using the API Keys Grant flow.
 * 
 * The API Keys Grant requires:
 * 1. Generate a WSSE-style digest from: nonce + timestamp + API_Secret (SHA1, Base64)
 * 2. POST to OAuth token endpoint with client credentials + API key + digest
 * 3. Receive a JWT access token (valid for 600 seconds / 10 minutes)
 * 
 * Token caching is handled via Platform Cache when available, falling back to
 * a static variable for short-term caching within a single transaction.
 */
public with sharing class PenneoAuthService {
    
    // Cache partition name - create via Setup > Platform Cache > Org Partition
    private static final String CACHE_PARTITION = 'local.PenneoTokens';
    private static final String CACHE_KEY = 'penneo_access_token';
    private static final Integer TOKEN_TTL_SECONDS = 540; // 9 minutes (token valid for 10)
    
    // Fallback static cache for when Platform Cache is not available
    private static String cachedToken;
    private static Long cachedTokenExpiry;
    
    /**
     * DTO for settings loaded from Custom Metadata
     */
    public class ProviderSettings {
        public String environment;
        public String oauthTokenEndpoint;
        public String apiBaseUrl;
        public String sendApiBaseUrl;
        public String oauthClientId;
        public String oauthClientSecret;
        public String apiKey;
        public String apiSecret;
        public String webhookSecret;
        public Boolean isActive;
    }
    
    /**
     * DTO for token response
     */
    public class TokenResponse {
        public String accessToken;
        public Long expiresAt; // Unix timestamp when token expires
        public Boolean success;
        public String errorMessage;
    }
    
    /**
     * Load active settings from Custom Metadata.
     * Returns settings for the specified environment, or the first active one.
     */
    public static ProviderSettings getSettings(String environment) {
        List<Signature_Provider_Settings__mdt> records;
        
        if (String.isNotBlank(environment)) {
            records = [
                SELECT DeveloperName, Environment__c, OAuth_Token_Endpoint__c, 
                       API_Base_URL__c, Send_API_Base_URL__c, OAuth_Client_ID__c, 
                       OAuth_Client_Secret__c, API_Key__c, API_Secret__c, 
                       Webhook_Secret__c, Is_Active__c
                FROM Signature_Provider_Settings__mdt
                WHERE Is_Active__c = true AND Environment__c = :environment
                LIMIT 1
            ];
        }
        
        // Fallback: get any active config
        if (records == null || records.isEmpty()) {
            records = [
                SELECT DeveloperName, Environment__c, OAuth_Token_Endpoint__c, 
                       API_Base_URL__c, Send_API_Base_URL__c, OAuth_Client_ID__c, 
                       OAuth_Client_Secret__c, API_Key__c, API_Secret__c, 
                       Webhook_Secret__c, Is_Active__c
                FROM Signature_Provider_Settings__mdt
                WHERE Is_Active__c = true
                LIMIT 1
            ];
        }
        
        if (records.isEmpty()) {
            return null;
        }
        
        Signature_Provider_Settings__mdt rec = records[0];
        ProviderSettings settings = new ProviderSettings();
        settings.environment = rec.Environment__c;
        settings.oauthTokenEndpoint = rec.OAuth_Token_Endpoint__c;
        settings.apiBaseUrl = rec.API_Base_URL__c;
        settings.sendApiBaseUrl = rec.Send_API_Base_URL__c;
        settings.oauthClientId = rec.OAuth_Client_ID__c;
        settings.oauthClientSecret = rec.OAuth_Client_Secret__c;
        settings.apiKey = rec.API_Key__c;
        settings.apiSecret = rec.API_Secret__c;
        settings.webhookSecret = rec.Webhook_Secret__c;
        settings.isActive = rec.Is_Active__c;
        
        return settings;
    }
    
    /**
     * Get a valid access token, using cache if available.
     * Returns null if authentication fails.
     */
    public static String getAccessToken() {
        return getAccessToken(null);
    }
    
    public static String getAccessToken(String environment) {
        // Try cache first
        String cached = getCachedToken(environment);
        if (String.isNotBlank(cached)) {
            return cached;
        }
        
        // Authenticate and cache new token
        TokenResponse response = authenticate(environment);
        if (response.success && String.isNotBlank(response.accessToken)) {
            cacheToken(environment, response.accessToken, response.expiresAt);
            return response.accessToken;
        }
        
        System.debug(LoggingLevel.ERROR, 'PenneoAuthService: Authentication failed - ' + response.errorMessage);
        return null;
    }
    
    /**
     * Force a fresh authentication, bypassing cache.
     */
    public static TokenResponse authenticate(String environment) {
        ProviderSettings settings = getSettings(environment);
        
        if (settings == null) {
            TokenResponse resp = new TokenResponse();
            resp.success = false;
            resp.errorMessage = 'No active Signature Provider Settings found';
            return resp;
        }
        
        // Validate required fields
        if (String.isBlank(settings.apiKey) || String.isBlank(settings.apiSecret)) {
            TokenResponse resp = new TokenResponse();
            resp.success = false;
            resp.errorMessage = 'API Key and API Secret are required';
            return resp;
        }
        
        if (String.isBlank(settings.oauthClientId) || String.isBlank(settings.oauthClientSecret)) {
            TokenResponse resp = new TokenResponse();
            resp.success = false;
            resp.errorMessage = 'OAuth Client ID and Client Secret are required for API Keys Grant';
            return resp;
        }
        
        return performApiKeysGrant(settings);
    }
    
    /**
     * Perform the API Keys Grant authentication flow.
     * 
     * Per Penneo docs:
     * 1. Generate nonce (random bytes, base64 encoded)
     * 2. Get current timestamp in ISO 8601 format
     * 3. Create digest: base64(sha1(nonce + timestamp + api_secret))
     * 4. POST to token endpoint with all credentials
     */
    private static TokenResponse performApiKeysGrant(ProviderSettings settings) {
        TokenResponse resp = new TokenResponse();
        
        try {
            // Generate WSSE components
            String nonce = generateNonce();
            String timestamp = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String digest = generateDigest(nonce, timestamp, settings.apiSecret);
            
            // Build request body
            Map<String, String> params = new Map<String, String>{
                'grant_type' => 'api_keys',
                'client_id' => settings.oauthClientId,
                'client_secret' => settings.oauthClientSecret,
                'key' => settings.apiKey,
                'nonce' => nonce,
                'timestamp' => timestamp,
                'digest' => digest
            };
            
            String body = '';
            for (String key : params.keySet()) {
                if (body.length() > 0) body += '&';
                body += EncodingUtil.urlEncode(key, 'UTF-8') + '=' + 
                        EncodingUtil.urlEncode(params.get(key), 'UTF-8');
            }
            
            // Make HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint(settings.oauthTokenEndpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setBody(body);
            req.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> jsonResp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                resp.accessToken = (String) jsonResp.get('access_token');
                
                // Calculate expiry (Penneo tokens are valid for 600 seconds)
                Integer expiresIn = 600;
                if (jsonResp.containsKey('expires_in')) {
                    expiresIn = (Integer) jsonResp.get('expires_in');
                }
                resp.expiresAt = Datetime.now().addSeconds(expiresIn).getTime() / 1000;
                resp.success = true;
            } else {
                resp.success = false;
                resp.errorMessage = 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
                System.debug(LoggingLevel.ERROR, 'PenneoAuthService: Token request failed - ' + resp.errorMessage);
            }
        } catch (Exception e) {
            resp.success = false;
            resp.errorMessage = e.getTypeName() + ': ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'PenneoAuthService: Exception - ' + resp.errorMessage);
        }
        
        return resp;
    }
    
    /**
     * Generate a random nonce (16 bytes, base64 encoded).
     */
    private static String generateNonce() {
        Blob randomBytes = Crypto.generateAesKey(128); // 16 bytes
        return EncodingUtil.base64Encode(randomBytes);
    }
    
    /**
     * Generate WSSE digest: base64(sha1(nonce + timestamp + secret))
     */
    private static String generateDigest(String nonce, String timestamp, String secret) {
        String combined = nonce + timestamp + secret;
        Blob sha1Hash = Crypto.generateDigest('SHA1', Blob.valueOf(combined));
        return EncodingUtil.base64Encode(sha1Hash);
    }
    
    /**
     * Try to get cached token from Platform Cache or static variable.
     */
    private static String getCachedToken(String environment) {
        String cacheKey = CACHE_KEY + '_' + (String.isBlank(environment) ? 'default' : environment);
        
        // Try Platform Cache first
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                String token = (String) partition.get(cacheKey);
                if (String.isNotBlank(token)) {
                    return token;
                }
            }
        } catch (Exception e) {
            // Platform Cache not configured, fall through to static cache
            System.debug(LoggingLevel.DEBUG, 'PenneoAuthService: Platform Cache not available - ' + e.getMessage());
        }
        
        // Fallback to static cache
        if (String.isNotBlank(cachedToken) && cachedTokenExpiry != null) {
            Long nowUnix = Datetime.now().getTime() / 1000;
            if (nowUnix < cachedTokenExpiry) {
                return cachedToken;
            }
        }
        
        return null;
    }
    
    /**
     * Cache the token in Platform Cache and static variable.
     */
    private static void cacheToken(String environment, String token, Long expiresAt) {
        String cacheKey = CACHE_KEY + '_' + (String.isBlank(environment) ? 'default' : environment);
        
        // Update static cache
        cachedToken = token;
        cachedTokenExpiry = expiresAt;
        
        // Try Platform Cache
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                partition.put(cacheKey, token, TOKEN_TTL_SECONDS);
            }
        } catch (Exception e) {
            // Platform Cache not configured, static cache is sufficient
            System.debug(LoggingLevel.DEBUG, 'PenneoAuthService: Could not cache in Platform Cache - ' + e.getMessage());
        }
    }
    
    /**
     * Clear cached tokens (useful for testing or forced re-auth).
     */
    public static void clearCache() {
        cachedToken = null;
        cachedTokenExpiry = null;
        
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                partition.remove(CACHE_KEY + '_default');
                partition.remove(CACHE_KEY + '_sandbox');
                partition.remove(CACHE_KEY + '_production');
            }
        } catch (Exception e) {
            // Ignore cache errors
        }
    }
}
