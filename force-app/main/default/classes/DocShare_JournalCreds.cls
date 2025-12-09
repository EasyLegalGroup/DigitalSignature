public with sharing class DocShare_JournalCreds {
    public class Creds {
        @AuraEnabled public Id     journalId;
        @AuraEnabled public String externalId;
        @AuraEnabled public String accessToken;

        // Page header / context data
        @AuraEnabled public String marketUnit;
        @AuraEnabled public String host;          // derived from marketUnit via DokHost
        @AuraEnabled public String customerName;  // Account.Name
        @AuraEnabled public String phone;         // prefer PersonMobilePhone, else Account.Phone
        @AuraEnabled public String email;         // PersonEmail (if available)
    }

    @AuraEnabled
    public static Creds getOrCreate(Id journalId) {
        if (journalId == null) {
            throw new AuraHandledException('journalId is required.');
        }

        // Lock the Journal row; select only fields we always have
        Journal__c j = [
            SELECT Id, External_ID__c, Access_Token__c, Market_Unit__c, Account__c
            FROM Journal__c
            WHERE Id = :journalId
            FOR UPDATE
        ];

        Boolean changed = false;
        if (String.isBlank(j.External_ID__c)) {
            j.External_ID__c = generateExternalId();     // 12 hex chars
            changed = true;
        }
        if (String.isBlank(j.Access_Token__c)) {
            j.Access_Token__c = generateAccessToken();   // 128 hex chars
            changed = true;
        }
        if (changed) {
            update j;
        }

        Creds out = new Creds();
        out.journalId   = j.Id;
        out.externalId  = j.External_ID__c;
        out.accessToken = j.Access_Token__c;

        // Market + host
        out.marketUnit = j.Market_Unit__c;
        out.host       = DokHost.forMarket(out.marketUnit);

        // --- Optional parent Account info (works with or without Person Accounts) ---
        if (j.Account__c != null) {
            // Build a dynamic SELECT for Account fields that exist in this org
            Map<String, Schema.SObjectField> fMap = Schema.SObjectType.Account.fields.getMap();
            List<String> fields = new List<String>{ 'Id', 'Name', 'Phone' };
            if (fMap.containsKey('PersonEmail'))        fields.add('PersonEmail');
            if (fMap.containsKey('PersonMobilePhone'))  fields.add('PersonMobilePhone');

            String soql = 'SELECT ' + String.join(fields, ',') +
                          ' FROM Account WHERE Id = \'' + String.escapeSingleQuotes(String.valueOf(j.Account__c)) + '\'';
            SObject acc = Database.query(soql);

            out.customerName = (String) acc.get('Name');

            String personMobile = (String) acc.get('PersonMobilePhone'); // may be null if field not present/selected
            String stdPhone     = (String) acc.get('Phone');
            out.phone = !String.isBlank(personMobile) ? personMobile : stdPhone;

            String personEmail  = (String) acc.get('PersonEmail');
            out.email = personEmail; // null if not present
        }

        return out;
    }

    // 12 hex chars (from 32 random bytes, truncated safely)
    private static String generateExternalId() {
        Blob b = Crypto.generateAesKey(256);            // 32 bytes
        String hex = EncodingUtil.convertToHex(b);      // 64 hex chars
        return hex.substring(0, 12);
    }
    // 128 hex chars (~64 bytes entropy)
    private static String generateAccessToken() {
        Blob b1 = Crypto.generateAesKey(256);
        Blob b2 = Crypto.generateAesKey(256);
        return EncodingUtil.convertToHex(b1) + EncodingUtil.convertToHex(b2);
    }
}