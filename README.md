# Digital Signature Integration for Salesforce

A Salesforce integration for sending documents for digital signature via Penneo. This project allows you to send PDFs to customers for signing, track signature status, and download signed documents.

## 🏗️ Project Structure

```
force-app/main/default/
├── classes/
│   ├── PenneoAuthService.cls       # WSSE authentication for Penneo API
│   ├── PenneoApiService.cls        # Penneo API calls (case files, jobs, downloads)
│   ├── PenneoWebhookHandler.cls    # REST endpoint for Penneo callbacks
│   ├── SignatureRequestService.cls # Main service layer for LWC
│   └── *_Test.cls                  # Test classes
├── lwc/
│   ├── signatureRequestModal/      # Modal for creating signature requests
│   └── journalDocConsole/          # Document console with "Sign" button
├── objects/
│   ├── Signature_Request__c/       # Custom object for tracking signatures
│   ├── Shared_Document__c/         # Documents stored in S3
│   └── Signature_Provider_Settings__mdt/ # Custom metadata for API config
├── customMetadata/
│   └── Signature_Provider_Settings__mdt.Penneo_Production.md-meta.xml
└── remoteSiteSettings/
    ├── Penneo_Production.remoteSite-meta.xml
    └── Penneo_OAuth.remoteSite-meta.xml
```

## ✅ What's Been Completed (December 10, 2025)

### Penneo API Integration
- [x] **WSSE Authentication** - Implemented in `PenneoAuthService.cls` using API Key + Secret
- [x] **API Connection Test** - Successfully tested against Penneo Production API
- [x] **Remote Site Settings** - Created for `app.penneo.com` and `oauth.penneo.cloud`
- [x] **Custom Metadata** - `Penneo_Production` record with production URLs configured

### Salesforce Components
- [x] **Signature_Request__c** - Custom object with fields for tracking signature requests
- [x] **PenneoApiService** - API integration for case files, jobs, and document download
- [x] **PenneoWebhookHandler** - REST endpoint for receiving Penneo webhook events
- [x] **SignatureRequestService** - Service layer with @AuraEnabled methods
- [x] **signatureRequestModal LWC** - UI for creating and viewing signature requests
- [x] **journalDocConsole updates** - Added "Sign" button to document rows

### AWS Integration
- [x] **CORS Configuration** - Added Penneo sandbox origins to API Gateway
- [x] **Lambda Origins** - Updated `ALLOWED_ORIGINS` in `index.py` (dfj-docs-test Lambda)

### Deployed To
- **Salesforce Org**: `penneo` sandbox (`mt@dinfamiliejurist.dk.penneo`)
- **AWS Lambda**: `dfj-docs-test` (test environment)

---

## 🔴 Current Issues

### 1. AWS Lambda 500 Error on `/upload-start`

**Status**: ❌ Blocking document uploads

**Symptoms**:
```
POST https://21tpssexjd.execute-api.eu-north-1.amazonaws.com/upload-start
Status: 500 Internal Server Error
Response: {"error": "Server error"}
```

**Request payload**:
```json
{
  "externalId": "776f9a2c5086",
  "accessToken": "84781175ce45...",
  "files": [{"name": "J-0058318.pdf", "size": 42282, "type": "application/pdf"}]
}
```

**Possible causes**:
- Lambda environment variables not configured (SF credentials, S3 bucket, etc.)
- Missing IAM permissions for S3 access
- Salesforce connected app not set up for test environment

**To debug**:
1. Check CloudWatch logs for `dfj-docs-test` Lambda
2. Verify environment variables are set:
   - `SF_CLIENT_ID`
   - `SF_CLIENT_SECRET`
   - `SF_REFRESH_TOKEN`
   - `DOCS_BUCKET` (should be `dfj-docs-test`)
3. Verify Lambda has S3 permissions for the test bucket

### 2. Document Content Retrieval

**Status**: ⚠️ Not yet tested

The signature flow requires downloading PDF content from S3 before sending to Penneo. This happens in `SignatureRequestService.getDocumentContent()`.

**Flow**:
1. User clicks "Sign" on a document in `journalDocConsole`
2. Modal opens, user fills in signer details
3. `SignatureRequestService.createSignatureRequest()` is called
4. Service queries `Shared_Document__c.S3_Key__c`
5. Downloads PDF from S3 via presigned URL
6. Sends PDF content to Penneo API

**Blocker**: Need S3 upload working first to have documents to sign.

---

## 🔧 Environment Configuration

### Salesforce Custom Metadata (`Signature_Provider_Settings__mdt`)

| Field | Value |
|-------|-------|
| `Environment__c` | `production` |
| `API_Base_URL__c` | `https://app.penneo.com/api/v3` |
| `Send_API_Base_URL__c` | `https://app.penneo.com/send/api/v1` |
| `OAuth_Token_URL__c` | `https://oauth.penneo.cloud/oauth/token` |
| `API_Key__c` | `ee9907e6...` (configured) |
| `API_Secret__c` | (configured) |
| `Is_Active__c` | `true` |

### AWS Test Environment

| Component | Value |
|-----------|-------|
| API Gateway | `https://21tpssexjd.execute-api.eu-north-1.amazonaws.com` |
| Lambda | `dfj-docs-test` |
| S3 Bucket | `dfj-docs-test` |
| Region | `eu-north-1` |

### CORS Allowed Origins (API Gateway)

```
https://dfj--penneo.sandbox.lightning.force.com
https://dfj--penneo.sandbox.my.salesforce.com
https://dfj--itdevops.sandbox.lightning.force.com
https://dfj--itdevops.sandbox.my.salesforce.com
https://dfj--itdevopsi.sandbox.lightning.force.com
https://dfj--itdevopsi.sandbox.my.salesforce.com
http://localhost:5173
https://dok-test.dinfamiliejurist.dk
https://dok-test.dinfamiljejurist.se
https://docs-test.hereslaw.ie
```

---

## 🧪 Testing

### Test Penneo API Connection

Run in Anonymous Apex:
```apex
System.debug(JSON.serializePretty(PenneoApiService.testConnection()));
```

Or via CLI:
```bash
sf apex run --target-org penneo --file scripts/apex/test-penneo-wsse.apex
```

**Expected output**:
```json
{
  "success": true,
  "statusCode": 200,
  "authMode": "WSSE",
  "environment": "production"
}
```

### Test AWS API Gateway (from terminal)

```bash
# Test CORS
curl -s -I -X OPTIONS "https://21tpssexjd.execute-api.eu-north-1.amazonaws.com/upload-start" \
  -H "Origin: https://dfj--penneo.sandbox.lightning.force.com" \
  -H "Access-Control-Request-Method: POST"

# Test endpoint
curl -s "https://21tpssexjd.execute-api.eu-north-1.amazonaws.com/upload-start" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Origin: https://dfj--penneo.sandbox.lightning.force.com" \
  -d '{"externalId":"test","accessToken":"test","files":[{"name":"test.pdf","size":1000,"type":"application/pdf"}]}'
```

---

## 📋 Next Steps

1. **Debug Lambda 500 error** - Check CloudWatch logs, verify environment variables
2. **Test document upload** - Once Lambda is working, test full upload flow
3. **Test signature request** - Create a signature request with a real document
4. **Configure webhooks** - Set up Penneo webhook to receive signature status updates
5. **Production deployment** - Deploy to production Salesforce org when ready

---

## 🔗 Useful Links

- [Penneo API Documentation](https://app.penneo.com/api/docs)
- [Penneo Sign API Guide](https://penneo.readme.io/)
- [Salesforce DX CLI](https://developer.salesforce.com/tools/salesforcecli)

---

## 📝 Development Commands

```bash
# Deploy to sandbox
sf project deploy start --target-org penneo --ignore-conflicts

# Run Apex tests
sf apex run test --target-org penneo --code-coverage

# Run anonymous Apex
sf apex run --target-org penneo --file scripts/apex/test-penneo-wsse.apex

# View org
sf org open --target-org penneo
```
