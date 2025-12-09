/**
 * PenneoWebhookHandler
 * REST endpoint to receive webhook callbacks from Penneo.
 * This will be exposed via a Salesforce Site.
 * 
 * Penneo sends webhooks for events like:
 * - Case file signed
 * - Case file rejected
 * - Case file expired
 * - Document signed
 * 
 * Example webhook payload:
 * {
 *   "eventId": "uuid",
 *   "eventType": "case_file.signed",
 *   "timestamp": "2024-01-15T10:30:00Z",
 *   "caseFileId": 12345,
 *   "documentId": 67890,
 *   "signerId": 11111
 * }
 */
@RestResource(urlMapping='/webhook/signature/*')
global without sharing class PenneoWebhookHandler {
    
    // Supported event types
    private static final Set<String> SUPPORTED_EVENTS = new Set<String>{
        'case_file.signed',
        'case_file.rejected',
        'case_file.expired',
        'document.signed',
        'signer.signed',
        'signer.rejected'
    };
    
    // Status mapping from event type to Signature_Request__c status
    private static final Map<String, String> EVENT_TO_STATUS = new Map<String, String>{
        'case_file.signed' => 'Signed',
        'case_file.rejected' => 'Rejected',
        'case_file.expired' => 'Expired',
        'document.signed' => 'Signed',
        'signer.signed' => 'Signed',
        'signer.rejected' => 'Rejected'
    };
    
    /**
     * POST endpoint for receiving webhooks
     */
    @HttpPost
    global static WebhookResponse handleWebhook() {
        WebhookResponse response = new WebhookResponse();
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            // Log incoming request for debugging
            System.debug('Webhook received: ' + req.requestBody.toString());
            
            // Parse the webhook payload
            WebhookPayload payload = parsePayload(req.requestBody.toString());
            
            if (payload == null) {
                response.success = false;
                response.message = 'Invalid payload format';
                res.statusCode = 400;
                return response;
            }
            
            // Verify webhook signature (if configured)
            if (!verifySignature(req)) {
                response.success = false;
                response.message = 'Invalid signature';
                res.statusCode = 401;
                return response;
            }
            
            // Check if this is a supported event type
            if (!SUPPORTED_EVENTS.contains(payload.eventType)) {
                // Acknowledge but don't process unsupported events
                response.success = true;
                response.message = 'Event type not processed: ' + payload.eventType;
                res.statusCode = 200;
                return response;
            }
            
            // Process the webhook
            processWebhook(payload);
            
            response.success = true;
            response.message = 'Webhook processed successfully';
            res.statusCode = 200;
            
        } catch (Exception e) {
            System.debug('Webhook error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            response.success = false;
            response.message = 'Error processing webhook: ' + e.getMessage();
            res.statusCode = 500;
        }
        
        return response;
    }
    
    /**
     * Parse webhook payload from JSON
     */
    private static WebhookPayload parsePayload(String jsonBody) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
            
            WebhookPayload payload = new WebhookPayload();
            payload.eventId = (String) data.get('eventId');
            payload.eventType = (String) data.get('eventType');
            payload.timestamp = (String) data.get('timestamp');
            
            // Handle different ID field names (might be nested or direct)
            if (data.containsKey('caseFileId')) {
                payload.caseFileId = String.valueOf(data.get('caseFileId'));
            } else if (data.containsKey('caseFile')) {
                Map<String, Object> cf = (Map<String, Object>) data.get('caseFile');
                if (cf != null) {
                    payload.caseFileId = String.valueOf(cf.get('id'));
                }
            }
            
            if (data.containsKey('documentId')) {
                payload.documentId = String.valueOf(data.get('documentId'));
            } else if (data.containsKey('document')) {
                Map<String, Object> doc = (Map<String, Object>) data.get('document');
                if (doc != null) {
                    payload.documentId = String.valueOf(doc.get('id'));
                }
            }
            
            if (data.containsKey('signerId')) {
                payload.signerId = String.valueOf(data.get('signerId'));
            } else if (data.containsKey('signer')) {
                Map<String, Object> signer = (Map<String, Object>) data.get('signer');
                if (signer != null) {
                    payload.signerId = String.valueOf(signer.get('id'));
                }
            }
            
            // Raw data for additional processing
            payload.rawData = data;
            
            return payload;
            
        } catch (Exception e) {
            System.debug('Error parsing webhook payload: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Verify webhook signature using shared secret
     * Penneo signs webhooks with HMAC-SHA256
     */
    private static Boolean verifySignature(RestRequest req) {
        // Get the signature from header
        String signature = req.headers.get('X-Penneo-Signature');
        
        // If no signature header, check if signature verification is required
        if (String.isBlank(signature)) {
            // Load settings to check if we have a webhook secret
            PenneoAuthService.ProviderSettings settings = PenneoAuthService.getSettings('sandbox');
            
            // If no webhook secret configured, skip verification
            if (settings == null || String.isBlank(settings.webhookSecret)) {
                return true;
            }
            
            // Secret configured but no signature provided - reject
            return false;
        }
        
        // Get settings with webhook secret
        PenneoAuthService.ProviderSettings settings = PenneoAuthService.getSettings('sandbox');
        if (settings == null || String.isBlank(settings.webhookSecret)) {
            // No secret to verify against - accept
            return true;
        }
        
        // Compute expected signature
        String body = req.requestBody.toString();
        String expectedSignature = computeHmacSha256(body, settings.webhookSecret);
        
        // Compare signatures (constant time comparison to prevent timing attacks)
        return constantTimeEquals(signature, expectedSignature);
    }
    
    /**
     * Compute HMAC-SHA256 signature
     */
    private static String computeHmacSha256(String data, String key) {
        Blob signatureBlob = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(data),
            Blob.valueOf(key)
        );
        return EncodingUtil.base64Encode(signatureBlob);
    }
    
    /**
     * Constant-time string comparison to prevent timing attacks
     */
    private static Boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null) {
            return false;
        }
        if (a.length() != b.length()) {
            return false;
        }
        Integer result = 0;
        for (Integer i = 0; i < a.length(); i++) {
            result |= a.charAt(i) ^ b.charAt(i);
        }
        return result == 0;
    }
    
    /**
     * Process the webhook and update Signature_Request__c
     */
    private static void processWebhook(WebhookPayload payload) {
        // Find the matching Signature_Request__c record
        List<Signature_Request__c> requests = findSignatureRequests(payload);
        
        if (requests.isEmpty()) {
            System.debug('No matching Signature_Request__c found for case file: ' + payload.caseFileId);
            // Still return success - we don't want Penneo to retry for records we don't have
            return;
        }
        
        // Determine the new status
        String newStatus = EVENT_TO_STATUS.get(payload.eventType);
        if (String.isBlank(newStatus)) {
            newStatus = 'Unknown';
        }
        
        // Update the records
        List<Signature_Request__c> toUpdate = new List<Signature_Request__c>();
        
        for (Signature_Request__c req : requests) {
            req.Status__c = newStatus;
            
            // Set completed date if signed/completed
            if (newStatus == 'Signed' || newStatus == 'Completed') {
                req.Completed_Date__c = Datetime.now();
                
                // Queue download of signed document (async)
                queueSignedDocumentDownload(req.Id);
            }
            
            toUpdate.add(req);
        }
        
        if (!toUpdate.isEmpty()) {
            update toUpdate;
            System.debug('Updated ' + toUpdate.size() + ' Signature_Request__c records to status: ' + newStatus);
        }
    }
    
    /**
     * Find Signature_Request__c records matching the webhook
     */
    private static List<Signature_Request__c> findSignatureRequests(WebhookPayload payload) {
        // First try to find by case file ID
        if (String.isNotBlank(payload.caseFileId)) {
            List<Signature_Request__c> byCase = [
                SELECT Id, Status__c, External_Case_ID__c, External_Document_ID__c, External_Signer_ID__c
                FROM Signature_Request__c
                WHERE External_Case_ID__c = :payload.caseFileId
                LIMIT 10
            ];
            if (!byCase.isEmpty()) {
                return byCase;
            }
        }
        
        // Try by document ID
        if (String.isNotBlank(payload.documentId)) {
            List<Signature_Request__c> byDoc = [
                SELECT Id, Status__c, External_Case_ID__c, External_Document_ID__c, External_Signer_ID__c
                FROM Signature_Request__c
                WHERE External_Document_ID__c = :payload.documentId
                LIMIT 10
            ];
            if (!byDoc.isEmpty()) {
                return byDoc;
            }
        }
        
        // Try by signer ID
        if (String.isNotBlank(payload.signerId)) {
            List<Signature_Request__c> bySigner = [
                SELECT Id, Status__c, External_Case_ID__c, External_Document_ID__c, External_Signer_ID__c
                FROM Signature_Request__c
                WHERE External_Signer_ID__c = :payload.signerId
                LIMIT 10
            ];
            if (!bySigner.isEmpty()) {
                return bySigner;
            }
        }
        
        return new List<Signature_Request__c>();
    }
    
    /**
     * Queue async job to download signed document
     */
    private static void queueSignedDocumentDownload(Id signatureRequestId) {
        // Use Queueable for async processing
        System.enqueueJob(new DownloadSignedDocumentJob(signatureRequestId));
    }
    
    /**
     * Response wrapper class
     */
    global class WebhookResponse {
        public Boolean success;
        public String message;
    }
    
    /**
     * Webhook payload wrapper
     */
    public class WebhookPayload {
        public String eventId;
        public String eventType;
        public String timestamp;
        public String caseFileId;
        public String documentId;
        public String signerId;
        public Map<String, Object> rawData;
    }
    
    /**
     * Queueable job to download signed document
     */
    public class DownloadSignedDocumentJob implements Queueable, Database.AllowsCallouts {
        private Id signatureRequestId;
        
        public DownloadSignedDocumentJob(Id requestId) {
            this.signatureRequestId = requestId;
        }
        
        public void execute(QueueableContext context) {
            try {
                // Get the signature request
                Signature_Request__c req = [
                    SELECT Id, External_Document_ID__c, Journal__c, Account__c, 
                           Shared_Document__c, Signer_Name__c, Market_Unit__c
                    FROM Signature_Request__c
                    WHERE Id = :signatureRequestId
                    LIMIT 1
                ];
                
                if (String.isBlank(req.External_Document_ID__c)) {
                    System.debug('No document ID to download for request: ' + signatureRequestId);
                    return;
                }
                
                // Download the signed PDF
                Integer documentId = Integer.valueOf(req.External_Document_ID__c);
                PenneoApiService.SignedDocumentResponse docResp = PenneoApiService.downloadSignedDocument(documentId);
                
                if (!docResp.success) {
                    System.debug('Failed to download signed document: ' + docResp.errorMessage);
                    // Update error message on record
                    req.Error_Message__c = 'Download failed: ' + docResp.errorMessage;
                    update req;
                    return;
                }
                
                // Create ContentVersion for the signed PDF
                String fileName = 'Signed_Document_' + req.Name + '.pdf';
                ContentVersion cv = new ContentVersion();
                cv.Title = fileName;
                cv.PathOnClient = fileName;
                cv.VersionData = docResp.content;
                cv.Origin = 'C'; // Content origin
                insert cv;
                
                // Get the ContentDocumentId
                cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
                
                // Link to Signature Request
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = cv.ContentDocumentId;
                cdl.LinkedEntityId = req.Id;
                cdl.ShareType = 'V'; // Viewer permission
                cdl.Visibility = 'AllUsers';
                insert cdl;
                
                // Also link to Account if available
                if (req.Account__c != null) {
                    ContentDocumentLink cdlAccount = new ContentDocumentLink();
                    cdlAccount.ContentDocumentId = cv.ContentDocumentId;
                    cdlAccount.LinkedEntityId = req.Account__c;
                    cdlAccount.ShareType = 'V';
                    cdlAccount.Visibility = 'AllUsers';
                    insert cdlAccount;
                }
                
                // Update signature request with signed document ID
                req.Signed_Document_ID__c = cv.ContentDocumentId;
                req.Status__c = 'Completed';
                req.Error_Message__c = null;
                update req;
                
                System.debug('Successfully downloaded and stored signed document for request: ' + signatureRequestId);
                
            } catch (Exception e) {
                System.debug('Error in DownloadSignedDocumentJob: ' + e.getMessage() + '\n' + e.getStackTraceString());
                
                // Try to update error on record
                try {
                    Signature_Request__c req = new Signature_Request__c(Id = signatureRequestId);
                    req.Error_Message__c = 'Download job error: ' + e.getMessage();
                    update req;
                } catch (Exception e2) {
                    System.debug('Could not update error message: ' + e2.getMessage());
                }
            }
        }
    }
}
