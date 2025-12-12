/**
 * @description The DFJ_ProcessDocFabDocument_Apex class is responsible for handling
 * document fabrication processes. It provides methods to interact with the document
 * fabricator settings and retrieve URLs for given records and object API names.
 */

public class DFJ_ProcessDocFabDocument_Apex {
  public class JournalOption {
    @AuraEnabled
    public Id journalId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String externalRecordUuid;
    @AuraEnabled
    public String url;
  }

  private static String normalizeBaseUrl(String baseUrl) {
    if (String.isBlank(baseUrl)) {
      return null;
    }
    return baseUrl.endsWith('/') ? baseUrl : (baseUrl + '/');
  }

  private static List<Journal__c> queryRelatedJournals(
    Id contextRecordId,
    String objectApiName
  ) {
    if (contextRecordId == null) {
      return new List<Journal__c>();
    }

    String whereClause;
    if (objectApiName == 'Journal__c') {
      whereClause = 'Id = :contextRecordId';
    } else if (objectApiName == 'Account') {
      whereClause = 'Account__c = :contextRecordId';
    } else if (objectApiName == 'Lead') {
      whereClause = 'Lead__c = :contextRecordId';
    } else if (objectApiName == 'Opportunity') {
      whereClause = 'Opportunity__c = :contextRecordId';
    } else {
      // Fallback if placed on an unexpected record page.
      whereClause = 'Id = :contextRecordId OR Account__c = :contextRecordId OR Lead__c = :contextRecordId OR Opportunity__c = :contextRecordId';
    }

    String soql =
      'SELECT Id, Name, External_record_uuid__c, LastModifiedDate ' +
      'FROM Journal__c ' +
      'WHERE External_record_uuid__c != null AND (' +
      whereClause +
      ') ' +
      'WITH SECURITY_ENFORCED ' +
      'ORDER BY LastModifiedDate DESC NULLS LAST ' +
      'LIMIT 200';

    return (List<Journal__c>) Database.query(soql);
  }

  /**
   * Returns all related journals (with a non-blank External_record_uuid__c) and their DocFab URLs.
   *
   * - Journal page: returns the current journal if it has an external uuid
   * - Account/Lead/Opportunity: returns all related journals
   */
  @AuraEnabled(Cacheable=true)
  public static List<JournalOption> getJournalOptions(
    String recordId,
    String objectApiName
  ) {
    try {
      if (String.isBlank(recordId) || String.isBlank(objectApiName)) {
        return new List<JournalOption>();
      }

      Doc_Fabricator_Setting__c docFabSetting = Doc_Fabricator_Setting__c.getOrgDefaults();
      String baseUrl = normalizeBaseUrl(
        docFabSetting != null ? docFabSetting.URL__c : null
      );
      if (String.isBlank(baseUrl)) {
        return new List<JournalOption>();
      }

      List<Journal__c> journals = queryRelatedJournals(
        (Id) recordId,
        objectApiName
      );

      List<JournalOption> options = new List<JournalOption>();
      for (Journal__c j : journals) {
        if (String.isBlank(j.External_record_uuid__c)) {
          continue;
        }
        JournalOption option = new JournalOption();
        option.journalId = j.Id;
        option.label = j.Name;
        option.externalRecordUuid = j.External_record_uuid__c;
        option.url =
          baseUrl +
          'public/record_templates/' +
          j.External_record_uuid__c;
        options.add(option);
      }

      return options;
    } catch (Exception e) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Get Journal Options',
        e.getMessage(),
        'Error',
        'DFJ_ProcessDocFabDocument_Apex.getJournalOptions',
        '',
        String.valueOf(e.getLineNumber())
      );
      return new List<JournalOption>();
    }
  }

  /**
   * @description The getUrl method is used to retrieve the URL for component
   * dFJ_Process_DocFab_Document.
   *
   * @param recordId The ID of the record for which the URL needs to be
   * retrieved.
   * @param objectApiName The API name of the object for which the URL needs to
   * be retrieved.
   * @return a Url for dFJ_Process_DocFab_Document component.
   */

  @AuraEnabled(Cacheable=true)
  public static String getUrl(String recordId, String objectApiName) {
    try {
      List<JournalOption> options = getJournalOptions(recordId, objectApiName);
      if (options.isEmpty()) {
        return null;
      }

      // Backwards compatible behavior: return the most recently modified journal's URL.
      return options[0].url;
    } catch (Exception e) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Get URL',
        e.getMessage(),
        'Error',
        'DFJ_ProcessDocFabDocument_Apex.getUrl',
        '',
        String.valueOf(e.getLineNumber())
      );
      return null;
    }
  }
}
