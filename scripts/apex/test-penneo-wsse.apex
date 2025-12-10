// Test Penneo API Connection with WSSE Authentication
// Run this in Developer Console: Debug > Open Execute Anonymous Window
// Or via SF CLI: sf apex run --file scripts/apex/test-penneo-wsse.apex

System.debug('=== Testing Penneo API Connection ===');

// Test 1: Check settings are loaded
PenneoAuthService.ProviderSettings settings = PenneoAuthService.getSettings(null);
if (settings == null) {
    System.debug('ERROR: No settings found. Make sure Signature_Provider_Settings__mdt has an active record.');
} else {
    System.debug('Settings loaded successfully:');
    System.debug('  Environment: ' + settings.environment);
    System.debug('  API Base URL: ' + settings.apiBaseUrl);
    System.debug('  API Key: ' + (String.isNotBlank(settings.apiKey) ? settings.apiKey.substring(0, 8) + '...' : 'MISSING'));
    System.debug('  API Secret: ' + (String.isNotBlank(settings.apiSecret) ? '***configured***' : 'MISSING'));
    System.debug('  OAuth Client ID: ' + (String.isNotBlank(settings.oauthClientId) ? 'configured' : 'not set (will use WSSE)'));
}

// Test 2: Check auth mode
Boolean useWsse = PenneoAuthService.shouldUseWsse(null);
System.debug('');
System.debug('Authentication Mode: ' + (useWsse ? 'WSSE' : 'OAuth'));

// Test 3: Generate WSSE headers (just to verify they work)
if (useWsse) {
    PenneoAuthService.WsseHeaders headers = PenneoAuthService.generateWsseHeaders(null);
    if (headers != null) {
        System.debug('');
        System.debug('WSSE Headers generated successfully:');
        System.debug('  Authorization: ' + headers.authorization);
        System.debug('  X-WSSE: ' + headers.xWsse.substring(0, 50) + '...');
    } else {
        System.debug('ERROR: Failed to generate WSSE headers');
    }
}

// Test 4: Make actual API call
System.debug('');
System.debug('=== Making API Test Call ===');
Map<String, Object> result = PenneoApiService.testConnection();

System.debug('Test Result:');
for (String key : result.keySet()) {
    System.debug('  ' + key + ': ' + result.get(key));
}

if ((Boolean)result.get('success')) {
    System.debug('');
    System.debug('✅ SUCCESS! Penneo API connection is working.');
} else {
    System.debug('');
    System.debug('❌ FAILED. Check the error message above.');
    System.debug('Common issues:');
    System.debug('  - API Key/Secret might be incorrect');
    System.debug('  - Remote Site Settings not configured for app.penneo.com');
    System.debug('  - Network/firewall issues');
}
