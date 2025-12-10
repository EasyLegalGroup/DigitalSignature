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
- [x] **Remote Site Settings** - Created for `app.penneo.com`, `oauth.penneo.cloud`, Lambda API Gateway, and S3
- [x] **Custom Metadata** - `Penneo_Production` record with production URLs configured

### Salesforce Components
- [x] **Signature_Request__c** - Custom object with fields for tracking signature requests
- [x] **PenneoApiService** - API integration for case files, jobs, and document download
- [x] **PenneoWebhookHandler** - REST endpoint for receiving Penneo webhook events
- [x] **SignatureRequestService** - Service layer with @AuraEnabled methods for signature requests
- [x] **signatureRequestModal LWC** - UI for creating and viewing signature requests
- [x] **journalDocConsole updates** - Added "Sign" button to document rows

### AWS Integration
- [x] **CORS Configuration** - Added Penneo sandbox origins to API Gateway
- [x] **Lambda Origins** - Updated `ALLOWED_ORIGINS` in `index.py` (dfj-docs-test Lambda)
- [x] **S3 Document Download** - Lambda endpoint `/internal/doc-content` returns presigned S3 URLs
- [x] **Apex S3 Integration** - `SignatureRequestService.downloadFromS3()` fetches documents via Lambda presigned URLs

### Signature Request Flow (Tested ✅)
- [x] **Document Retrieval** - S3 download working (33KB PDF successfully downloaded)
- [x] **Penneo API Call** - Request reaches Penneo with WSSE authentication
- [ ] **OAuth Token** - ⚠️ BLOCKED - Penneo Send API requires OAuth JWT token (see below)

### Deployed To
- **Salesforce Org**: `penneo-sandbox` (`mt@dinfamiliejurist.dk.penneo`)
- **AWS Lambda**: `dfj-docs-test` (test environment)

---

## 🚧 Currently Blocked: OAuth Credentials Required

**Status**: ⏳ Waiting on Penneo (expected December 11, 2025)

### The Issue

The Penneo **Send API** (`/send/api/v1/casefiles/`) requires OAuth authentication via `X-Auth-Token` header with a JWT token. The current WSSE authentication (API Key + Secret) only works with the standard API (`/api/v3/`), not the Send API.

**Error from Penneo**:
```json
{"message":"X-Auth-Token header is required","error":"Bad Request","statusCode":400}
```

### What's Needed from Penneo

1. **OAuth Client ID** - To be added to `Signature_Provider_Settings__mdt.OAuth_Client_ID__c`
2. **OAuth Client Secret** - To be added to `Signature_Provider_Settings__mdt.OAuth_Client_Secret__c`

### Once Received

1. Update custom metadata in Salesforce:
   ```apex
   // In Setup > Custom Metadata Types > Signature Provider Settings > Penneo_Production
   OAuth_Client_ID__c = 'provided-client-id'
   OAuth_Client_Secret__c = 'provided-client-secret'
   ```

2. Update `PenneoApiService.createCaseFile()` to use `X-Auth-Token` header:
   ```apex
   // The code already supports OAuth via PenneoAuthService.getAccessToken()
   // Just need to change header from 'Authorization: Bearer' to 'X-Auth-Token'
   req.setHeader('X-Auth-Token', accessToken);
   ```

3. Test the signature request flow again

---

## ✅ Resolved Issues

### 1. AWS Lambda 500 Error on `/upload-start`

**Status**: ✅ FIXED (December 10, 2025)

**Root Cause**: Missing External Client App in the penneo sandbox. The Lambda couldn't authenticate to Salesforce.

**Solution**:
1. Created **External Client App** (`DFJ_Doc_Presigner_Test`) in penneo sandbox
2. Generated OAuth Client ID and Secret
3. Obtained refresh token via OAuth authorization code flow
4. Updated Lambda environment variables:
   - `SF_CLIENT_ID`
   - `SF_CLIENT_SECRET`
   - `SF_REFRESH_TOKEN`
   - `SF_LOGIN_URL` = `https://test.salesforce.com`

**Verified**: Upload endpoint now returns presigned S3 URLs successfully.

### 2. S3 Document Download for Signature Requests

**Status**: ✅ FIXED (December 10, 2025)

**Root Cause**: `SignatureRequestService.downloadFromS3()` was a stub method returning null.

**Solution**:
1. Added Lambda endpoint `/internal/doc-content` to generate presigned S3 URLs
2. Created Remote Site Settings for Lambda API Gateway and S3 bucket
3. Implemented `downloadFromS3()` to:
   - Call Lambda to get presigned URL for the S3 key
   - Download document content directly from S3
   - Return PDF as Blob for Penneo API

**Verified**: Successfully downloads 33KB PDF from S3 bucket `dfj-docs-test`.

---

## 📋 Next Steps

### 1. Configure OAuth Credentials (Waiting on Penneo)
**Status**: ⏳ Blocked - ETA December 11, 2025

Once Penneo provides OAuth Client ID and Client Secret:
1. Add credentials to `Signature_Provider_Settings__mdt.Penneo_Production`
2. Update `PenneoApiService` to use `X-Auth-Token` header for Send API
3. Test signature request creation

### 2. Test Full Signature Request Flow
**Status**: 🔄 Ready once OAuth is configured

1. Open a Journal in Salesforce (penneo-sandbox)
2. Navigate to document console (`journalDocConsole` LWC)
3. Click "Sign" on a document with S3_Key__c populated
4. Fill in signer name and email
5. Submit - verify:
   - `Signature_Request__c` record created
   - PDF downloaded from S3 (✅ already working)
   - Case file created in Penneo
   - Signing link returned

### 3. Configure Penneo Webhooks
**Status**: ⏳ Pending

Set up webhooks to receive signature status updates:
1. Create a Salesforce Site for the webhook endpoint
2. Register webhook URL in Penneo admin
3. Test webhook delivery with a real signature

### 4. Production Deployment
**Status**: ⏳ Pending

When ready for production:
1. Deploy Salesforce components to production org
2. Update `Signature_Provider_Settings__mdt` with production credentials
3. Update Lambda environment for production
4. Test end-to-end flow in production

---

## 🔧 Environment Configuration

### Salesforce Custom Metadata (`Signature_Provider_Settings__mdt`)

| Field | Value |
|-------|-------|
| `Environment__c` | `production` |
| `API_Base_URL__c` | `https://app.penneo.com/api/v3` |
| `Send_API_Base_URL__c` | `https://app.penneo.com/send/api/v1` |
| `OAuth_Token_Endpoint__c` | `https://oauth.penneo.cloud/oauth/token` |
| `API_Key__c` | `ee9907e6...` (configured ✅) |
| `API_Secret__c` | (configured ✅) |
| `OAuth_Client_ID__c` | ⏳ **PENDING** - waiting on Penneo |
| `OAuth_Client_Secret__c` | ⏳ **PENDING** - waiting on Penneo |
| `Is_Active__c` | `true` |

### Remote Site Settings

| Name | URL | Purpose |
|------|-----|---------|
| `Penneo_Production` | `https://app.penneo.com` | Penneo API |
| `Penneo_OAuth` | `https://oauth.penneo.cloud` | OAuth token endpoint |
| `AWS_Lambda_Test` | `https://21tpssexjd.execute-api.eu-north-1.amazonaws.com` | Lambda for S3 presigned URLs |
| `AWS_S3_Test` | `https://dfj-docs-test.s3.amazonaws.com` | S3 document downloads |

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
