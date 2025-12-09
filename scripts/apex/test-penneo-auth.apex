// Test Penneo API authentication
// This script attempts to get an access token from Penneo

System.debug('=== Testing Penneo Authentication ===');

// Get settings
PenneoAuthService.ProviderSettings settings = PenneoAuthService.getSettings('sandbox');

if (settings == null) {
    System.debug('ERROR: No settings found for sandbox environment');
} else {
    System.debug('Settings found:');
    System.debug('  Environment: ' + settings.environment);
    System.debug('  OAuth Token Endpoint: ' + settings.oauthTokenEndpoint);
    System.debug('  API Base URL: ' + settings.apiBaseUrl);
    System.debug('  Has API Key: ' + String.isNotBlank(settings.apiKey));
    System.debug('  Has API Secret: ' + String.isNotBlank(settings.apiSecret));
    System.debug('  Has OAuth Client ID: ' + String.isNotBlank(settings.oauthClientId));
    System.debug('  Has OAuth Client Secret: ' + String.isNotBlank(settings.oauthClientSecret));
    
    // Try to authenticate
    System.debug('');
    System.debug('Attempting to authenticate...');
    PenneoAuthService.TokenResponse tokenResponse = PenneoAuthService.authenticate('sandbox');
    
    if (tokenResponse.success) {
        System.debug('SUCCESS: Got access token');
        System.debug('  Token (first 20 chars): ' + tokenResponse.accessToken.substring(0, Math.min(20, tokenResponse.accessToken.length())) + '...');
        System.debug('  Expires At: ' + Datetime.newInstance(tokenResponse.expiresAt).format());
    } else {
        System.debug('ERROR: Authentication failed');
        System.debug('  Error: ' + tokenResponse.errorMessage);
    }
}

System.debug('=== Test Complete ===');
