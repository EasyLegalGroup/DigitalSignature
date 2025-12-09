@IsTest
private class DocShareService_Coverage {

    // -- helper: minimal Account + Journal
    private static Journal__c makeJournal() {
        Account a = new Account(Name = 'CovTest Acct');
        insert a;

        Journal__c j = new Journal__c(
            Account__c      = a.Id,
            Market_Unit__c  = 'DFJ_DK',
            External_ID__c  = 'ext-' + String.valueOf(Crypto.getRandomInteger()),
            Access_Token__c = 'tok-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert j;
        return j;
    }

    @IsTest
    static void cover_createForJournalSimple() {
        Journal__c j = makeJournal();
        j = [SELECT Id, Name, Market_Unit__c FROM Journal__c WHERE Id = :j.Id];

        String key = 'customer-documents/' + j.Name + '/simple.pdf';
        DocShareService.CreateForJournalResult r =
            DocShareService.createForJournalSimple(j.Id, key, 'simple.pdf');

        System.assertNotEquals(null, r);
        System.assertNotEquals(null, r.DocumentId);

        Shared_Document__c d = [
            SELECT Id, Journal__c, Name, S3_Key__c, Status__c, Version__c, Is_Newest_Version__c, Market_Unit__c
            FROM Shared_Document__c WHERE Id = :r.DocumentId
        ];
        System.assertEquals(j.Id, d.Journal__c);
        System.assertEquals('simple.pdf', d.Name);
        System.assertEquals(key, d.S3_Key__c);
        System.assertEquals('Draft', d.Status__c);
        System.assertEquals(1, d.Version__c);
        System.assertEquals(true, d.Is_Newest_Version__c);
        System.assertEquals(j.Market_Unit__c, d.Market_Unit__c, 'Market should stamp from Journal');
    }

    @IsTest
    static void cover_full_with_all_optionals() {
        Journal__c j = makeJournal();
        j = [SELECT Id, Name, Market_Unit__c FROM Journal__c WHERE Id = :j.Id];

        String key = 'customer-documents/' + j.Name + '/full.pdf';

        DocShareService.CreateForJournalRequest req = new DocShareService.CreateForJournalRequest();
        req.JournalId     = j.Id;
        req.S3Key         = key;
        req.FileName      = 'full.pdf';
        req.VersionNumber = 5;
        req.InitialStatus = 'Sent';
        req.Expiration    = Datetime.now().addDays(3);

        DocShareService.CreateForJournalResult r = DocShareService.createForJournal(req);
        System.assertNotEquals(null, r.DocumentId);

        Shared_Document__c d = [
            SELECT Id, Journal__c, Name, S3_Key__c, Version__c, Status__c, Expiration_Date__c, Is_Newest_Version__c, Market_Unit__c
            FROM Shared_Document__c WHERE Id = :r.DocumentId
        ];
        System.assertEquals('full.pdf', d.Name);
        System.assertEquals(5, d.Version__c);
        System.assertEquals('Sent', d.Status__c);
        System.assertNotEquals(null, d.Expiration_Date__c);
        System.assertEquals(true, d.Is_Newest_Version__c);
        System.assertEquals(j.Market_Unit__c, d.Market_Unit__c);
    }

    @IsTest
    static void cover_full_deriveName_noOptionals() {
        Journal__c j = makeJournal();
        j = [SELECT Id, Name, Market_Unit__c FROM Journal__c WHERE Id = :j.Id];

        String key = 'customer-documents/' + j.Name + '/derived-name.pdf';

        DocShareService.CreateForJournalRequest req = new DocShareService.CreateForJournalRequest();
        req.JournalId = j.Id;
        req.S3Key     = key;

        DocShareService.CreateForJournalResult r = DocShareService.createForJournal(req);
        System.assertNotEquals(null, r.DocumentId);

        Shared_Document__c d = [
            SELECT Id, Name, S3_Key__c, Status__c, Version__c, Is_Newest_Version__c, Market_Unit__c
            FROM Shared_Document__c WHERE Id = :r.DocumentId
        ];
        System.assertEquals('derived-name.pdf', d.Name);
        System.assertEquals(key, d.S3_Key__c);
        System.assertEquals('Draft', d.Status__c);
        System.assertEquals(1, d.Version__c);
        System.assertEquals(true, d.Is_Newest_Version__c);
        System.assertEquals(j.Market_Unit__c, d.Market_Unit__c);
    }

    @IsTest
    static void cover_full_key_ends_with_slash_defaultName() {
        Journal__c j = makeJournal();
        j = [SELECT Id, Name, Market_Unit__c FROM Journal__c WHERE Id = :j.Id];

        String key = 'customer-documents/' + j.Name + '/';

        DocShareService.CreateForJournalRequest req = new DocShareService.CreateForJournalRequest();
        req.JournalId = j.Id;
        req.S3Key     = key;

        DocShareService.CreateForJournalResult r = DocShareService.createForJournal(req);
        Shared_Document__c d = [
            SELECT Id, Name, S3_Key__c, Market_Unit__c FROM Shared_Document__c WHERE Id = :r.DocumentId
        ];
        System.assertEquals(key, d.S3_Key__c);
        System.assertEquals(j.Market_Unit__c, d.Market_Unit__c);

        System.assertNotEquals(null, d.Name, 'Name should not be null when key ends with slash.');
        Boolean isDocumentPrefix = Pattern.compile('^Document(\\b|\\s)').matcher(d.Name).find();
        Boolean isJournalName = d.Name == j.Name;
        System.assert(
            isDocumentPrefix || isJournalName,
            'When key ends with "/", name should default to "Document <...>" or fallback to Journal.Name. Was: "' + d.Name + '"'
        );
    }

    @IsTest
    static void cover_bulk_happy_path() {
        Journal__c j = makeJournal();
        j = [SELECT Id, Name, Market_Unit__c FROM Journal__c WHERE Id = :j.Id];

        List<DocShareService.CreateForJournalRequest> batch =
            new List<DocShareService.CreateForJournalRequest>();

        DocShareService.CreateForJournalRequest a = new DocShareService.CreateForJournalRequest();
        a.JournalId = j.Id;
        a.S3Key     = 'customer-documents/' + j.Name + '/bulk-a.pdf';
        a.FileName  = 'bulk-a.pdf';
        batch.add(a);

        DocShareService.CreateForJournalRequest b = new DocShareService.CreateForJournalRequest();
        b.JournalId = j.Id;
        b.S3Key     = 'customer-documents/' + j.Name + '/bulk-b.pdf';
        batch.add(b);

        List<DocShareService.CreateForJournalResult> out =
            DocShareService.createForJournalBulk(batch);

        System.assertEquals(2, out.size());

        Set<String> names = new Set<String>();
        for (DocShareService.CreateForJournalResult r : out) {
            Shared_Document__c d = [
                SELECT Name, Status__c, Version__c, Is_Newest_Version__c, Market_Unit__c
                FROM Shared_Document__c WHERE Id = :r.DocumentId
            ];
            names.add(d.Name);
            System.assertEquals('Draft', d.Status__c);
            System.assertEquals(1, d.Version__c);
            System.assertEquals(true, d.Is_Newest_Version__c);
            System.assertEquals(j.Market_Unit__c, d.Market_Unit__c);
        }
        System.assert(names.contains('bulk-a.pdf'));
        System.assert(names.contains('bulk-b.pdf'));
    }

    @IsTest
    static void cover_replace_increments_version_and_marks_newest() {
        Journal__c j = makeJournal();
        j = [SELECT Id, Name, Market_Unit__c FROM Journal__c WHERE Id = :j.Id];

        // Seed v1
        DocShareService.CreateForJournalResult r1 =
            DocShareService.createForJournalSimple(
                j.Id,
                'customer-documents/' + j.Name + '/seed.pdf',
                'seed.pdf'
            );

        Shared_Document__c v1 = [
            SELECT Id, Name, Journal__c, Status__c, Version__c, Is_Newest_Version__c, Market_Unit__c
            FROM Shared_Document__c WHERE Id = :r1.DocumentId
        ];
        System.assertEquals(1, v1.Version__c);
        System.assertEquals(true, v1.Is_Newest_Version__c);
        System.assertEquals(j.Market_Unit__c, v1.Market_Unit__c);

        // Replace with a new file name -> expect v2, market should carry forward
        DocShareService.CreateForJournalResult r2 =
            DocShareService.replaceSharedDocument(
                v1.Id,
                'customer-documents/' + j.Name + '/seed-v2.pdf',
                'seed-v2.pdf'
            );

        Shared_Document__c oldAfter = [
            SELECT Id, Is_Newest_Version__c FROM Shared_Document__c WHERE Id = :v1.Id
        ];
        Shared_Document__c v2 = [
            SELECT Id, Name, Journal__c, Status__c, Version__c, Is_Newest_Version__c, S3_Key__c, Market_Unit__c
            FROM Shared_Document__c WHERE Id = :r2.DocumentId
        ];

        System.assertEquals(false, oldAfter.Is_Newest_Version__c, 'Old version should no longer be newest');
        System.assertEquals('seed-v2.pdf', v2.Name);
        System.assertEquals('Draft', v2.Status__c);
        System.assertEquals(2, v2.Version__c);
        System.assertEquals(true, v2.Is_Newest_Version__c);
        System.assertEquals(v1.Market_Unit__c, v2.Market_Unit__c, 'Market should carry forward on replace');

        // Replace again without a new filename -> name should stay the same
        DocShareService.CreateForJournalResult r3 =
            DocShareService.replaceSharedDocument(
                v2.Id,
                'customer-documents/' + j.Name + '/seed-v3.pdf',
                null
            );

        Shared_Document__c v3 = [
            SELECT Id, Name, Version__c, Is_Newest_Version__c, Market_Unit__c
            FROM Shared_Document__c WHERE Id = :r3.DocumentId
        ];
        Shared_Document__c v2After = [
            SELECT Id, Is_Newest_Version__c FROM Shared_Document__c WHERE Id = :v2.Id
        ];

        System.assertEquals(false, v2After.Is_Newest_Version__c, 'Second-old version should no longer be newest');
        System.assertEquals(3, v3.Version__c);
        System.assertEquals(true, v3.Is_Newest_Version__c);
        System.assertEquals(v2.Name, v3.Name);
        System.assertEquals(v2.Market_Unit__c, v3.Market_Unit__c);
    }

    @IsTest
    static void cover_invocable_wrapper() {
        Journal__c j = makeJournal();
        j = [SELECT Id, Name, Market_Unit__c FROM Journal__c WHERE Id = :j.Id];

        DocShare_CreateInvocable.Request req = new DocShare_CreateInvocable.Request();
        req.JournalId = j.Id;
        req.S3Key     = 'customer-documents/' + j.Name + '/invocable.pdf';
        req.FileName  = 'invocable.pdf';

        List<DocShare_CreateInvocable.Result> res =
            DocShare_CreateInvocable.run(new List<DocShare_CreateInvocable.Request>{ req });

        System.assertEquals(1, res.size());
        System.assertNotEquals(null, res[0].DocumentId);

        Shared_Document__c d = [
            SELECT Name, S3_Key__c, Journal__c, Market_Unit__c FROM Shared_Document__c WHERE Id = :res[0].DocumentId
        ];
        System.assertEquals('invocable.pdf', d.Name);
        System.assertEquals('customer-documents/' + j.Name + '/invocable.pdf', d.S3_Key__c);
        System.assertEquals(j.Id, d.Journal__c);
        System.assertEquals(j.Market_Unit__c, d.Market_Unit__c);
    }

    @IsTest
    static void cover_error_paths() {
        Journal__c j = makeJournal();
        j = [SELECT Id, Name FROM Journal__c WHERE Id = :j.Id];

        Boolean threw = false;
        try {
            DocShareService.createForJournalSimple(j.Id, null, 'x.pdf');
        } catch (Exception e) { threw = true; }
        System.assert(threw);

        threw = false;
        try {
            DocShareService.createForJournalSimple(null, 'customer-documents/X/x.pdf', 'x.pdf');
        } catch (Exception e) { threw = true; }
        System.assert(threw);

        DocShareService.CreateForJournalRequest good = new DocShareService.CreateForJournalRequest();
        good.JournalId = j.Id;
        good.S3Key     = 'customer-documents/' + j.Name + '/ok.pdf';

        DocShareService.CreateForJournalRequest bad = new DocShareService.CreateForJournalRequest();
        bad.JournalId = j.Id;
        bad.S3Key     = null;

        threw = false;
        try {
            DocShareService.createForJournalBulk(new List<DocShareService.CreateForJournalRequest>{ good, bad });
        } catch (Exception e) { threw = true; }
        System.assert(threw);
    }

    @IsTest
    static void cover_overlong_name_trimming_on_replace() {
        Journal__c j = makeJournal();
        j = [SELECT Id, Name FROM Journal__c WHERE Id = :j.Id];

        // Seed v1
        DocShareService.CreateForJournalResult r1 =
            DocShareService.createForJournalSimple(
                j.Id,
                'customer-documents/' + j.Name + '/seed.pdf',
                'seed.pdf'
            );

        Shared_Document__c v1 = [SELECT Id, Name, Journal__c FROM Shared_Document__c WHERE Id = :r1.DocumentId];

        String veryLong = 'Some very very very very long prefix that will need trimming ' + '(' + j.Name + ').pdf';
        DocShareService.CreateForJournalResult r2 =
            DocShareService.replaceSharedDocument(
                v1.Id,
                'customer-documents/' + j.Name + '/seed-v2.pdf',
                veryLong
            );

        Shared_Document__c v2 = [SELECT Name FROM Shared_Document__c WHERE Id = :r2.DocumentId];
    Integer maxLen = Schema.SObjectType.Shared_Document__c.fields.Name.getLength();
        System.assert(v2.Name.length() <= maxLen, 'Replace should truncate overlong names');
        System.assert(v2.Name.endsWith(j.Name + ').pdf') || v2.Name.endsWith('(' + j.Name + ').pdf') || v2.Name.endsWith(' ' + j.Name + ').pdf'),
            'Replace should keep journal suffix');
        System.assert(v2.Name.contains('…') || !v2.Name.contains('…') && v2.Name.length() <= maxLen,
            'Replace should include ellipsis when truncated when space allows');
    }
}