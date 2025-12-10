// Test creating a signature request - get the real Account ID from the Journal
Journal__c j = [SELECT Id, Account__c FROM Journal__c WHERE Id = 'a0AG5000009TBaoMAG' LIMIT 1];

SignatureRequestService.CreateSignatureInput input = new SignatureRequestService.CreateSignatureInput();
input.accountId = j.Account__c; // The actual Account ID from the Journal
input.journalId = 'a0AG5000009TBaoMAG'; // The Journal ID
input.sharedDocumentId = 'a0nG5000001UpsXIAS'; // The Shared Document ID
input.signerName = 'Test Signer';
input.signerEmail = 'test@example.com';
input.title = 'Test Document';
input.language = 'da';
input.expirationDays = 14;
input.marketUnit = 'DFJ_DK';
input.environment = 'production';

System.debug('=== Testing SignatureRequestService.createSignatureRequest ===');
System.debug('Account ID from Journal: ' + input.accountId);
System.debug('Input sharedDocumentId: ' + input.sharedDocumentId);

SignatureRequestService.CreateSignatureResult result = SignatureRequestService.createSignatureRequest(input);

System.debug('Result success: ' + result.success);
System.debug('Result errorMessage: ' + result.errorMessage);
System.debug('Result signatureRequestId: ' + result.signatureRequestId);
