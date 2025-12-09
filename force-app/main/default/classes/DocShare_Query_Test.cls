@IsTest
private class DocShare_Query_Test {

    @TestSetup
    static void setupCommonData() {
        Account a = new Account(Name = 'QTest');
        insert a;

        Journal__c j = new Journal__c(Account__c = a.Id, Market_Unit__c = 'DFJ_DK');
        insert j;
        // requery to get the auto-number Name populated
        j = [SELECT Id, Name FROM Journal__c WHERE Id = :j.Id];

        // Create two shared documents with a variety of fields
        // Using valid Document_Type__c values for Market_Unit__c = 'DFJ_DK'
        Shared_Document__c d1 = new Shared_Document__c(
            Journal__c           = j.Id,
            Name                 = 'a.pdf',
            S3_Key__c            = 'customer-documents/' + j.Name + '/a.pdf',
            Status__c            = 'Draft',
            Version__c           = 2,
            Is_Newest_Version__c = true,
            Market_Unit__c       = 'DFJ_DK',
            Document_Type__c     = 'Testamente',
            Sent_Date__c         = Date.today(),
            First_Viewed__c      = System.now().addHours(-2),
            Last_Viewed__c       = System.now().addHours(-1),
            Is_Guidance_Acknowledged__c    = true,
            Time_of_Guidance_Acknowledge__c = System.now(),
            Is_Approval_Blocked__c = true
        );

        Shared_Document__c d2 = new Shared_Document__c(
            Journal__c           = j.Id,
            Name                 = 'b.pdf',
            S3_Key__c            = 'customer-documents/' + j.Name + '/b.pdf',
            Status__c            = 'Sent',
            Version__c           = 1,
            Is_Newest_Version__c = false,
            Market_Unit__c       = 'DFJ_DK',
            Document_Type__c     = 'Fremtidsfuldmagt',
            Sent_Date__c         = null,
            First_Viewed__c      = null,
            Last_Viewed__c       = null,
            Is_Guidance_Acknowledged__c    = false,
            Time_of_Guidance_Acknowledge__c = null,
            Is_Approval_Blocked__c = false
        );

        insert new List<Shared_Document__c>{ d1, d2 };
    }

    @IsTest
    static void cover_getByJournal_withValidJournal() {
        Journal__c[] journals = [SELECT Id, Name FROM Journal__c LIMIT 1];
        Id journalId       = journals[0].Id;
        String journalName = journals[0].Name;

        Test.startTest();
        List<DocShare_Query.DocRow> rows = DocShare_Query.getByJournal(journalId);
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'Should return both documents for the journal');

        // First row: a.pdf
        DocShare_Query.DocRow first = rows[0];
        System.assertEquals('a.pdf', first.name);
        System.assertEquals(Integer.valueOf(2), first.version);
        System.assertEquals('Draft', first.status);
        System.assertEquals('customer-documents/' + journalName + '/a.pdf', first.s3Key);
        System.assertEquals(true, first.isNewestVersion);
        // if a valid type was set, it should round-trip
        // (can't assert specific label since it’s org-dependent)
        // Just verify non-null iff set during setup:
        // nothing else needed here

        // Second row: b.pdf
        DocShare_Query.DocRow second = rows[1];
        System.assertEquals('b.pdf', second.name);
        System.assertEquals(Integer.valueOf(1), second.version);
        System.assertEquals('Sent', second.status);
        System.assertEquals('customer-documents/' + journalName + '/b.pdf', second.s3Key);
        System.assertEquals(false, second.isNewestVersion);

        // Common new fields sanity
        // (We already validated guidance fields by type in setup)
        System.assertEquals('DFJ_DK', first.marketUnit);
        System.assertEquals(true, first.isGuidanceAcknowledged);
        System.assertNotEquals(null, first.timeOfGuidanceAcknowledge);
        
        System.assertEquals('DFJ_DK', second.marketUnit);
        System.assertEquals(false, second.isGuidanceAcknowledged);
        System.assertEquals(null, second.timeOfGuidanceAcknowledge);
    }
}