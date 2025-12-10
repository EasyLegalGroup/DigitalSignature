/**
 * PenneoApiService
 * Provides methods to interact with the Penneo API for digital signatures.
 * 
 * Key operations:
 * - Create case files (signature requests)
 * - Poll job status
 * - Retrieve case file details
 * - Download signed documents
 * 
 * Uses PenneoAuthService for OAuth token management.
 */
public with sharing class PenneoApiService {
    
    // ===== DTOs =====
    
    public class CreateCaseFileRequest {
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String signerName { get; set; }
        @AuraEnabled public String signerEmail { get; set; }
        @AuraEnabled public String documentTitle { get; set; }
        @AuraEnabled public Blob documentContent { get; set; }
        @AuraEnabled public String documentFileName { get; set; }
        @AuraEnabled public String language { get; set; } // en, da, sv, etc.
        @AuraEnabled public Integer expirationDays { get; set; }
        @AuraEnabled public String successUrl { get; set; }
        @AuraEnabled public String failUrl { get; set; }
    }
    
    public class CreateCaseFileResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public String jobUuid { get; set; }
        @AuraEnabled public String payloadHash { get; set; }
    }
    
    public class JobStatusResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public String status { get; set; } // pending, processing, completed, failed
        @AuraEnabled public Integer caseFileId { get; set; }
        @AuraEnabled public Integer documentId { get; set; }
        @AuraEnabled public Integer signerId { get; set; }
        @AuraEnabled public String signingLink { get; set; }
    }
    
    public class CaseFileDetails {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Integer id { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public Integer status { get; set; } // 0=new, 1=pending, 4=signed, 5=completed, etc.
        @AuraEnabled public String statusText { get; set; }
    }
    
    public class SignedDocumentResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Blob content { get; set; }
        @AuraEnabled public String contentType { get; set; }
    }
    
    // Status code mapping from Penneo API
    private static final Map<Integer, String> STATUS_MAP = new Map<Integer, String>{
        0 => 'new',
        1 => 'pending',
        2 => 'rejected',
        3 => 'deleted',
        4 => 'signed',
        5 => 'completed',
        6 => 'failed',
        7 => 'expired',
        8 => 'anonymized'
    };
    
    // ===== Public Methods =====
    
    /**
     * Create a case file with a single document and signer.
     * Uses the simplified Send API (multipart/form-data).
     */
    @AuraEnabled
    public static CreateCaseFileResponse createCaseFile(CreateCaseFileRequest request) {
        return createCaseFile(request, null);
    }
    
    public static CreateCaseFileResponse createCaseFile(CreateCaseFileRequest request, String environment) {
        CreateCaseFileResponse resp = new CreateCaseFileResponse();
        resp.success = false;
        
        // Validate request
        if (request == null) {
            resp.errorMessage = 'Request cannot be null';
            return resp;
        }
        if (String.isBlank(request.signerName) || String.isBlank(request.signerEmail)) {
            resp.errorMessage = 'Signer name and email are required';
            return resp;
        }
        if (request.documentContent == null || String.isBlank(request.documentFileName)) {
            resp.errorMessage = 'Document content and filename are required';
            return resp;
        }
        
        // Get settings
        PenneoAuthService.ProviderSettings settings = PenneoAuthService.getSettings(environment);
        if (settings == null) {
            resp.errorMessage = 'No active signature provider settings found';
            return resp;
        }
        
        try {
            // Build the JSON payload
            Map<String, Object> caseFileData = buildCaseFilePayload(request);
            String jsonPayload = JSON.serialize(new Map<String, Object>{ 'caseFile' => caseFileData });
            
            // Build multipart form data
            String boundary = '----PenneoFormBoundary' + String.valueOf(Datetime.now().getTime());
            Blob requestBody = buildMultipartBody(boundary, jsonPayload, request.documentContent, request.documentFileName);
            
            // Make the API call
            String endpoint = settings.sendApiBaseUrl + '/casefiles/20251022/create';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
            req.setHeader('Accept', 'application/json');
            
            // Apply authentication (WSSE or OAuth)
            applyAuthentication(req, environment);
            
            req.setBodyAsBlob(requestBody);
            req.setTimeout(60000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200 || res.getStatusCode() == 201 || res.getStatusCode() == 202) {
                Map<String, Object> jsonResp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                resp.jobUuid = (String) jsonResp.get('uuid');
                resp.payloadHash = (String) jsonResp.get('payloadHash');
                resp.success = true;
            } else {
                resp.errorMessage = 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
                System.debug(LoggingLevel.ERROR, 'PenneoApiService.createCaseFile failed: ' + resp.errorMessage);
            }
        } catch (Exception e) {
            resp.errorMessage = e.getTypeName() + ': ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'PenneoApiService.createCaseFile exception: ' + resp.errorMessage);
        }
        
        return resp;
    }
    
    /**
     * Poll for job status after creating a case file.
     */
    @AuraEnabled
    public static JobStatusResponse getJobStatus(String jobUuid, String payloadHash) {
        return getJobStatus(jobUuid, payloadHash, null);
    }
    
    public static JobStatusResponse getJobStatus(String jobUuid, String payloadHash, String environment) {
        JobStatusResponse resp = new JobStatusResponse();
        resp.success = false;
        
        if (String.isBlank(jobUuid) || String.isBlank(payloadHash)) {
            resp.errorMessage = 'Job UUID and payload hash are required';
            return resp;
        }
        
        PenneoAuthService.ProviderSettings settings = PenneoAuthService.getSettings(environment);
        if (settings == null) {
            resp.errorMessage = 'No active signature provider settings found';
            return resp;
        }
        
        try {
            String endpoint = settings.sendApiBaseUrl + '/queue/public/status';
            String body = JSON.serialize(new Map<String, String>{
                'uuid' => jobUuid,
                'payloadHash' => payloadHash
            });
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            // Note: Job status endpoint doesn't require auth per Penneo docs
            // The UUID + payloadHash provide security
            req.setBody(body);
            req.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> jsonResp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                resp.status = (String) jsonResp.get('status');
                resp.success = true;
                
                // If completed, extract result details
                if (resp.status == 'completed' && jsonResp.containsKey('result')) {
                    Map<String, Object> result = (Map<String, Object>) jsonResp.get('result');
                    if (result != null) {
                        resp.caseFileId = (Integer) result.get('caseFileId');
                        
                        // Extract document and signer IDs from nested structures
                        if (result.containsKey('documents')) {
                            List<Object> docs = (List<Object>) result.get('documents');
                            if (docs != null && !docs.isEmpty()) {
                                Map<String, Object> firstDoc = (Map<String, Object>) docs[0];
                                resp.documentId = (Integer) firstDoc.get('id');
                            }
                        }
                        
                        if (result.containsKey('signers')) {
                            List<Object> signers = (List<Object>) result.get('signers');
                            if (signers != null && !signers.isEmpty()) {
                                Map<String, Object> firstSigner = (Map<String, Object>) signers[0];
                                resp.signerId = (Integer) firstSigner.get('id');
                                
                                // Get signing link from signing request
                                if (firstSigner.containsKey('signingRequest')) {
                                    Map<String, Object> signingReq = (Map<String, Object>) firstSigner.get('signingRequest');
                                    if (signingReq != null) {
                                        resp.signingLink = (String) signingReq.get('link');
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Check for failure
                if (resp.status == 'failed' && jsonResp.containsKey('errorMessage')) {
                    resp.errorMessage = (String) jsonResp.get('errorMessage');
                }
            } else {
                resp.errorMessage = 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
            }
        } catch (Exception e) {
            resp.errorMessage = e.getTypeName() + ': ' + e.getMessage();
        }
        
        return resp;
    }
    
    /**
     * Get case file details including status.
     */
    @AuraEnabled
    public static CaseFileDetails getCaseFileDetails(Integer caseFileId) {
        return getCaseFileDetails(caseFileId, null);
    }
    
    public static CaseFileDetails getCaseFileDetails(Integer caseFileId, String environment) {
        CaseFileDetails resp = new CaseFileDetails();
        resp.success = false;
        
        if (caseFileId == null) {
            resp.errorMessage = 'Case file ID is required';
            return resp;
        }
        
        PenneoAuthService.ProviderSettings settings = PenneoAuthService.getSettings(environment);
        if (settings == null) {
            resp.errorMessage = 'No active signature provider settings found';
            return resp;
        }
        
        try {
            String endpoint = settings.apiBaseUrl + '/casefiles/' + caseFileId;
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            
            // Apply authentication (WSSE or OAuth)
            applyAuthentication(req, environment);
            
            req.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> jsonResp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                resp.id = (Integer) jsonResp.get('id');
                resp.title = (String) jsonResp.get('title');
                resp.status = (Integer) jsonResp.get('status');
                resp.statusText = STATUS_MAP.containsKey(resp.status) ? STATUS_MAP.get(resp.status) : 'unknown';
                resp.success = true;
            } else {
                resp.errorMessage = 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
            }
        } catch (Exception e) {
            resp.errorMessage = e.getTypeName() + ': ' + e.getMessage();
        }
        
        return resp;
    }
    
    /**
     * Download signed document content.
     * Only call when case file status = 5 (completed).
     */
    @AuraEnabled
    public static SignedDocumentResponse downloadSignedDocument(Integer documentId) {
        return downloadSignedDocument(documentId, null);
    }
    
    public static SignedDocumentResponse downloadSignedDocument(Integer documentId, String environment) {
        SignedDocumentResponse resp = new SignedDocumentResponse();
        resp.success = false;
        
        if (documentId == null) {
            resp.errorMessage = 'Document ID is required';
            return resp;
        }
        
        PenneoAuthService.ProviderSettings settings = PenneoAuthService.getSettings(environment);
        if (settings == null) {
            resp.errorMessage = 'No active signature provider settings found';
            return resp;
        }
        
        try {
            // Get the signed PDF
            String endpoint = settings.apiBaseUrl + '/documents/' + documentId + '/pdf';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/pdf');
            
            // Apply authentication (WSSE or OAuth)
            applyAuthentication(req, environment);
            
            req.setTimeout(60000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                resp.content = res.getBodyAsBlob();
                resp.contentType = 'application/pdf';
                resp.success = true;
            } else {
                resp.errorMessage = 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
            }
        } catch (Exception e) {
            resp.errorMessage = e.getTypeName() + ': ' + e.getMessage();
        }
        
        return resp;
    }
    
    // ===== Authentication Helper =====
    
    /**
     * Apply authentication headers to a request.
     * Uses WSSE if OAuth credentials are not available.
     */
    private static void applyAuthentication(HttpRequest req, String environment) {
        if (PenneoAuthService.shouldUseWsse(environment)) {
            // Use WSSE authentication
            PenneoAuthService.applyWsseHeaders(req, environment);
        } else {
            // Use OAuth Bearer token
            String accessToken = PenneoAuthService.getAccessToken(environment);
            if (String.isNotBlank(accessToken)) {
                req.setHeader('Authorization', 'Bearer ' + accessToken);
            }
        }
    }
    
    // ===== Test/Debug Methods =====
    
    /**
     * Simple test method to verify API connectivity with WSSE.
     * Returns list of case files or error message.
     */
    public static Map<String, Object> testConnection() {
        return testConnection(null);
    }
    
    public static Map<String, Object> testConnection(String environment) {
        Map<String, Object> result = new Map<String, Object>();
        
        PenneoAuthService.ProviderSettings settings = PenneoAuthService.getSettings(environment);
        if (settings == null) {
            result.put('success', false);
            result.put('error', 'No active signature provider settings found');
            return result;
        }
        
        result.put('environment', settings.environment);
        result.put('apiBaseUrl', settings.apiBaseUrl);
        result.put('authMode', PenneoAuthService.shouldUseWsse(environment) ? 'WSSE' : 'OAuth');
        
        try {
            // Simple GET request to list case files (limited to 1)
            String endpoint = settings.apiBaseUrl + '/casefiles?per_page=1';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            
            // Apply authentication
            applyAuthentication(req, environment);
            
            req.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            result.put('statusCode', res.getStatusCode());
            result.put('success', res.getStatusCode() == 200);
            
            if (res.getStatusCode() == 200) {
                result.put('message', 'Connection successful!');
                // Parse response to get count
                List<Object> caseFiles = (List<Object>) JSON.deserializeUntyped(res.getBody());
                result.put('caseFilesReturned', caseFiles.size());
            } else {
                result.put('error', res.getBody());
            }
        } catch (Exception e) {
            result.put('success', false);
            result.put('error', e.getTypeName() + ': ' + e.getMessage());
        }
        
        return result;
    }
    
    // ===== Private Helper Methods =====
    
    /**
     * Build the case file JSON payload.
     */
    private static Map<String, Object> buildCaseFilePayload(CreateCaseFileRequest request) {
        Map<String, Object> payload = new Map<String, Object>();
        
        // Title
        payload.put('title', String.isNotBlank(request.title) ? request.title : 'Signature Request');
        
        // Language
        if (String.isNotBlank(request.language)) {
            payload.put('language', request.language);
        } else {
            payload.put('language', 'en');
        }
        
        // Expiration
        if (request.expirationDays != null && request.expirationDays > 0) {
            Long expireAt = Datetime.now().addDays(request.expirationDays).getTime() / 1000;
            payload.put('expireAt', expireAt);
        }
        
        // Signers
        Map<String, Object> signer = new Map<String, Object>{
            'name' => request.signerName,
            'email' => request.signerEmail
        };
        
        // Success/Fail URLs
        if (String.isNotBlank(request.successUrl)) {
            signer.put('successUrl', request.successUrl);
        }
        if (String.isNotBlank(request.failUrl)) {
            signer.put('failUrl', request.failUrl);
        }
        
        payload.put('signers', new List<Object>{ signer });
        
        // Documents
        String docTitle = String.isNotBlank(request.documentTitle) ? request.documentTitle : request.documentFileName;
        Map<String, Object> document = new Map<String, Object>{
            'title' => docTitle,
            'name' => request.documentFileName
        };
        payload.put('documents', new List<Object>{ document });
        
        return payload;
    }
    
    /**
     * Build multipart/form-data body with JSON data and file.
     */
    private static Blob buildMultipartBody(String boundary, String jsonData, Blob fileContent, String fileName) {
        String CRLF = '\r\n';
        
        // Part 1: JSON data
        String body = '--' + boundary + CRLF;
        body += 'Content-Disposition: form-data; name="data"' + CRLF;
        body += 'Content-Type: application/json' + CRLF + CRLF;
        body += jsonData + CRLF;
        
        // Part 2: File (we need to handle binary data carefully)
        body += '--' + boundary + CRLF;
        body += 'Content-Disposition: form-data; name="files"; filename="' + fileName + '"' + CRLF;
        body += 'Content-Type: application/pdf' + CRLF + CRLF;
        
        // Combine text parts with binary file
        Blob beforeFile = Blob.valueOf(body);
        Blob afterFile = Blob.valueOf(CRLF + '--' + boundary + '--' + CRLF);
        
        // Concatenate: beforeFile + fileContent + afterFile
        String beforeHex = EncodingUtil.convertToHex(beforeFile);
        String fileHex = EncodingUtil.convertToHex(fileContent);
        String afterHex = EncodingUtil.convertToHex(afterFile);
        
        return EncodingUtil.convertFromHex(beforeHex + fileHex + afterHex);
    }
    
    /**
     * Translate Penneo status code to our Status__c picklist value.
     */
    public static String translateStatus(Integer penneoStatus) {
        switch on penneoStatus {
            when 0 { return 'New'; }
            when 1 { return 'Pending'; }
            when 2 { return 'Rejected'; }
            when 3 { return 'Failed'; } // deleted
            when 4 { return 'Signed'; }
            when 5 { return 'Completed'; }
            when 6 { return 'Failed'; }
            when 7 { return 'Expired'; }
            when else { return 'New'; }
        }
    }
}
