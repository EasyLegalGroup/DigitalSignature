# Digital Signature Integration for Salesforce

A Salesforce integration for sending documents for digital signature via Penneo. This project allows you to send PDFs to customers for signing, track signature status, and download signed documents.

## 🏗️ Project Structure

```
force-app/main/default/
├── classes/
│   ├── PenneoAuthService.cls       # OAuth token management & WSSE digest
│   ├── PenneoApiService.cls        # Penneo API calls (case files, jobs, downloads)
│   ├── PenneoWebhookHandler.cls    # REST endpoint for Penneo callbacks
│   ├── SignatureRequestService.cls # Main service layer for LWC
│   └── *_Test.cls                  # Test classes (36 tests total)
├── lwc/
│   ├── signatureRequestModal/      # Modal for creating signature requests
│   └── journalDocConsole/          # Document console with "Sign" button
├── objects/
│   ├── Signature_Request__c/       # Custom object for tracking signatures
│   └── Signature_Provider_Settings__mdt/ # Custom metadata for API config
└── permissionsets/
    └── Signature_Admin.permissionset-meta.xml
```

## ✅ What's Completed

- [x] **Signature_Request__c** - Custom object with fields for tracking signature requests
- [x] **Signature_Provider_Settings__mdt** - Custom metadata for API credentials
- [x] **PenneoAuthService** - OAuth 2.0 API Keys Grant authentication with WSSE digest
- [x] **PenneoApiService** - API integration for case files, jobs, and document download
- [x] **PenneoWebhookHandler** - REST endpoint for receiving Penneo webhook events
- [x] **SignatureRequestService** - Service layer with @AuraEnabled methods
- [x] **signatureRequestModal LWC** - UI for creating and viewing signature requests
- [x] **journalDocConsole updates** - Added "Sign" button to document rows
- [x] **Test classes** - 36 tests with 100% pass rate
- [x] **Deployed to sandbox** - All components deployed to penneo-sandbox org

---

## 🔑 NEXT STEPS: Getting Your Penneo OAuth Credentials

### Understanding the Two Types of Credentials

Penneo uses **two separate sets of credentials**:

| Credential Type | What It Is | Where to Get It |
|-----------------|------------|-----------------|
| **API Key & Secret** | Used for WSSE digest authentication (already configured) | Penneo Admin → API Keys |
| **OAuth Client ID & Secret** | Used for OAuth 2.0 token exchange (**STILL NEEDED**) | Penneo Admin → OAuth Clients |

The API Key/Secret we have (`ee9907e6...`) is for signing API requests. But to get OAuth access tokens, we also need a **Client ID and Client Secret**.

### Step-by-Step: Getting OAuth Client Credentials

#### 1. Log in to Penneo Admin Dashboard

- **Sandbox**: https://sandbox.penneo.com/admin
- **Production**: https://app.penneo.com/admin

#### 2. Navigate to API Settings

1. Click on your **company name** or **profile icon** in the top-right corner
2. Select **"Settings"** or **"Administration"**
3. Look for **"API"**, **"Integrations"**, or **"Developer"** section in the left sidebar

#### 3. Create an OAuth Client

1. Click **"Create OAuth Client"** or **"Add New Client"** or similar button
2. Fill in the form:
   - **Name**: `Salesforce Integration` (or any descriptive name)
   - **Grant Type**: Select **"API Keys"** (also called "Client Credentials with API Keys")
   - **Scopes**: Select **"Full Access"** or the specific scopes needed

#### 4. Copy Your Credentials

After creating the client, you'll see:

- **Client ID**: A UUID like `a1b2c3d4-e5f6-7890-abcd-ef1234567890`
- **Client Secret**: A long random string

⚠️ **CRITICAL**: Copy the Client Secret immediately! You will only see it once. If you lose it, you'll need to create a new client.

#### 5. Update Salesforce Custom Metadata

1. Go to **Salesforce Setup**
2. Search for **"Custom Metadata Types"**
3. Find **"Signature Provider Settings"** and click **"Manage Records"**
4. Click **Edit** on the **"Penneo_Sandbox"** record
5. Fill in:
   - **Client_ID__c** = your OAuth Client ID
   - **Client_Secret__c** = your OAuth Client Secret
6. Click **Save**

### If You Can't Find OAuth Settings

Contact Penneo support:
- **Email**: support@penneo.com
- **Subject**: "Need OAuth Client credentials for API Keys Grant"
- **Message**: "We are building a Salesforce integration and need to create an OAuth Client for the API Keys Grant flow. Can you help us set this up or point us to the right location in the admin dashboard?"

---

## 🌐 NEXT STEPS: Setting Up Salesforce Site for Webhooks

Penneo sends webhook callbacks when signatures are completed. This requires a public-facing URL that Penneo can reach.

### Step 1: Create a Salesforce Site

1. **Go to Setup** → search for **"Sites"**
2. Click **"New"** to create a new site
3. Fill in:
   - **Site Label**: `Signature Webhooks`
   - **Site Name**: `signaturewebhooks`
   - **Active**: ✅ Checked
   - **Default Web Address**: Choose an available subdomain (e.g., `signaturewebhooks`)
   - **Active Site Home Page**: Select any Visualforce page (required, can be a blank page)
4. Click **Save**

5. **Note Your Site URL** - It will look like:
   - Sandbox: `https://yourorg--penneo.sandbox.my.salesforce-sites.com`
   - Production: `https://yourorg.my.salesforce-sites.com`

### Step 2: Grant Public Access to the REST Endpoint

1. Go to **Setup** → **Sites**
2. Click on your site name
3. Click **"Public Access Settings"** button
4. This opens the Site Guest User profile
5. Scroll down to **"Enabled Apex Class Access"** and click **Edit**
6. Add `PenneoWebhookHandler` to the enabled list
7. Click **Save**

### Step 3: Configure the Webhook URL in Penneo

1. Log in to **Penneo Admin Dashboard**
2. Go to **Settings** → **Webhooks** (or **Integrations** → **Webhooks**)
3. Click **"Add Webhook"** or **"Create New"**
4. Configure:
   - **URL**: `https://[your-site-url]/services/apexrest/webhook/signature`
   - **Events**: Select all relevant events:
     - ✅ `signer.completed` - When a signer finishes signing
     - ✅ `casefile.signed` - When all signers have signed
     - ✅ `signer.rejected` - When a signer rejects
     - ✅ `casefile.expired` - When a case file expires

5. **If Penneo provides a Webhook Secret**, copy it and add to your Custom Metadata:
   - Field: `Webhook_Secret__c`

### Step 4: Test the Webhook Endpoint

Test that your endpoint is publicly accessible:

```powershell
# Using PowerShell
Invoke-RestMethod -Method Post -Uri "https://[your-site-url]/services/apexrest/webhook/signature" `
  -ContentType "application/json" `
  -Body '{"eventType": "test"}'
```

---

## 📥 NEXT STEPS: Downloading Signed PDFs

When documents are signed, Penneo stores them and provides download links. The current implementation downloads via Penneo's API.

### How It Works

1. When Penneo sends a `casefile.signed` webhook, the `PenneoWebhookHandler` receives it
2. The handler calls `PenneoApiService.downloadSignedDocument(caseFileId)`
3. The signed PDF is returned as a Blob
4. You can then store it in Salesforce Files or wherever needed

### To Complete This Feature

Add logic to save the downloaded PDF:

```apex
// In SignatureRequestService.cls or a new class
public static void saveSignedDocument(Id signatureRequestId, Blob pdfContent) {
    Signature_Request__c sr = [SELECT Id, Shared_Document__c, Account__c FROM Signature_Request__c WHERE Id = :signatureRequestId];
    
    // Create ContentVersion
    ContentVersion cv = new ContentVersion();
    cv.Title = 'Signed Document';
    cv.PathOnClient = 'signed_document.pdf';
    cv.VersionData = pdfContent;
    insert cv;
    
    // Link to Signature Request
    ContentDocumentLink cdl = new ContentDocumentLink();
    cdl.ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    cdl.LinkedEntityId = sr.Id;
    cdl.ShareType = 'V';
    insert cdl;
}
```

---

## 🧪 Running Tests

### Run All Local Tests
```powershell
sf apex run test --target-org penneo-sandbox --test-level RunLocalTests --wait 10
```

### Run Specific Test Classes
```powershell
# Penneo API tests
sf apex run test --target-org penneo-sandbox --class-names PenneoService_Test --wait 10

# Signature service tests  
sf apex run test --target-org penneo-sandbox --class-names SignatureService_Test --wait 10
```

### Expected Results
- **Total Tests**: 36
- **Pass Rate**: 100%

---

## 🚀 Deployment Commands

### Deploy to Sandbox
```powershell
sf project deploy start --target-org penneo-sandbox
```

### Deploy to Production (with tests)
```powershell
sf project deploy start --target-org production --test-level RunLocalTests
```

### Check Deployment Status
```powershell
sf project deploy report --target-org penneo-sandbox
```

---

## 📋 Pre-Production Checklist

Before going live, ensure you have completed:

### Credentials
- [ ] **OAuth Client ID** - Obtained from Penneo admin dashboard
- [ ] **OAuth Client Secret** - Obtained from Penneo admin dashboard
- [ ] **API Key** - ✅ Already configured
- [ ] **API Secret** - ✅ Already configured

### Salesforce Configuration
- [ ] **Salesforce Site created** - For webhook endpoint
- [ ] **Public Access granted** - PenneoWebhookHandler enabled for guest users
- [ ] **Permission Set assigned** - `Signature_Admin` to appropriate users

### Penneo Configuration
- [ ] **Webhook URL registered** - Your Salesforce Site URL in Penneo
- [ ] **Webhook events selected** - signer.completed, casefile.signed, etc.
- [ ] **Webhook secret stored** - In Custom Metadata (if provided)

### Testing
- [ ] **End-to-end test** - Send a test document, sign it, verify webhook received
- [ ] **Error handling verified** - Test with invalid data, expired tokens

---

## 📊 Custom Object: Signature_Request__c

| Field | Type | Description |
|-------|------|-------------|
| `Account__c` | Lookup(Account) | The customer (PersonAccount) |
| `Journal__c` | Lookup(Journal__c) | The journal this relates to |
| `Shared_Document__c` | Lookup(Shared_Document__c) | The document being signed |
| `Status__c` | Picklist | New, Pending, Sent, Opened, Signed, Completed, Rejected, Expired, Failed |
| `Signer_Name__c` | Text | Full name of the signer |
| `Signer_Email__c` | Email | Email address for signing link |
| `External_Case_ID__c` | Text | Penneo Case File ID |
| `Signature_UUID__c` | Text | Penneo Signer UUID |
| `Signing_Link__c` | URL | Link sent to signer |
| `Payload_Hash__c` | Text | SHA-256 hash for integrity |
| `Signed_At__c` | DateTime | When document was signed |
| `Completed_At__c` | DateTime | When case file was completed |
| `Provider__c` | Text | "Penneo" (for multi-provider support) |

---

## 🔒 Security Best Practices

1. **Secrets in Protected Fields** - Client secrets are stored in protected Custom Metadata fields
2. **Webhook Validation** - Verify webhook signatures when provided by Penneo
3. **HTTPS Only** - All API communication uses HTTPS
4. **Permission-Based Access** - Use permission sets to limit who can create signature requests
5. **Audit Trail** - All signature requests are tracked with timestamps

---

## 🐛 Troubleshooting

### "Invalid OAuth credentials" Error
- Verify Client ID and Client Secret are correctly entered in Custom Metadata
- Check if you're using sandbox credentials against production or vice versa

### "Token expired" Error
- Tokens expire after 600 seconds (10 minutes)
- The system automatically refreshes tokens; if issues persist, check API Key/Secret

### Webhook Not Receiving Events
- Verify the Salesforce Site is active
- Check that `PenneoWebhookHandler` is in the Site's Apex Class Access
- Test the URL directly with a POST request
- Check Penneo's webhook delivery logs

### "WSSE authentication failed" Error
- Verify API Key and API Secret are correct
- Check that server time is synchronized (WSSE is time-sensitive)

---

## 📞 Support Resources

- **Penneo Support**: support@penneo.com
- **Penneo API Docs**: https://penneo.readme.io/
- **Salesforce Developer Forums**: https://developer.salesforce.com/forums

---

## 📄 License

Internal use only - Easy Legal Group
