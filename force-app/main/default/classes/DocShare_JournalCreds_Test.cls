@IsTest
private class DocShare_JournalCreds_Test {
    @TestSetup
    static void data() {
        Account a = new Account(Name = 'Creds Test Acct', Phone = '+4512345678');
        insert a;

        // One journal with blanks (to test generation)
        insert new Journal__c(Account__c = a.Id, Market_Unit__c = 'DFJ_DK');

        // One journal with prefilled values (to test idempotency)
        insert new Journal__c(
            Account__c      = a.Id,
            Market_Unit__c  = 'FA_SE',
            External_ID__c  = 'preext123456',
            Access_Token__c = 'aabbccddeeff' + '00112233445566778899aabbccddeeff' +
                              'ffeeddccbbaa' + '11223344556677889900aabbccddeeff'
        );
    }

    @IsTest
    static void generates_when_blank() {
        Journal__c j = [SELECT Id FROM Journal__c
                        WHERE External_ID__c = NULL
                        LIMIT 1];

        Test.startTest();
        DocShare_JournalCreds.Creds c = DocShare_JournalCreds.getOrCreate(j.Id);
        Test.stopTest();

        System.assertEquals(j.Id, c.journalId);
        System.assert(!String.isBlank(c.externalId), 'externalId should be generated');
        System.assert(!String.isBlank(c.accessToken), 'accessToken should be generated');

        Journal__c after = [SELECT External_ID__c, Access_Token__c, Market_Unit__c
                            FROM Journal__c WHERE Id = :j.Id];
        System.assertEquals(c.externalId, after.External_ID__c);
        System.assertEquals(c.accessToken, after.Access_Token__c);
        System.assertEquals(12, c.externalId.length(), 'externalId should be 12 hex chars');
        System.assertEquals(128, c.accessToken.length(), 'accessToken should be 128 hex chars');

        // Header info present and mapped
        System.assertEquals(after.Market_Unit__c, c.marketUnit);
        System.assertEquals('Creds Test Acct', c.customerName);
        System.assertEquals('+4512345678', c.phone);
        System.assertEquals('https://dok.dinfamiliejurist.dk', c.host);
        // email may be null in tests (business Account)
    }

    @IsTest
    static void idempotent_when_present() {
        Journal__c j = [SELECT Id, External_ID__c, Access_Token__c
                        FROM Journal__c
                        WHERE External_ID__c != NULL
                        LIMIT 1];

        String extBefore = j.External_ID__c;
        String tokBefore = j.Access_Token__c;

        Test.startTest();
        DocShare_JournalCreds.Creds c = DocShare_JournalCreds.getOrCreate(j.Id);
        Test.stopTest();

        System.assertEquals(extBefore, c.externalId, 'Should not change existing External_ID__c');
        System.assertEquals(tokBefore, c.accessToken, 'Should not change existing Access_Token__c');

        Journal__c after = [SELECT External_ID__c, Access_Token__c FROM Journal__c WHERE Id = :j.Id];
        System.assertEquals(extBefore, after.External_ID__c);
        System.assertEquals(tokBefore, after.Access_Token__c);

        // Market/host come through, host should match FA_SE
        System.assertEquals('FA_SE', c.marketUnit);
        System.assertEquals('https://dok.dinfamiljejurist.se', c.host);
    }

    @IsTest
    static void throws_when_null_id() {
        Boolean threw = false;
        try {
            DocShare_JournalCreds.getOrCreate(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should throw when journalId is null');
    }
}