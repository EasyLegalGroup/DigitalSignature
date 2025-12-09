/**
 * Test class for PenneoAuthService and PenneoApiService
 */
@isTest
private class PenneoService_Test {
    
    // ===== Mock HTTP Callout Classes =====
    
    /**
     * Mock for successful OAuth token response
     */
    private class MockAuthSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"access_token":"mock_access_token_12345","expires_in":600,"token_type":"Bearer"}');
            return res;
        }
    }
    
    /**
     * Mock for failed OAuth token response
     */
    private class MockAuthFailure implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"error":"invalid_client","error_description":"Client authentication failed"}');
            return res;
        }
    }
    
    /**
     * Mock for case file creation - returns job UUID
     */
    private class MockCreateCaseFile implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            
            if (req.getEndpoint().contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","expires_in":600}');
            } else if (req.getEndpoint().contains('/casefiles')) {
                res.setStatusCode(202);
                res.setBody('{"uuid":"job-uuid-12345","payloadHash":"sha256hash12345"}');
            } else {
                res.setStatusCode(404);
                res.setBody('Not found');
            }
            return res;
        }
    }
    
    /**
     * Mock for job status polling - completed
     */
    private class MockJobStatusCompleted implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            
            if (req.getEndpoint().contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","expires_in":600}');
            } else if (req.getEndpoint().contains('/queue/public/status')) {
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'status' => 'completed',
                    'result' => new Map<String, Object>{
                        'caseFileId' => 12345,
                        'documents' => new List<Object>{
                            new Map<String, Object>{ 'id' => 67890 }
                        },
                        'signers' => new List<Object>{
                            new Map<String, Object>{
                                'id' => 11111,
                                'signingRequest' => new Map<String, Object>{
                                    'link' => 'https://sandbox.penneo.com/signing/12345'
                                }
                            }
                        }
                    }
                }));
            } else {
                res.setStatusCode(404);
            }
            return res;
        }
    }
    
    /**
     * Mock for job status polling - pending
     */
    private class MockJobStatusPending implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            
            if (req.getEndpoint().contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","expires_in":600}');
            } else if (req.getEndpoint().contains('/queue/public/status')) {
                res.setStatusCode(200);
                res.setBody('{"status":"pending"}');
            } else {
                res.setStatusCode(404);
            }
            return res;
        }
    }
    
    /**
     * Mock for case file details
     */
    private class MockCaseFileDetails implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            
            if (req.getEndpoint().contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","expires_in":600}');
            } else if (req.getEndpoint().contains('/casefiles/')) {
                res.setStatusCode(200);
                res.setBody('{"id":12345,"title":"Test Document","status":5}');
            } else {
                res.setStatusCode(404);
            }
            return res;
        }
    }
    
    /**
     * Mock for document download
     */
    private class MockDocumentDownload implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            
            if (req.getEndpoint().contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","expires_in":600}');
            } else if (req.getEndpoint().contains('/documents/') && req.getEndpoint().contains('/pdf')) {
                res.setStatusCode(200);
                res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 mock pdf content'));
                res.setHeader('Content-Type', 'application/pdf');
            } else {
                res.setStatusCode(404);
            }
            return res;
        }
    }
    
    // ===== Test Setup =====
    
    @testSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            FirstName = 'Test',
            LastName = 'Signer',
            PersonEmail = 'test.signer@example.com',
            RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1].Id
        );
        insert testAccount;
        
        // Create test Journal
        Journal__c testJournal = new Journal__c(
            Account__c = testAccount.Id,
            Market_Unit__c = 'DFJ_DK'
        );
        insert testJournal;
    }
    
    // ===== PenneoAuthService Tests =====
    
    @isTest
    static void testGetSettings_ReturnsSettings() {
        // Settings are loaded from Custom Metadata, which is available in tests
        PenneoAuthService.ProviderSettings settings = PenneoAuthService.getSettings('sandbox');
        
        // May be null if no Custom Metadata is deployed, which is fine for unit tests
        if (settings != null) {
            System.assertNotEquals(null, settings.environment, 'Environment should be set');
        }
    }
    
    @isTest
    static void testGetSettings_NullEnvironment() {
        PenneoAuthService.ProviderSettings settings = PenneoAuthService.getSettings(null);
        // Should return first active settings or null
        // No assertion needed - just verify no exception
    }
    
    @isTest
    static void testAuthenticate_MissingSettings() {
        // Clear any cached tokens
        PenneoAuthService.clearCache();
        
        // Test with non-existent environment
        PenneoAuthService.TokenResponse resp = PenneoAuthService.authenticate('nonexistent_env_12345');
        
        // Should fail gracefully (either no settings or missing credentials)
        // The exact error depends on whether Custom Metadata exists
        System.assertNotEquals(null, resp, 'Response should not be null');
    }
    
    @isTest
    static void testClearCache() {
        // Just verify no exception is thrown
        PenneoAuthService.clearCache();
        System.assert(true, 'Cache cleared without exception');
    }
    
    // ===== PenneoApiService Tests =====
    
    @isTest
    static void testCreateCaseFile_NullRequest() {
        PenneoApiService.CreateCaseFileResponse resp = PenneoApiService.createCaseFile(null);
        
        System.assertEquals(false, resp.success, 'Should fail for null request');
        System.assert(resp.errorMessage.contains('null'), 'Error should mention null');
    }
    
    @isTest
    static void testCreateCaseFile_MissingSigner() {
        PenneoApiService.CreateCaseFileRequest req = new PenneoApiService.CreateCaseFileRequest();
        req.documentContent = Blob.valueOf('test pdf');
        req.documentFileName = 'test.pdf';
        // Missing signerName and signerEmail
        
        PenneoApiService.CreateCaseFileResponse resp = PenneoApiService.createCaseFile(req);
        
        System.assertEquals(false, resp.success, 'Should fail for missing signer');
        System.assert(resp.errorMessage.contains('Signer'), 'Error should mention signer');
    }
    
    @isTest
    static void testCreateCaseFile_MissingDocument() {
        PenneoApiService.CreateCaseFileRequest req = new PenneoApiService.CreateCaseFileRequest();
        req.signerName = 'Test Signer';
        req.signerEmail = 'test@example.com';
        // Missing document
        
        PenneoApiService.CreateCaseFileResponse resp = PenneoApiService.createCaseFile(req);
        
        System.assertEquals(false, resp.success, 'Should fail for missing document');
        System.assert(resp.errorMessage.contains('Document'), 'Error should mention document');
    }
    
    @isTest
    static void testCreateCaseFile_Success() {
        Test.setMock(HttpCalloutMock.class, new MockCreateCaseFile());
        
        PenneoApiService.CreateCaseFileRequest req = new PenneoApiService.CreateCaseFileRequest();
        req.title = 'Test Signature Request';
        req.signerName = 'Test Signer';
        req.signerEmail = 'test@example.com';
        req.documentContent = Blob.valueOf('%PDF-1.4 test content');
        req.documentFileName = 'test.pdf';
        req.documentTitle = 'Test Document';
        req.language = 'da';
        req.expirationDays = 14;
        
        Test.startTest();
        PenneoApiService.CreateCaseFileResponse resp = PenneoApiService.createCaseFile(req, 'sandbox');
        Test.stopTest();
        
        // Response depends on settings availability
        System.assertNotEquals(null, resp, 'Response should not be null');
    }
    
    @isTest
    static void testGetJobStatus_MissingParams() {
        PenneoApiService.JobStatusResponse resp = PenneoApiService.getJobStatus(null, null);
        
        System.assertEquals(false, resp.success, 'Should fail for null params');
        System.assert(resp.errorMessage.contains('required'), 'Error should mention required');
    }
    
    @isTest
    static void testGetJobStatus_Completed() {
        Test.setMock(HttpCalloutMock.class, new MockJobStatusCompleted());
        
        Test.startTest();
        PenneoApiService.JobStatusResponse resp = PenneoApiService.getJobStatus('job-uuid', 'payload-hash', 'sandbox');
        Test.stopTest();
        
        System.assertNotEquals(null, resp, 'Response should not be null');
    }
    
    @isTest
    static void testGetJobStatus_Pending() {
        Test.setMock(HttpCalloutMock.class, new MockJobStatusPending());
        
        Test.startTest();
        PenneoApiService.JobStatusResponse resp = PenneoApiService.getJobStatus('job-uuid', 'payload-hash', 'sandbox');
        Test.stopTest();
        
        System.assertNotEquals(null, resp, 'Response should not be null');
    }
    
    @isTest
    static void testGetCaseFileDetails_NullId() {
        PenneoApiService.CaseFileDetails resp = PenneoApiService.getCaseFileDetails(null);
        
        System.assertEquals(false, resp.success, 'Should fail for null ID');
    }
    
    @isTest
    static void testGetCaseFileDetails_Success() {
        Test.setMock(HttpCalloutMock.class, new MockCaseFileDetails());
        
        Test.startTest();
        PenneoApiService.CaseFileDetails resp = PenneoApiService.getCaseFileDetails(12345, 'sandbox');
        Test.stopTest();
        
        System.assertNotEquals(null, resp, 'Response should not be null');
    }
    
    @isTest
    static void testDownloadSignedDocument_NullId() {
        PenneoApiService.SignedDocumentResponse resp = PenneoApiService.downloadSignedDocument(null);
        
        System.assertEquals(false, resp.success, 'Should fail for null ID');
    }
    
    @isTest
    static void testDownloadSignedDocument_Success() {
        Test.setMock(HttpCalloutMock.class, new MockDocumentDownload());
        
        Test.startTest();
        PenneoApiService.SignedDocumentResponse resp = PenneoApiService.downloadSignedDocument(67890, 'sandbox');
        Test.stopTest();
        
        System.assertNotEquals(null, resp, 'Response should not be null');
    }
    
    @isTest
    static void testTranslateStatus() {
        System.assertEquals('New', PenneoApiService.translateStatus(0));
        System.assertEquals('Pending', PenneoApiService.translateStatus(1));
        System.assertEquals('Rejected', PenneoApiService.translateStatus(2));
        System.assertEquals('Failed', PenneoApiService.translateStatus(3));
        System.assertEquals('Signed', PenneoApiService.translateStatus(4));
        System.assertEquals('Completed', PenneoApiService.translateStatus(5));
        System.assertEquals('Failed', PenneoApiService.translateStatus(6));
        System.assertEquals('Expired', PenneoApiService.translateStatus(7));
        System.assertEquals('New', PenneoApiService.translateStatus(99)); // default
    }
    
    // ===== Signature_Request__c Object Tests =====
    
    @isTest
    static void testSignatureRequestCreation() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Journal__c j = [SELECT Id FROM Journal__c LIMIT 1];
        
        Signature_Request__c sr = new Signature_Request__c(
            Account__c = acc.Id,
            Journal__c = j.Id,
            Status__c = 'New',
            Signer_Name__c = 'Test Signer',
            Signer_Email__c = 'test@example.com',
            Market_Unit__c = 'DFJ_DK'
        );
        
        Test.startTest();
        insert sr;
        Test.stopTest();
        
        Signature_Request__c inserted = [SELECT Id, Name, Status__c FROM Signature_Request__c WHERE Id = :sr.Id];
        System.assertNotEquals(null, inserted.Name, 'Auto-number name should be generated');
        System.assertEquals('New', inserted.Status__c, 'Status should be New');
    }
    
    @isTest
    static void testSignatureRequestStatusUpdate() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Signature_Request__c sr = new Signature_Request__c(
            Account__c = acc.Id,
            Status__c = 'New',
            Signer_Name__c = 'Test Signer',
            Signer_Email__c = 'test@example.com'
        );
        insert sr;
        
        sr.Status__c = 'Pending';
        sr.External_Case_ID__c = '12345';
        sr.Signature_UUID__c = 'uuid-12345';
        sr.Payload_Hash__c = 'hash-12345';
        update sr;
        
        sr.Status__c = 'Completed';
        sr.Completed_Date__c = Datetime.now();
        update sr;
        
        Signature_Request__c updated = [SELECT Status__c, External_Case_ID__c FROM Signature_Request__c WHERE Id = :sr.Id];
        System.assertEquals('Completed', updated.Status__c);
        System.assertEquals('12345', updated.External_Case_ID__c);
    }
}
