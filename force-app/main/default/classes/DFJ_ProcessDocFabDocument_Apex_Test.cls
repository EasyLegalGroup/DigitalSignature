@IsTest
private class DFJ_ProcessDocFabDocument_Apex_Test {
  @TestSetup
  static void setup() {
    // Org defaults for hierarchy custom setting
    insert new Doc_Fabricator_Setting__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      URL__c = 'https://docfab.example/'
    );

    Account a = new Account(Name = 'Test Account');
    insert a;

    Lead l = new Lead(LastName = 'Test Lead', Company = 'Test Co');
    insert l;

    Opportunity o = new Opportunity(
      Name = 'Test Opp',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(10),
      AccountId = a.Id
    );
    insert o;

    // Account-related journals (two valid)
    insert new Journal__c(
      Account__c = a.Id,
      Market_Unit__c = 'DFJ_DK',
      External_record_uuid__c = 'acc-uuid-1'
    );
    insert new Journal__c(
      Account__c = a.Id,
      Market_Unit__c = 'DFJ_DK',
      External_record_uuid__c = 'acc-uuid-2'
    );

    // Lead-related journals (one valid, one invalid)
    insert new Journal__c(
      Lead__c = l.Id,
      Market_Unit__c = 'DFJ_DK',
      External_record_uuid__c = 'lead-uuid-1'
    );
    insert new Journal__c(Lead__c = l.Id, Market_Unit__c = 'DFJ_DK');

    // Opportunity-related journals (two valid)
    insert new Journal__c(
      Opportunity__c = o.Id,
      Market_Unit__c = 'DFJ_DK',
      External_record_uuid__c = 'opp-uuid-1'
    );
    insert new Journal__c(
      Opportunity__c = o.Id,
      Market_Unit__c = 'DFJ_DK',
      External_record_uuid__c = 'opp-uuid-2'
    );
  }

  @IsTest
  static void accountReturnsMultipleOptions() {
    Account a = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
    List<DFJ_ProcessDocFabDocument_Apex.JournalOption> opts = DFJ_ProcessDocFabDocument_Apex.getJournalOptions(
      (String) a.Id,
      'Account'
    );

    System.assertEquals(
      2,
      opts.size(),
      'Account should return two valid journals'
    );
    System.assert(
      opts[0].url.contains('/public/record_templates/'),
      'URL should use record_templates path'
    );
  }

  @IsTest
  static void leadFiltersInvalidUuid() {
    Lead l = [SELECT Id FROM Lead LIMIT 1];
    List<DFJ_ProcessDocFabDocument_Apex.JournalOption> opts = DFJ_ProcessDocFabDocument_Apex.getJournalOptions(
      (String) l.Id,
      'Lead'
    );

    System.assertEquals(
      1,
      opts.size(),
      'Lead should return only journals with External_record_uuid__c'
    );
    System.assertEquals('lead-uuid-1', opts[0].externalRecordUuid);
  }

  @IsTest
  static void opportunityReturnsMultipleOptions() {
    Opportunity o = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Test Opp'
      LIMIT 1
    ];
    List<DFJ_ProcessDocFabDocument_Apex.JournalOption> opts = DFJ_ProcessDocFabDocument_Apex.getJournalOptions(
      (String) o.Id,
      'Opportunity'
    );

    System.assertEquals(
      2,
      opts.size(),
      'Opportunity should return two valid journals'
    );
  }

  @IsTest
  static void journalContextReturnsSingleOption() {
    Journal__c j = [
      SELECT Id
      FROM Journal__c
      WHERE Lead__c != NULL AND External_record_uuid__c != NULL
      LIMIT 1
    ];
    List<DFJ_ProcessDocFabDocument_Apex.JournalOption> opts = DFJ_ProcessDocFabDocument_Apex.getJournalOptions(
      (String) j.Id,
      'Journal__c'
    );

    System.assertEquals(
      1,
      opts.size(),
      'Journal page should return the journal itself'
    );
    System.assertEquals(j.Id, opts[0].journalId);
  }

  @IsTest
  static void getUrlReturnsMostRecentUrlOrNull() {
    Account a = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
    String url = DFJ_ProcessDocFabDocument_Apex.getUrl(
      (String) a.Id,
      'Account'
    );
    System.assertNotEquals(null, url);
    System.assert(url.startsWith('https://docfab.example/'));
  }
}
