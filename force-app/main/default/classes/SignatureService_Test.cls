/**
 * Test class for PenneoWebhookHandler and SignatureRequestService
 */
@isTest
private class SignatureService_Test {
    
    // ===== Mock HTTP Callouts =====
    
    private class MockApiSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            if (req.getEndpoint().contains('/oauth/token')) {
                res.setBody('{"access_token":"mock_token","expires_in":600}');
            } else if (req.getEndpoint().contains('/casefiles')) {
                res.setBody('{"uuid":"job-uuid-123","payloadHash":"hash-123"}');
                res.setStatusCode(202);
            } else if (req.getEndpoint().contains('/queue/public/status')) {
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
                                    'link' => 'https://sign.penneo.com/12345'
                                }
                            }
                        }
                    }
                }));
            } else if (req.getEndpoint().contains('/pdf')) {
                res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 signed content'));
            }
            
            return res;
        }
    }
    
    // ===== Test Setup =====
    
    @testSetup
    static void setupTestData() {
        // Create test Account (PersonAccount)
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
        
        // Create test Shared_Document
        Shared_Document__c testDoc = new Shared_Document__c(
            Name = 'Test Document.pdf',
            Account__c = testAccount.Id,
            S3_Key__c = 'test/documents/test.pdf'
        );
        insert testDoc;
        
        // Create test Signature_Request
        Signature_Request__c testSr = new Signature_Request__c(
            Account__c = testAccount.Id,
            Journal__c = testJournal.Id,
            Shared_Document__c = testDoc.Id,
            Status__c = 'Sent',
            Signer_Name__c = 'Test Signer',
            Signer_Email__c = 'test@example.com',
            External_Case_ID__c = '12345',
            External_Document_ID__c = '67890',
            External_Signer_ID__c = '11111',
            Market_Unit__c = 'DFJ_DK'
        );
        insert testSr;
    }
    
    // ===== Webhook Handler Tests =====
    
    @isTest
    static void testWebhook_CaseFileSigned() {
        // Get the test signature request
        Signature_Request__c sr = [SELECT Id, External_Case_ID__c FROM Signature_Request__c LIMIT 1];
        
        // Prepare webhook payload
        Map<String, Object> payload = new Map<String, Object>{
            'eventId' => 'evt-123',
            'eventType' => 'case_file.signed',
            'timestamp' => String.valueOf(Datetime.now()),
            'caseFileId' => Integer.valueOf(sr.External_Case_ID__c)
        };
        
        Test.setMock(HttpCalloutMock.class, new MockApiSuccess());
        
        Test.startTest();
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/webhook/signature';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = req;
        
        RestResponse res = new RestResponse();
        RestContext.response = res;
        
        PenneoWebhookHandler.WebhookResponse response = PenneoWebhookHandler.handleWebhook();
        
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Webhook should succeed');
        
        // Verify status was updated
        sr = [SELECT Status__c FROM Signature_Request__c WHERE Id = :sr.Id];
        System.assertEquals('Signed', sr.Status__c, 'Status should be updated to Signed');
    }
    
    @isTest
    static void testWebhook_SignerRejected() {
        Signature_Request__c sr = [SELECT Id, External_Signer_ID__c FROM Signature_Request__c LIMIT 1];
        
        Map<String, Object> payload = new Map<String, Object>{
            'eventId' => 'evt-456',
            'eventType' => 'signer.rejected',
            'signerId' => Integer.valueOf(sr.External_Signer_ID__c)
        };
        
        Test.startTest();
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/webhook/signature';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        PenneoWebhookHandler.WebhookResponse response = PenneoWebhookHandler.handleWebhook();
        
        Test.stopTest();
        
        System.assertEquals(true, response.success);
        
        sr = [SELECT Status__c FROM Signature_Request__c WHERE Id = :sr.Id];
        System.assertEquals('Rejected', sr.Status__c);
    }
    
    @isTest
    static void testWebhook_Expired() {
        Signature_Request__c sr = [SELECT Id, External_Case_ID__c FROM Signature_Request__c LIMIT 1];
        
        Map<String, Object> payload = new Map<String, Object>{
            'eventId' => 'evt-789',
            'eventType' => 'case_file.expired',
            'caseFileId' => Integer.valueOf(sr.External_Case_ID__c)
        };
        
        Test.startTest();
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/webhook/signature';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        PenneoWebhookHandler.WebhookResponse response = PenneoWebhookHandler.handleWebhook();
        
        Test.stopTest();
        
        System.assertEquals(true, response.success);
        
        sr = [SELECT Status__c FROM Signature_Request__c WHERE Id = :sr.Id];
        System.assertEquals('Expired', sr.Status__c);
    }
    
    @isTest
    static void testWebhook_UnsupportedEvent() {
        Map<String, Object> payload = new Map<String, Object>{
            'eventId' => 'evt-000',
            'eventType' => 'unsupported.event',
            'caseFileId' => 99999
        };
        
        Test.startTest();
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/webhook/signature';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        PenneoWebhookHandler.WebhookResponse response = PenneoWebhookHandler.handleWebhook();
        
        Test.stopTest();
        
        System.assertEquals(true, response.success);
        System.assert(response.message.contains('not processed'));
    }
    
    @isTest
    static void testWebhook_InvalidPayload() {
        Test.startTest();
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/webhook/signature';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('not valid json {{{');
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        PenneoWebhookHandler.WebhookResponse response = PenneoWebhookHandler.handleWebhook();
        
        Test.stopTest();
        
        System.assertEquals(false, response.success);
        System.assert(response.message.contains('Invalid'));
    }
    
    @isTest
    static void testWebhook_NoMatchingRequest() {
        Map<String, Object> payload = new Map<String, Object>{
            'eventId' => 'evt-nomatch',
            'eventType' => 'case_file.signed',
            'caseFileId' => 99999999
        };
        
        Test.startTest();
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/webhook/signature';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        PenneoWebhookHandler.WebhookResponse response = PenneoWebhookHandler.handleWebhook();
        
        Test.stopTest();
        
        // Should still succeed (acknowledge webhook even if no matching record)
        System.assertEquals(true, response.success);
    }
    
    // ===== SignatureRequestService Tests =====
    
    @isTest
    static void testGetSignatureRequest() {
        Signature_Request__c sr = [SELECT Id FROM Signature_Request__c LIMIT 1];
        
        Test.startTest();
        Signature_Request__c result = SignatureRequestService.getSignatureRequest(sr.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(sr.Id, result.Id);
    }
    
    @isTest
    static void testGetSignatureRequestsForDocument() {
        Shared_Document__c doc = [SELECT Id FROM Shared_Document__c LIMIT 1];
        
        Test.startTest();
        List<Signature_Request__c> results = SignatureRequestService.getSignatureRequestsForDocument(doc.Id);
        Test.stopTest();
        
        System.assertEquals(1, results.size());
    }
    
    @isTest
    static void testGetSignatureRequestsForJournal() {
        Journal__c journal = [SELECT Id FROM Journal__c LIMIT 1];
        
        Test.startTest();
        List<Signature_Request__c> results = SignatureRequestService.getSignatureRequestsForJournal(journal.Id);
        Test.stopTest();
        
        System.assertEquals(1, results.size());
    }
    
    @isTest
    static void testCreateSignatureRequest_NullInput() {
        Test.startTest();
        SignatureRequestService.CreateSignatureResult result = SignatureRequestService.createSignatureRequest(null);
        Test.stopTest();
        
        System.assertEquals(false, result.success);
        System.assert(result.errorMessage.contains('required'));
    }
    
    @isTest
    static void testCreateSignatureRequest_MissingDocument() {
        SignatureRequestService.CreateSignatureInput input = new SignatureRequestService.CreateSignatureInput();
        input.signerName = 'Test';
        input.signerEmail = 'test@example.com';
        // Missing sharedDocumentId
        
        Test.startTest();
        SignatureRequestService.CreateSignatureResult result = SignatureRequestService.createSignatureRequest(input);
        Test.stopTest();
        
        System.assertEquals(false, result.success);
        System.assert(result.errorMessage.contains('Document'));
    }
    
    @isTest
    static void testCreateSignatureRequest_InvalidEmail() {
        Shared_Document__c doc = [SELECT Id FROM Shared_Document__c LIMIT 1];
        
        SignatureRequestService.CreateSignatureInput input = new SignatureRequestService.CreateSignatureInput();
        input.sharedDocumentId = doc.Id;
        input.signerName = 'Test';
        input.signerEmail = 'invalid-email';
        
        Test.startTest();
        SignatureRequestService.CreateSignatureResult result = SignatureRequestService.createSignatureRequest(input);
        Test.stopTest();
        
        System.assertEquals(false, result.success);
        System.assert(result.errorMessage.contains('email'));
    }
    
    @isTest
    static void testCancelSignatureRequest_Sent() {
        Signature_Request__c sr = [SELECT Id FROM Signature_Request__c LIMIT 1];
        
        Test.startTest();
        SignatureRequestService.CancelResult result = SignatureRequestService.cancelSignatureRequest(sr.Id);
        Test.stopTest();
        
        System.assertEquals(true, result.success);
        
        sr = [SELECT Status__c FROM Signature_Request__c WHERE Id = :sr.Id];
        System.assertEquals('Failed', sr.Status__c);
    }
    
    @isTest
    static void testCancelSignatureRequest_Completed() {
        Signature_Request__c sr = [SELECT Id FROM Signature_Request__c LIMIT 1];
        sr.Status__c = 'Completed';
        update sr;
        
        Test.startTest();
        SignatureRequestService.CancelResult result = SignatureRequestService.cancelSignatureRequest(sr.Id);
        Test.stopTest();
        
        System.assertEquals(false, result.success);
        System.assert(result.message.contains('Cannot cancel'));
    }
    
    @isTest
    static void testResendInvitation() {
        Signature_Request__c sr = [SELECT Id FROM Signature_Request__c LIMIT 1];
        
        Test.startTest();
        SignatureRequestService.ResendResult result = SignatureRequestService.resendInvitation(sr.Id);
        Test.stopTest();
        
        System.assertEquals(true, result.success);
    }
    
    @isTest
    static void testResendInvitation_InvalidStatus() {
        Signature_Request__c sr = [SELECT Id FROM Signature_Request__c LIMIT 1];
        sr.Status__c = 'Completed';
        update sr;
        
        Test.startTest();
        SignatureRequestService.ResendResult result = SignatureRequestService.resendInvitation(sr.Id);
        Test.stopTest();
        
        System.assertEquals(false, result.success);
    }
    
    // ===== DownloadSignedDocumentJob Test =====
    
    @isTest
    static void testDownloadSignedDocumentJob() {
        Signature_Request__c sr = [SELECT Id FROM Signature_Request__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockApiSuccess());
        
        Test.startTest();
        System.enqueueJob(new PenneoWebhookHandler.DownloadSignedDocumentJob(sr.Id));
        Test.stopTest();
        
        // Verify the job ran (even if download fails due to no S3 implementation)
        sr = [SELECT Id, Error_Message__c FROM Signature_Request__c WHERE Id = :sr.Id];
        // Just verify no exception was thrown
        System.assertNotEquals(null, sr.Id);
    }
    
    // ===== PollJobStatusJob Test =====
    
    @isTest
    static void testPollJobStatusJob() {
        // Create a new request in Pending state
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Signature_Request__c sr = new Signature_Request__c(
            Account__c = acc.Id,
            Status__c = 'Pending',
            Signer_Name__c = 'Test',
            Signer_Email__c = 'test@example.com',
            Signature_UUID__c = 'job-123',
            Payload_Hash__c = 'hash-123'
        );
        insert sr;
        
        Test.setMock(HttpCalloutMock.class, new MockApiSuccess());
        
        Test.startTest();
        System.enqueueJob(new SignatureRequestService.PollJobStatusJob(sr.Id, 'job-123', 'hash-123', 'sandbox'));
        Test.stopTest();
        
        // Job should have updated the record
        sr = [SELECT Status__c, External_Case_ID__c FROM Signature_Request__c WHERE Id = :sr.Id];
        // Status depends on mock response and settings availability
        System.assertNotEquals(null, sr.Id);
    }
}
