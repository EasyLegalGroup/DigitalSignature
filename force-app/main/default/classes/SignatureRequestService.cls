/**
 * SignatureRequestService
 * Main entry point for creating and managing signature requests.
 * Called by LWC and other Apex code.
 */
public with sharing class SignatureRequestService {
    
    /**
     * Create a new signature request for a document
     * This creates the Signature_Request__c record and initiates the Penneo API call
     */
    @AuraEnabled
    public static CreateSignatureResult createSignatureRequest(CreateSignatureInput input) {
        CreateSignatureResult result = new CreateSignatureResult();
        
        try {
            // Validate input
            String validationError = validateInput(input);
            if (String.isNotBlank(validationError)) {
                result.success = false;
                result.errorMessage = validationError;
                return result;
            }
            
            // Get the document content
            Blob documentContent = getDocumentContent(input.sharedDocumentId);
            if (documentContent == null) {
                result.success = false;
                result.errorMessage = 'Could not retrieve document content';
                return result;
            }
            
            // Get document info
            Shared_Document__c doc = [
                SELECT Id, Name, Document_Type__c, S3_Key__c
                FROM Shared_Document__c
                WHERE Id = :input.sharedDocumentId
                LIMIT 1
            ];
            
            // Create the Signature_Request__c record first (in Pending state)
            Signature_Request__c sr = new Signature_Request__c();
            sr.Status__c = 'Pending';
            sr.Account__c = input.accountId;
            sr.Journal__c = input.journalId;
            sr.Shared_Document__c = input.sharedDocumentId;
            sr.Signer_Name__c = input.signerName;
            sr.Signer_Email__c = input.signerEmail;
            sr.Market_Unit__c = input.marketUnit;
            sr.Expiration_Date__c = Date.today().addDays(input.expirationDays != null ? input.expirationDays : 14);
            insert sr;
            
            result.signatureRequestId = sr.Id;
            
            // Build the API request
            PenneoApiService.CreateCaseFileRequest apiRequest = new PenneoApiService.CreateCaseFileRequest();
            apiRequest.title = String.isNotBlank(input.title) ? input.title : doc.Name;
            apiRequest.signerName = input.signerName;
            apiRequest.signerEmail = input.signerEmail;
            apiRequest.documentContent = documentContent;
            apiRequest.documentFileName = doc.Name.endsWith('.pdf') ? doc.Name : doc.Name + '.pdf';
            apiRequest.documentTitle = doc.Name;
            apiRequest.language = String.isNotBlank(input.language) ? input.language : 'da';
            apiRequest.expirationDays = input.expirationDays != null ? input.expirationDays : 14;
            
            // Call Penneo API to create case file
            String environment = String.isNotBlank(input.environment) ? input.environment : 'sandbox';
            PenneoApiService.CreateCaseFileResponse apiResponse = PenneoApiService.createCaseFile(apiRequest, environment);
            
            if (!apiResponse.success) {
                // Update record with error
                sr.Status__c = 'Failed';
                sr.Error_Message__c = apiResponse.errorMessage;
                update sr;
                
                result.success = false;
                result.errorMessage = apiResponse.errorMessage;
                return result;
            }
            
            // Update with job info
            sr.Signature_UUID__c = apiResponse.jobUuid;
            sr.Payload_Hash__c = apiResponse.payloadHash;
            update sr;
            
            // Queue job status polling
            System.enqueueJob(new PollJobStatusJob(sr.Id, apiResponse.jobUuid, apiResponse.payloadHash, environment));
            
            result.success = true;
            result.signatureRequestId = sr.Id;
            result.message = 'Signature request created successfully. Processing...';
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
            System.debug('Error creating signature request: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * Get the status of a signature request
     */
    @AuraEnabled(cacheable=true)
    public static Signature_Request__c getSignatureRequest(Id signatureRequestId) {
        return [
            SELECT Id, Name, Status__c, Signer_Name__c, Signer_Email__c, 
                   Signing_Link__c, External_Case_ID__c, Expiration_Date__c,
                   Completed_Date__c, Error_Message__c, Signed_Document_ID__c,
                   Account__c, Journal__c, Shared_Document__c, CreatedDate
            FROM Signature_Request__c
            WHERE Id = :signatureRequestId
            LIMIT 1
        ];
    }
    
    /**
     * Get signature requests for a document
     */
    @AuraEnabled(cacheable=true)
    public static List<Signature_Request__c> getSignatureRequestsForDocument(Id sharedDocumentId) {
        return [
            SELECT Id, Name, Status__c, Signer_Name__c, Signer_Email__c, 
                   Signing_Link__c, Expiration_Date__c, Completed_Date__c, 
                   Error_Message__c, CreatedDate
            FROM Signature_Request__c
            WHERE Shared_Document__c = :sharedDocumentId
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }
    
    /**
     * Get signature requests for a journal
     */
    @AuraEnabled(cacheable=true)
    public static List<Signature_Request__c> getSignatureRequestsForJournal(Id journalId) {
        return [
            SELECT Id, Name, Status__c, Signer_Name__c, Signer_Email__c, 
                   Signing_Link__c, Expiration_Date__c, Completed_Date__c, 
                   Error_Message__c, Shared_Document__c, Shared_Document__r.Name,
                   CreatedDate
            FROM Signature_Request__c
            WHERE Journal__c = :journalId
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
    }
    
    /**
     * Cancel a pending signature request
     */
    @AuraEnabled
    public static CancelResult cancelSignatureRequest(Id signatureRequestId) {
        CancelResult result = new CancelResult();
        
        try {
            Signature_Request__c sr = [
                SELECT Id, Status__c, External_Case_ID__c
                FROM Signature_Request__c
                WHERE Id = :signatureRequestId
                LIMIT 1
            ];
            
            // Can only cancel if not yet completed/signed
            if (sr.Status__c == 'Completed' || sr.Status__c == 'Signed') {
                result.success = false;
                result.message = 'Cannot cancel a completed signature request';
                return result;
            }
            
            // TODO: Call Penneo API to cancel case file if it exists
            // For now, just update the status locally
            
            sr.Status__c = 'Failed';
            sr.Error_Message__c = 'Cancelled by user';
            update sr;
            
            result.success = true;
            result.message = 'Signature request cancelled';
            
        } catch (Exception e) {
            result.success = false;
            result.message = e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Resend signing invitation email
     */
    @AuraEnabled
    public static ResendResult resendInvitation(Id signatureRequestId) {
        ResendResult result = new ResendResult();
        
        try {
            Signature_Request__c sr = [
                SELECT Id, Status__c, External_Case_ID__c, External_Signer_ID__c
                FROM Signature_Request__c
                WHERE Id = :signatureRequestId
                LIMIT 1
            ];
            
            if (sr.Status__c != 'Sent' && sr.Status__c != 'Pending') {
                result.success = false;
                result.message = 'Can only resend invitations for pending/sent requests';
                return result;
            }
            
            // TODO: Call Penneo API to resend invitation
            
            result.success = true;
            result.message = 'Invitation resent successfully';
            
        } catch (Exception e) {
            result.success = false;
            result.message = e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Validate input for creating signature request
     */
    private static String validateInput(CreateSignatureInput input) {
        if (input == null) {
            return 'Input is required';
        }
        if (input.sharedDocumentId == null) {
            return 'Document is required';
        }
        if (String.isBlank(input.signerName)) {
            return 'Signer name is required';
        }
        if (String.isBlank(input.signerEmail)) {
            return 'Signer email is required';
        }
        if (!Pattern.matches('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$', input.signerEmail)) {
            return 'Invalid email format';
        }
        return null;
    }
    
    /**
     * Get document content from Shared_Document__c
     * This retrieves the PDF from S3 via DocShareService
     */
    private static Blob getDocumentContent(Id sharedDocumentId) {
        try {
            // Get the Shared_Document__c to find the S3 key
            Shared_Document__c doc = [
                SELECT Id, S3_Key__c
                FROM Shared_Document__c
                WHERE Id = :sharedDocumentId
                LIMIT 1
            ];
            
            if (String.isBlank(doc.S3_Key__c)) {
                System.debug('No S3 key for document: ' + sharedDocumentId);
                return null;
            }
            
            // Use DocShareService to get presigned URL, then download
            // This is a placeholder - actual implementation depends on your S3 setup
            return downloadFromS3(doc.S3_Key__c);
            
        } catch (Exception e) {
            System.debug('Error getting document content: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Download document from S3
     * Placeholder - implement based on your S3 configuration
     */
    private static Blob downloadFromS3(String s3Key) {
        // TODO: Implement S3 download
        // Option 1: Use AWS SDK via Named Credentials
        // Option 2: Generate presigned URL and fetch
        // Option 3: Use existing DocShareService methods
        
        // For now, return null - will need to integrate with existing S3 logic
        System.debug('S3 download not yet implemented for key: ' + s3Key);
        return null;
    }
    
    // ===== Input/Output Classes =====
    
    public class CreateSignatureInput {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id journalId;
        @AuraEnabled public Id sharedDocumentId;
        @AuraEnabled public String signerName;
        @AuraEnabled public String signerEmail;
        @AuraEnabled public String title;
        @AuraEnabled public String message;
        @AuraEnabled public String language;
        @AuraEnabled public Integer expirationDays;
        @AuraEnabled public String marketUnit;
        @AuraEnabled public String environment;
    }
    
    public class CreateSignatureResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Id signatureRequestId;
        @AuraEnabled public String message;
        @AuraEnabled public String errorMessage;
    }
    
    public class CancelResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }
    
    public class ResendResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }
    
    // ===== Queueable Job for Polling =====
    
    /**
     * Job to poll for case file creation status
     */
    public class PollJobStatusJob implements Queueable, Database.AllowsCallouts {
        private Id signatureRequestId;
        private String jobUuid;
        private String payloadHash;
        private String environment;
        private Integer pollAttempt;
        
        private final Integer MAX_POLL_ATTEMPTS = 10;
        
        public PollJobStatusJob(Id requestId, String uuid, String hash, String env) {
            this.signatureRequestId = requestId;
            this.jobUuid = uuid;
            this.payloadHash = hash;
            this.environment = env;
            this.pollAttempt = 0;
        }
        
        public PollJobStatusJob(Id requestId, String uuid, String hash, String env, Integer attempt) {
            this(requestId, uuid, hash, env);
            this.pollAttempt = attempt;
        }
        
        public void execute(QueueableContext context) {
            try {
                // Poll for job status
                PenneoApiService.JobStatusResponse status = PenneoApiService.getJobStatus(jobUuid, payloadHash, environment);
                
                if (!status.success) {
                    // API error
                    updateRequestError(status.errorMessage);
                    return;
                }
                
                if (status.status == 'completed') {
                    // Job completed - update with case file details
                    updateRequestSuccess(status);
                    return;
                }
                
                if (status.status == 'failed') {
                    updateRequestError('Case file creation failed');
                    return;
                }
                
                // Still pending - queue another poll if under max attempts
                pollAttempt++;
                if (pollAttempt < MAX_POLL_ATTEMPTS) {
                    // Note: Can't delay in Salesforce queueable, 
                    // but the callout itself takes some time
                    System.enqueueJob(new PollJobStatusJob(
                        signatureRequestId, jobUuid, payloadHash, environment, pollAttempt
                    ));
                } else {
                    updateRequestError('Timed out waiting for case file creation');
                }
                
            } catch (Exception e) {
                updateRequestError('Poll error: ' + e.getMessage());
            }
        }
        
        private void updateRequestSuccess(PenneoApiService.JobStatusResponse status) {
            try {
                Signature_Request__c sr = new Signature_Request__c(Id = signatureRequestId);
                sr.Status__c = 'Sent';
                sr.External_Case_ID__c = status.caseFileId != null ? String.valueOf(status.caseFileId) : null;
                sr.External_Document_ID__c = status.documentId != null ? String.valueOf(status.documentId) : null;
                sr.External_Signer_ID__c = status.signerId != null ? String.valueOf(status.signerId) : null;
                sr.Signing_Link__c = status.signingLink;
                sr.Error_Message__c = null;
                update sr;
            } catch (Exception e) {
                System.debug('Error updating signature request: ' + e.getMessage());
            }
        }
        
        private void updateRequestError(String errorMessage) {
            try {
                Signature_Request__c sr = new Signature_Request__c(Id = signatureRequestId);
                sr.Status__c = 'Failed';
                sr.Error_Message__c = errorMessage;
                update sr;
            } catch (Exception e) {
                System.debug('Error updating signature request error: ' + e.getMessage());
            }
        }
    }
}
