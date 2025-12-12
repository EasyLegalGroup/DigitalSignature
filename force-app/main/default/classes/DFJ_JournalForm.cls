/**
 * Created by shubh on 23-07-2019.
 */

public with sharing class DFJ_JournalForm {
  // Backwards-compatible overload to satisfy older callers/tests expecting the legacy signature.
  @AuraEnabled
  public static journalWholeData getJournalData_Apex(
    String JournalId,
    String objectName,
    String contextRecordId,
    Boolean journlaFormClicked
  ) {
    return getJournalData_Apex(
      JournalId,
      objectName,
      contextRecordId,
      journlaFormClicked,
      null,
      null,
      null
    );
  }

  @AuraEnabled
  public static journalWholeData getJournalData_Apex(
    String JournalId,
    String objectName,
    String contextRecordId,
    Boolean journlaFormClicked,
    Decimal componentRecordModelId,
    String componentFormUuid,
    String componentFormTypeName
  ) {
    if (objectName == null || objectName.trim() == '') {
      objectName = 'Journal__c';
    }
    if (JournalId == null || JournalId.trim() == '') {
      return null;
    }

    if (
      componentRecordModelId != null && !String.isBlank(componentFormTypeName)
    ) {
      journalWholeData conflictResponse = new journalWholeData();
      conflictResponse.docFabUrl = 'Record Model Id and Form Type cannot both be specified in the Page layout';
      return conflictResponse;
    }

    List<Journal__c> journalsList = new List<Journal__c>();
    List<Person__c> personsList = new List<Person__c>();
    List<Assests__c> assetsList = new List<Assests__c>();
    List<Journal_Configuration__c> journalConfigurationList = new List<Journal_Configuration__c>();
    journalWholeData journalReturnInstance = new journalWholeData();
    //DFJ-160 Changes Added Retskreds__c in the Query field
    journalsList = [
      SELECT
        Has_Children__c,
        Civil_Status__c,
        Children_type__c,
        All_children_over_18__c,
        Account__c,
        Account__r.LastName,
        Account__r.MiddleName,
        Account__r.FirstName,
        CreatedById,
        CreatedDate,
        CurrencyIsoCode,
        edit_or_recall__c,
        escrow_age__c,
        escrow_partial__c,
        Id,
        IsDeleted,
        mariage_date__c,
        mariage_type__c,
        Name,
        separate_property_type__c,
        Services__c,
        Arv_fra_f_rste_afd_de__c,
        First_Include_future_children__c,
        Second_Include_Future_Children__c,
        CVR__c,
        Company_Name__c,
        inheritance_from_longest_lived__c,
        inheritance_from_first__c,
        Internal_notes__c,
        Testament_Type__c,
        Date_of_Cohabiting__c,
        Partial_Expense_Description__c,
        Is_2_mutual_procurations__c,
        Use_subsidiary_procurators__c,
        Personal_Conditions__c,
        Economical_Conditions__c,
        Company__c,
        Presents_for_charity__c,
        Presents_for_procurator__c,
        Tax_free_presents__c,
        Procurators_have_access_to_annual_fee__c,
        Amount__c,
        Use_year_instead_of_date__c,
        Year_of_marriage__c,
        Year_of_cohabiting__c,
        grave_maintenance__c,
        former_wills__c,
        inheritance_additional_notes__c,
        Testament_fall_on_divorce__c,
        Common_Property__c,
        Undivided_estate__c,
        separate_property_conditions__c,
        Use_same_address_as_spouse_1__c,
        last_surviving_conditions__c,
        Guardian_one_time_fee__c,
        Surviving_inheritance_as_prenuptial__c,
        Testament_valid_on_surviving_remarriage__c,
        Testament_valid_on_marriage__c,
        Present_usually__c,
        Presents_occasionally__c,
        Total_Count__c,
        LastModifiedDate,
        Document_generated_on__c,
        journal_Deadline__c,
        Journal_States__c,
        Arv_fra_l_ngstlevende__c,
        Template_outdated__c,
        Guardian_monthly_amount__c,
        Internal_Notes_InheritDistribution__c,
        Internal_Notes_Escrow__c,
        Internal_Notes_Children__c,
        Internal_Notes_ChildrenTestament__c,
        Internal_Notes_FutureMandate__c,
        Internal_Notes_Marriage__c,
        Internal_Notes_IndledendeSprgsml__c,
        Internal_Notes_Person1__c,
        Internal_Notes_Person2__c,
        Internal_Notes_Cohabiting__c,
        Internal_Notes_Prenup__c,
        First_Include_future_children_P__c,
        Has_Children_P__c,
        Former_Wills_P__c,
        Use_same_address_as_spouse_1_P__c,
        All_children_over_18_P__c,
        Use_year_instead_of_date_P__c,
        Testament_fall_on_divorce_P__c,
        Testament_valid_on_surviving_remarriag_P__c,
        Surviving_inheritance_as_prenuptial_P__c,
        Undivided_estate_P__c,
        Edit_or_recall_P__c,
        Testament_valid_on_marriage_P__c,
        Common_Property_P__c,
        Second_Include_Future_Children_P__c,
        Grave_Maintenance_P__c,
        Is_2_mutual_procurations_P__c,
        Use_subsidiary_procurators_P__c,
        Personal_Conditions_P__c,
        Economical_Conditions_P__c,
        Company_P__c,
        Presents_for_charity_P__c,
        Presents_occasionally_P__c,
        Present_usually_P__c,
        Tax_free_presents_P__c,
        Procurators_have_access_to_annual_fee_P__c,
        Include_future_children_P__c,
        Lead__r.LastName,
        Lead__r.MiddleName,
        Lead__r.FirstName,
        Lead__r.Address,
        Lead__r.City,
        Lead__r.PostalCode,
        Lead__r.Email,
        Lead__r.State,
        Lead__r.Street,
        Lead__r.Status,
        Lead__r.Market_Unit__c,
        Lead__r.Phone,
        Lead__r.Country,
        Account__r.Id,
        Lead__r.IsConverted,
        Lead__c,
        Seperate_Property__c,
        Unwanted_Guardian__c,
        Special_Conditions__c,
        Show_Asset_Thing__c,
        Show_Asset_Money__c,
        Add_Escrow__c,
        persisting_inheritance__c,
        Child_Wiils__c,
        Allow_Guardian_Amount__c,
        Procurator_order__c,
        Internal_Notes_Sumlegat__c,
        Internal_Notes_Genstandslegat__c,
        Market_Unit__c,
        Responsible_Lawyer__c,
        External_record_uuid__c,
        Retskreds__c,
        SMS_Flow__c,
        Is_Using_Docfab__c,
        DocFab_Record_Model_ID__c,
        Type__c
      FROM Journal__c
      WHERE Id = :JournalId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];

    if (!journalsList.isEmpty()) {
      // Two-tier DocFab selection:
      // Form UUID comes from the selection flow; Record Model is inferred from the Form metadata.
      // Access is controlled by the Form's Custom Permission.
      System.debug(
        'journlaFormClicked >>>' +
          journlaFormClicked +
          'Is docfab URL' +
          journalsList[0].Is_Using_Docfab__c
      );
      if (journlaFormClicked) {
        System.debug('Inside If-----');
        Boolean shouldRollback = false;

        // Validate that form UUID is provided (required)
        if (String.isBlank(componentFormUuid)) {
          journalReturnInstance.docFabUrl = 'Form UUID is required. Please configure the Journal Form component on the page layout.';
          return journalReturnInstance;
        }

        // Use selectConfiguration for permission checking and field config lookup
        DF_DocFabricator_Utility.DocFabSelectionResult selection = DF_DocFabricator_Utility.selectConfiguration(
          null,
          null,
          componentRecordModelId,
          componentFormUuid,
          UserInfo.getUserId()
        );
        if (selection == null) {
          journalReturnInstance.docFabUrl = 'No DocFab configuration found.';
          return journalReturnInstance;
        }
        if (!String.isBlank(selection.permissionError)) {
          journalReturnInstance.docFabUrl = selection.permissionError;
          return journalReturnInstance;
        }
        if (!String.isBlank(selection.errorMessage)) {
          journalReturnInstance.docFabUrl = selection.errorMessage;
          return journalReturnInstance;
        }
        if (selection.recordModelId == null) {
          journalReturnInstance.docFabUrl = 'Record Model ID not configured.';
          return journalReturnInstance;
        }

        // Get market unit for the journal (still needed for the journal record itself)
        String resolvedMarketUnit = resolveMarketUnit(
          journalsList[0],
          objectName,
          contextRecordId
        );

        String docFabUrl = processDocFabSelection(
          journalsList,
          selection,
          resolvedMarketUnit,
          objectName,
          contextRecordId
        );
        System.debug('docFabUrl If-----' + docFabUrl);
        if (!String.isBlank(docFabUrl)) {
          journalReturnInstance.docFabUrl = docFabUrl;
          System.debug(
            'journalReturnInstance.docFabUrl---' +
            journalReturnInstance.docFabUrl
          );
          if (objectName == 'Lead') {
            journalReturnInstance.docFabOptions = buildDocFabOptionsForLead(
              contextRecordId,
              selection.recordModelId,
              selection.formUuid
            );
            if (
              journalReturnInstance.docFabOptions != null &&
              journalReturnInstance.docFabOptions.size() > 1
            ) {
              journalReturnInstance.requiresSelection = true;
              // If multiple options, do not force docFabUrl to auto-open
              journalReturnInstance.docFabUrl = null;
            } else if (
              journalReturnInstance.docFabOptions != null &&
              journalReturnInstance.docFabOptions.size() == 1
            ) {
              journalReturnInstance.docFabUrl = journalReturnInstance.docFabOptions[0]
                .url;
            }
          }
        } else {
          shouldRollback = true;
          DFJ_ErrorLogController.addErrorLogs(
            JournalId,
            'Checking docFabUrl is not blank',
            '',
            'Warning',
            'In getJournalData_Apex docFabUrl is null or empty',
            '',
            ''
          );
        }

        if (objectName == 'Lead') {
          Boolean failed = shouldRollback;
          if (!failed && !String.isBlank(docFabUrl)) {
            failed =
              docFabUrl.contains('Can not create record in DocFabricator') ||
              docFabUrl.startsWith('Error Code') ||
              docFabUrl.startsWith('Current user with');
          }
          if (failed && !String.isBlank(JournalId)) {
            // Clean up the draft journal/persons if DocFab failed.
            cleanupLeadDraftJournal(JournalId);
          }
        }
      }
      // End
      // End
      personsList = [
        SELECT
          Address__c,
          City__c,
          CPR__c,
          CurrencyIsoCode,
          Email__c,
          First_Name__c,
          Guardian_one_time_fee__c,
          Id,
          First_Is_Blacksheep__c,
          Second_Is_Blacksheep__c,
          IsDeleted,
          Journal__c,
          Last_Name__c,
          Parents__c,
          Phone__c,
          Type__c,
          Zip_Code__c,
          Full_Name__c,
          Guardian_Justification__c,
          First_Percentage__c,
          Second_Percentage__c,
          Guardian_type__c,
          Custody__c,
          First_Percentage_Of_Child__c,
          Is_Primary__c,
          Procurator_Justification__c,
          Is_Primary_P__c,
          Priority__c
        FROM Person__c
        WHERE Journal__c = :JournalId
        WITH SECURITY_ENFORCED
        LIMIT 10000
      ];

      assetsList = [
        SELECT
          CPR_Number__c,
          CreatedById,
          CreatedDate,
          CurrencyIsoCode,
          First_Name__c,
          Id,
          IsDeleted,
          Journal_Id__c,
          Last_Name__c,
          Name,
          Person_Id__c,
          Type__c,
          Value__c,
          Asset_Info__c,
          Is_Personal__c,
          Is_Personal_P__c
        FROM Assests__c
        WHERE Journal_Id__c = :JournalId
        WITH SECURITY_ENFORCED
        LIMIT 10000
      ];
      List<Journal_Configuration__c> configurationList = new List<Journal_Configuration__c>();
      Set<Id> setOfProductId = new Set<Id>();

      if (objectName == 'Journal__c') {
        List<Journal__c> journalList = new List<Journal__c>();
        journalList = [
          SELECT Id, Name, Order__c
          FROM Journal__c
          WHERE Id = :JournalId
          WITH SECURITY_ENFORCED
          LIMIT 1
        ];

        Set<Id> setOfOrderId = new Set<Id>();
        for (Journal__c jc : journalList) {
          setOfOrderId.add(jc.Order__c);
        }

        List<Order> orderList = new List<Order>();
        orderList = [
          SELECT Id, Name
          FROM Order
          WHERE Id IN :setOfOrderId
          WITH SECURITY_ENFORCED
          LIMIT 10000
        ];

        Set<Id> orderIdSet = new Set<Id>();
        for (Order od : orderList) {
          orderIdSet.add(od.Id);
        }

        List<OrderItem> orderItemList = new List<OrderItem>();
        orderItemList = [
          SELECT Id, OrderId, Product2Id
          FROM OrderItem
          WHERE OrderId IN :orderIdSet
          WITH SECURITY_ENFORCED
          LIMIT 10000
        ];

        for (OrderItem ol : orderItemList) {
          setOfProductId.add(ol.Product2Id);
        }
      } else if (objectName == 'Lead') {
        List<LeadProducts__c> leadProductsList = new List<LeadProducts__c>();
        leadProductsList = [
          SELECT Id, Name, Product_Id__c
          FROM LeadProducts__c
          WHERE Lead__c = :contextRecordId
          WITH SECURITY_ENFORCED
          LIMIT 10000
        ];

        for (LeadProducts__c lp : leadProductsList) {
          setOfProductId.add(lp.Product_Id__c);
        }
      }
      if (setOfProductId != null && !setOfProductId.isEmpty()) {
        configurationList = [
          SELECT
            Id,
            Name,
            Journal_Field__r.Unique_Name__c,
            Journal_Field__r.Name,
            Journal_Section__r.Name,
            Journal_Section__r.Unique_Name__c,
            Product__r.Name,
            Mandatory__c,
            Visible__c
          FROM Journal_Configuration__c
          WHERE Product__c IN :setOfProductId
          WITH SECURITY_ENFORCED
          LIMIT 10000
        ];
      }

      Map<String, Boolean> journalFieldVsRequiredFieldMap = new Map<String, Boolean>();

      for (Journal_Configuration__c journal_configuration : configurationList) {
        // Check if the unique name should not be null (we don't want to add the null key value in the map)
        if (journal_configuration.Journal_Section__r.Unique_Name__c != null) {
          // Check if the unique section is present in the map, if not then we will add in the map
          if (
            !journalFieldVsRequiredFieldMap.containsKey(
              journal_configuration.Journal_Section__r.Unique_Name__c
            )
          ) {
            journalFieldVsRequiredFieldMap.put(
              journal_configuration.Journal_Section__r.Unique_Name__c,
              false
            );
          }
          // Check if the unique field is present in the map, if not then we will add in the map
          if (
            !journalFieldVsRequiredFieldMap.containsKey(
              journal_configuration.Journal_Field__r.Unique_Name__c
            )
          ) {
            journalFieldVsRequiredFieldMap.put(
              journal_configuration.Journal_Field__r.Unique_Name__c,
              false
            );
          }
          // check if the field is mandatory for every time, if we got it any time then it should not be false
          if (journal_configuration.Mandatory__c == true) {
            journalFieldVsRequiredFieldMap.put(
              journal_configuration.Journal_Field__r.Unique_Name__c,
              true
            );
          }
        }
      }

      List<configWrapper> configWrapperList = new List<configWrapper>();

      for (String jConfig : journalFieldVsRequiredFieldMap.keySet()) {
        configWrapper configWrapperInstance = new configWrapper();
        configWrapperInstance.uniqueName = jConfig;
        configWrapperInstance.isMandatory = journalFieldVsRequiredFieldMap.get(
          jConfig
        );
        configWrapperList.add(configWrapperInstance);
      }
      journalReturnInstance.journalData = journalsList[0];
      journalReturnInstance.personData = personsList;
      journalReturnInstance.assestData = assetsList;
      journalReturnInstance.configurationValues = configWrapperList;
      journalReturnInstance.userList = new List<User>(
        [SELECT Id, Name FROM User WHERE IsActive = TRUE]
      );
      //DFJ-160 Added Retskreds__c in fetch picklist field value.
      journalReturnInstance.picklistWrappersValues = fetchPicklistValue_Apex(
        'Journal__c',
        'mariage_type__c,CurrencyIsoCode,separate_property_type__c,Arv_fra_f_rste_afd_de__c,Arv_fra_l_ngstlevende__c,inheritance_from_first__c,inheritance_from_longest_lived__c,Testament_Type__c,last_surviving_conditions__c,Journal_States__c,Civil_Status__c,Retskreds__c'
      );
      journalReturnInstance.picklistWrappersEventValues = fetchPicklistValue_Apex(
        'Event',
        'Type'
      );
      journalReturnInstance.picklistWrappersPersonValues = fetchPicklistValue_Apex(
        'Person__c',
        'Guardian_type__c,Custody__c'
      );
      // Changes for ticket DIN-284 : Create type picklist field on journal and show in component
      // Start
      journalReturnInstance.picklistWrappersJournalTypeValues = fetchPicklistValue_Apex(
        'Journal__c',
        'Type__c'
      );
      // End
      // DFJ-160 Changes
      //journalReturnInstance.picklistWrappersJournalTypeValues = fetchPicklistValue_Apex('Journal__c', 'Retskreds__c');
      //End
      System.debug('journalReturnInstance-->' + journalReturnInstance);
      return journalReturnInstance;
    }

    return null;
  }

  public class journalWholeData {
    @AuraEnabled
    public Journal__c journalData;
    @AuraEnabled
    public List<Person__c> personData;
    @AuraEnabled
    public List<Assests__c> assestData;
    @AuraEnabled
    public List<listOfPicklistWrapper> picklistWrappersValues;
    @AuraEnabled
    public List<listOfPicklistWrapper> picklistWrappersEventValues;
    @AuraEnabled
    public List<listOfPicklistWrapper> picklistWrappersPersonValues;
    // Changes for ticket DIN-284 : Create type picklist field on journal and show in component
    // Start
    @AuraEnabled
    public List<listOfPicklistWrapper> picklistWrappersJournalTypeValues;
    // End
    // DFJ-160 Changes
    //@AuraEnabled public List<listOfPicklistWrapper> picklistWrappersJournalRetskredsValues;
    //End
    @AuraEnabled
    public List<configWrapper> configurationValues;
    @AuraEnabled
    public List<User> userList;
    // Changes for ticket - DIN-169 : Open record content in form.
    // Start
    // Description : Adding property to store record_uuid,form_uuid,marketunit,errorMessage so DocFab can be opened using record_uuid,form_uuid.
    // @AuraEnabled public String recordUuid;
    // @AuraEnabled public String formUuid;
    @AuraEnabled
    public String docFabUrl;
    @AuraEnabled
    public String errorMessage;
    @AuraEnabled
    public List<DocFabOption> docFabOptions;
    @AuraEnabled
    public Boolean requiresSelection;
    // End
  }

  public class DocFabOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String url;
    @AuraEnabled
    public Decimal recordModelId;
  }

  public class configWrapper {
    @AuraEnabled
    public String uniqueName;
    @AuraEnabled
    public Boolean isMandatory;
  }

  @AuraEnabled
  public static journalWholeData insertJournaldata_Apex(
    String JournalData,
    String personsData,
    String assetData,
    String personListToDelete,
    String assetToDelete,
    String guardianToDelete,
    String GuardianData,
    String HeirToDelete,
    String ProcuratorsToDelete
  ) {
    if (JournalData == null || personsData == null || assetData == null) {
      return null;
    }

    if (personListToDelete != null) {
      Set<String> personsToDeleteList = new Set<String>();
      personsToDeleteList = (Set<String>) JSON.deserialize(
        personListToDelete,
        Set<String>.class
      );

      List<Person__c> personList = new List<Person__c>();
      personList = [
        SELECT Id, Name
        FROM Person__c
        WHERE Id IN :personsToDeleteList
        WITH SECURITY_ENFORCED
      ];
      if (!personList.isEmpty()) {
        delete personList;
      }
    }

    if (HeirToDelete != null) {
      Set<String> heirToDeleteList = new Set<String>();
      heirToDeleteList = (Set<String>) JSON.deserialize(
        HeirToDelete,
        Set<String>.class
      );

      List<Person__c> personList = new List<Person__c>();
      personList = [
        SELECT Id, Name
        FROM Person__c
        WHERE Id IN :heirToDeleteList
        WITH SECURITY_ENFORCED
      ];
      if (!personList.isEmpty()) {
        delete personList;
      }
    }

    if (ProcuratorsToDelete != null) {
      Set<String> heirToDeleteList = new Set<String>();
      heirToDeleteList = (Set<String>) JSON.deserialize(
        ProcuratorsToDelete,
        Set<String>.class
      );

      List<Person__c> personList = new List<Person__c>();
      personList = [
        SELECT Id, Name
        FROM Person__c
        WHERE Id IN :heirToDeleteList
        WITH SECURITY_ENFORCED
      ];
      if (!personList.isEmpty()) {
        delete personList;
      }
    }

    if (assetToDelete != null) {
      Set<String> assetsToDeleteList = new Set<String>();
      assetsToDeleteList = (Set<String>) JSON.deserialize(
        assetToDelete,
        Set<String>.class
      );

      List<Assests__c> assetList = new List<Assests__c>();
      assetList = [
        SELECT Id, Name
        FROM Assests__c
        WHERE Id IN :assetsToDeleteList
        WITH SECURITY_ENFORCED
      ];
      if (!assetList.isEmpty()) {
        delete assetList;
      }
    }

    /*Person__c personInstance = new Person__c();
		personInstance = (Person__c) JSON.deserialize(GuardianData,Person__c.class);
		if(personInstance != null){
			upsert personInstance;
		}*/
    if (guardianToDelete != null) {
      Set<String> guardiansToDeleteList = new Set<String>();
      guardiansToDeleteList = (Set<String>) JSON.deserialize(
        guardianToDelete,
        Set<String>.class
      );

      List<Person__c> personDeleteList = new List<Person__c>();
      personDeleteList = [
        SELECT Id, Name
        FROM Person__c
        WHERE Id IN :guardiansToDeleteList
        WITH SECURITY_ENFORCED
      ];
      if (!personDeleteList.isEmpty()) {
        delete personDeleteList;
      }
    }

    Journal__c journalInstance = new Journal__c();
    journalInstance = (Journal__c) JSON.deserialize(
      JournalData,
      Journal__c.class
    );
    if (journalInstance != null) {
      upsert journalInstance;
    }

    if (GuardianData != null) {
      List<Person__c> guardianList = new List<Person__c>();
      guardianList = (List<Person__c>) JSON.deserialize(
        GuardianData,
        List<Person__c>.class
      );
      for (Person__c personsLoop : guardianList) {
        personsLoop.Journal__c = journalInstance.Id;
        personsLoop.Market_Unit__c = journalInstance.Market_Unit__c;
        /*personsLoop.Type__c = 'Guardian 1';*/
      }
      if (guardianList != null) {
        upsert guardianList;
      }
    }

    /*if(unwantedGuradianData != null){
			List<Person__c> unwantedGuardianList = new List<Person__c>();
			unwantedGuardianList = (List<Person__c>) JSON.deserialize(unwantedGuradianData,List<Person__c>.class);
			for(Person__c personsLoop : unwantedGuardianList){
				personsLoop.Journal__c = journalInstance.Id;
			}
			if(unwantedGuardianList != null){
				if(!unwantedGuardianList.isEmpty()){
					upsert unwantedGuardianList;
				}
			}
		}*/

    List<Person__c> peopleList = new List<Person__c>();
    peopleList = (List<Person__c>) JSON.deserialize(
      personsData,
      List<Person__c>.class
    );
    for (Person__c personsLoop : peopleList) {
      personsLoop.Journal__c = journalInstance.Id;
      personsLoop.Market_Unit__c = journalInstance.Market_Unit__c;
    }
    if (peopleList != null) {
      if (!peopleList.isEmpty()) {
        upsert peopleList;
      }
    }

    List<Assests__c> assetList = new List<Assests__c>();
    assetList = (List<Assests__c>) JSON.deserialize(
      assetData,
      List<Assests__c>.class
    );
    for (Assests__c assests : assetList) {
      assests.Journal_Id__c = journalInstance.Id;
      assests.Market_Unit__c = journalInstance.Market_Unit__c;
    }
    if (assetList != null) {
      upsert assetList;
    }

    journalWholeData journalReturnInstance = new journalWholeData();
    journalReturnInstance.journalData = journalInstance;
    journalReturnInstance.personData = peopleList;
    journalReturnInstance.assestData = assetList;
    return journalReturnInstance;
  }

  @AuraEnabled
  public static List<listOfPicklistWrapper> fetchPicklistValue_Apex(
    String objectName,
    String fieldName
  ) {
    if (
      objectName != null &&
      objectName.trim() != '' &&
      fieldName != null &&
      fieldName.trim() != ''
    ) {
      List<listOfPicklistWrapper> returnPicklistWrapperList = new List<listOfPicklistWrapper>();

      List<String> fieldsList = new List<String>();
      fieldsList = fieldName.split(',');

      for (String fieldNameLoop : fieldsList) {
        List<picklistWrapper> listPickvals = new List<picklistWrapper>();

        Schema.SObjectType targetType = Schema.getGlobalDescribe()
          .get(objectName); //From the Object Api name retrieving the SObject
        SObject Object_name = targetType.newSObject();
        Schema.SObjectType sobject_type = Object_name.getSObjectType(); //grab the sobject that was passed

        Schema.DescribeSObjectResult sobject_describe = sobject_type.getDescribe(); //describe the sobject
        Map<String, Schema.SObjectField> field_map = sobject_describe.fields.getMap(); //get a map of fields for the passed sobject

        List<Schema.PicklistEntry> pick_list_values = field_map.get(
            fieldNameLoop
          )
          .getDescribe()
          .getPickListValues(); //grab the list of picklist values for the passed field on the sobject
        for (Schema.PicklistEntry a : pick_list_values) {
          //for all values in the picklist list

          picklistWrapper picklistWrapperInstance = new picklistWrapper();
          picklistWrapperInstance.Label = a.getLabel();
          picklistWrapperInstance.value = a.getValue();
          // System.debug(LoggingLevel.ERROR, picklistWrapperInstance.Label);
          listPickvals.add(picklistWrapperInstance); //add the value  to our final list
        }

        listOfPicklistWrapper listOfPicklistWrapperInstance = new listOfPicklistWrapper();
        listOfPicklistWrapperInstance.fieldName = fieldNameLoop;
        listOfPicklistWrapperInstance.multiplepicklist = listPickvals;
        returnPicklistWrapperList.add(listOfPicklistWrapperInstance);
      }
      return returnPicklistWrapperList;
    }
    return null;
  }

  public class listOfPicklistWrapper {
    @AuraEnabled
    public String fieldName { get; set; }
    @AuraEnabled
    public List<picklistWrapper> multiplepicklist { get; set; }
  }

  public class picklistWrapper {
    @AuraEnabled
    public String Label { get; set; }
    @AuraEnabled
    public String value { get; set; }
    @AuraEnabled
    public String textValue { get; set; }
  }

  @AuraEnabled
  public static List<Journal__c> journalAssociatedWithLead(String recordId) {
    if (recordId.trim() != '' && recordId != null) {
      List<Journal__c> listOfJournals = new List<Journal__c>();
      listOfJournals = [
        SELECT Id, Name, Lead__c
        FROM Journal__c
        WHERE Lead__c = :recordId
        WITH SECURITY_ENFORCED
        LIMIT 10000
      ];
      List<Lead> listOfLead = new List<Lead>();
      listOfLead = [
        SELECT
          Name,
          Address,
          Phone,
          Street,
          PostalCode,
          City,
          State,
          Country,
          Email,
          FirstName,
          LastName,
          Children_over_18__c,
          Has_children__c,
          Civil_status__c,
          Children_type__c,
          Market_Unit__c
        FROM Lead
        WHERE Id = :recordId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];

      //Checking for the value of the field Civil Status
      if (listOfLead[0].Civil_status__c == 'Gift') {
        listOfLead[0].Civil_status__c = 'Married';
      } else if (listOfLead[0].Civil_status__c == 'Enlig') {
        listOfLead[0].Civil_status__c = 'Single';
      } else if (listOfLead[0].Civil_status__c == 'Samlevende') {
        listOfLead[0].Civil_status__c = 'Cohabiting';
      }

      // Checking for the value of the field Type of Children
      if (listOfLead[0].Children_type__c == 'Fælles børn') {
        listOfLead[0].Children_type__c = 'Common';
      } else if (listOfLead[0].Children_type__c == 'Sammenbragte børn') {
        listOfLead[0].Children_type__c = '	Blended';
      } else if (listOfLead[0].Children_type__c == 'Begge dele') {
        listOfLead[0].Children_type__c = '';
      }

      if (listOfJournals.isEmpty()) {
        Journal__c journalInstance = new Journal__c();
        journalInstance.Lead__c = recordId;
        journalInstance.Civil_Status__c = listOfLead[0].Civil_status__c;
        journalInstance.Has_Children__c = listOfLead[0].Has_children__c;
        journalInstance.All_children_over_18__c = listOfLead[0]
          .Children_over_18__c;
        journalInstance.Children_type__c = listOfLead[0].Children_type__c;
        journalInstance.Market_Unit__c = listOfLead[0].Market_Unit__c;
        insert journalInstance;

        String addressString = '';
        addressString += listOfLead[0].Street == null
          ? ''
          : listOfLead[0].Street;
        addressString += listOfLead[0].PostalCode == null
          ? ''
          : ',' + ' ' + listOfLead[0].PostalCode;
        addressString += listOfLead[0].City == null
          ? ''
          : ',' + ' ' + listOfLead[0].City;
        addressString += listOfLead[0].State == null
          ? ''
          : ',' + ' ' + listOfLead[0].State;
        addressString += listOfLead[0].Country == null
          ? ''
          : ',' + ' ' + listOfLead[0].Country;

        Person__c personInstance = new Person__c();
        personInstance.First_Name__c = listOfLead[0].FirstName;
        personInstance.Last_Name__c = listOfLead[0].LastName;
        personInstance.Address__c = addressString;
        personInstance.Zip_Code__c = String.valueOf(listOfLead[0].PostalCode);
        personInstance.City__c = String.valueOf(listOfLead[0].City);
        personInstance.Phone__c = listOfLead[0].Phone;
        personInstance.Email__c = listOfLead[0].Email;
        personInstance.Type__c = 'Spouse 1';
        personInstance.Journal__c = journalInstance.Id;
        insert personInstance;
        listOfJournals.add(journalInstance);
      }
      return listOfJournals;
    }
    return null;
  }

  @AuraEnabled
  public static List<Journal__c> journalAssociatedWithOpportunity(
    String opportunityId,
    String recordModelId
  ) {
    if (String.isBlank(opportunityId)) {
      return null;
    }

    String rm = String.isBlank(recordModelId) ? null : recordModelId.trim();

    List<Journal__c> existing = new List<Journal__c>();
    if (rm != null) {
      existing = [
        SELECT Id, Name, Opportunity__c, Account__c, DocFab_Record_Model_ID__c
        FROM Journal__c
        WHERE
          Opportunity__c = :opportunityId
          AND DocFab_Record_Model_ID__c = :rm
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
    } else {
      existing = [
        SELECT Id, Name, Opportunity__c, Account__c, DocFab_Record_Model_ID__c
        FROM Journal__c
        WHERE Opportunity__c = :opportunityId
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
    }

    if (!existing.isEmpty()) {
      if (existing[0].Account__c == null) {
        List<Opportunity> oppsForExisting = [
          SELECT Id, AccountId
          FROM Opportunity
          WHERE Id = :opportunityId
          WITH SECURITY_ENFORCED
          LIMIT 1
        ];
        if (
          !oppsForExisting.isEmpty() && oppsForExisting[0].AccountId != null
        ) {
          existing[0].Account__c = oppsForExisting[0].AccountId;
          update existing[0];
        }
      }
      return existing;
    }

    List<Opportunity> opps = [
      SELECT Id, AccountId, Market_Unit__c
      FROM Opportunity
      WHERE Id = :opportunityId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (opps.isEmpty()) {
      return null;
    }

    Journal__c j = new Journal__c();
    j.Opportunity__c = opportunityId;
    j.Account__c = opps[0].AccountId;
    j.Market_Unit__c = opps[0].Market_Unit__c;
    j.DocFab_Record_Model_ID__c = rm;
    insert j;

    return new List<Journal__c>{ j };
  }

  @AuraEnabled //Changes DFJ-106 remove the type param from method
  //Changes DFJ-160 Added Retskreds__c in the journal List and added retskreds in the class param
  public static String updateJournalFields_Apex(
    String journalState,
    Date deadline,
    String journalId,
    String responsibleLawyer,
    String retskreds
  ) {
    if (journalId != null && journalId.trim() != '') {
      if (journalId != null && journalId.trim() != '') {
        List<Journal__c> journalList = new List<Journal__c>();
        //DFJ-160 Added Retskreds__c in Query param
        journalList = [
          SELECT Id, Name, Retskreds__c, Journal_States__c, journal_Deadline__c
          FROM Journal__c
          WHERE Id = :journalId
          WITH SECURITY_ENFORCED
          LIMIT 1
        ];
        if (!journalList.isEmpty()) {
          journalList[0].Journal_States__c = journalState;
          journalList[0].journal_Deadline__c = deadline;
          journalList[0].Responsible_Lawyer__c = responsibleLawyer;
          //Changes DFJ-160
          journalList[0].Retskreds__c = retskreds;
          // Changes for ticket DIN-284 : Create type picklist field on journal and show in component.
          // Start
          // Changes starts DFJ-106 to remove the type form component
          //	journalList[0].Type__c = type;
          // End
        }
        update journalList;
      }
    }
    return 'updated';
  }

  @AuraEnabled
  public static List<Journal__c> getJournalStatusAndDeadline_Apex(
    String leadId
  ) {
    if (leadId != null && leadId.trim() != '') {
      List<Journal__c> journalList = new List<Journal__c>();
      journalList = [
        SELECT
          Id,
          Name,
          Journal_States__c,
          journal_Deadline__c,
          LastModifiedDate,
          CreatedDate,
          External_record_uuid__c,
          Type__c
        FROM Journal__c
        WHERE Lead__c = :leadId
        WITH SECURITY_ENFORCED
        LIMIT 10000
      ];
      if (journalList != null) {
        if (!journalList.isEmpty()) {
          return journalList;
        }
      }
    }
    return null;
  }

  @AuraEnabled
  public static Datetime insertEventData_Apex(
    String EventData,
    String journalData
  ) {
    if (EventData == null || EventData.trim() == '') {
      return null;
    }

    Event eventInstance = new Event();
    eventInstance = (Event) JSON.deserialize(EventData, Event.class);
    // Changes for DIN-180 : Add checkbox to schedule meeting with attorney
    // Start
    Journal__c journalInstance = new Journal__c();
    if (journalData != null && journalData.trim() != '') {
      journalInstance = (Journal__c) JSON.deserialize(
        journalData,
        Journal__c.class
      );
    }
    // End
    List<Journal__c> journalList = new List<Journal__c>();
    journalList = [
      SELECT Id, journal_Deadline__c, SMS_Flow__c
      FROM Journal__c
      WHERE Id = :eventInstance.WhatId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];

    if (!journalList.isEmpty()) {
      journalList[0].journal_Deadline__c = eventInstance.EndDateTime;
      // Changes for DIN-180 : Add checkbox to schedule meeting with attorney
      // Start
      if (journalInstance != null && journalInstance.SMS_Flow__c != null) {
        journalList[0].SMS_Flow__c = journalInstance.SMS_Flow__c;
      }
      // End
      upsert journalList;
    }
    insert eventInstance;
    List<Journal__c> journal = new List<Journal__c>();
    journal = [
      SELECT journal_Deadline__c
      FROM Journal__c
      WHERE Id = :journalList[0].Id
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];

    return journal[0].journal_Deadline__c;
  }

  @AuraEnabled
  public static String addErrorLogsInSalesforce_Apex(String logData) {
    if (logData == null || logData.trim() == '') {
      return null;
    }

    Log__c logInstance = new Log__c();
    logInstance = (Log__c) JSON.deserialize(logData, Log__c.class);
    insert logInstance;
    List<Log__c> listOfLogs = [
      SELECT Id, Message__c
      FROM Log__c
      WHERE Id = :logInstance.Id
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    return listOfLogs[0].Message__c;
  }

  @AuraEnabled
  public static Boolean addSectionErrors_Apex(String logData) {
    if (logData == null || logData.trim() == '') {
      return false;
    }
    Log__c logInstance = new Log__c();
    logInstance = (Log__c) JSON.deserialize(logData, Log__c.class);
    insert logInstance;
    return true;
  }

  @AuraEnabled
  public static Boolean updateLeadValues_Apex(String changedValues) {
    try {
      if (changedValues == null || changedValues.trim() == '') {
        return false;
      }

      Lead leadInstance = new Lead();
      leadInstance = (Lead) JSON.deserialize(changedValues, Lead.class);
      if (leadInstance != null) {
        update leadInstance;
      }
      return true;
    } catch (Exception ex) {
      Log__c logInstance = new Log__c();
      logInstance.Message__c =
        ex.getMessage() +
        ' at line number ' +
        ex.getLineNumber();
      logInstance.Severity__c = 'ERROR';
      logInstance.Source__c = 'UpdateLeadValues';
      if (logInstance != null) {
        insert logInstance;
      }
    }
    return false;
  }

  // Changes for ticket - DIN-169 : Open record content in form.
  // Start
  // Description : Processes DocFab selection and returns the DocFab URL.
  // For Leads: finds existing journal by Record Model or creates new.
  // For Journals: reuses existing DocFab record or creates new.
  @AuraEnabled
  public static String processDocFabSelection(
    List<Journal__c> journalData,
    DF_DocFabricator_Utility.DocFabSelectionResult selection,
    String resolvedMarketUnit,
    String objectName,
    String contextRecordId
  ) {
    try {
      if (journalData.isEmpty()) {
        return null;
      }

      Doc_Fabricator_Setting__c docFabSetting = Doc_Fabricator_Setting__c.getOrgDefaults();
      if (docFabSetting == null || String.isBlank(docFabSetting.URL__c)) {
        return 'DocFab base URL is missing in Doc_Fabricator_Setting__c.';
      }

      String targetModelId = selection.recordModelId != null
        ? String.valueOf(selection.recordModelId)
        : null;
      if (objectName == 'Lead') {
        return handleLeadDocFabFlow(
          selection,
          docFabSetting,
          resolvedMarketUnit,
          contextRecordId,
          targetModelId
        );
      }

      String externalRecordUuid = journalData[0].External_record_uuid__c;
      String existingRecordModelId = journalData[0].DocFab_Record_Model_ID__c;
      Boolean modelMatchesExisting =
        selection.recordModelId != null &&
        !String.isBlank(existingRecordModelId) &&
        existingRecordModelId == targetModelId;

      // Reuse existing when possible - for non-Lead objects, always reuse if there's an existing DocFab record
      if (!String.isBlank(externalRecordUuid)) {
        return DF_DocFabricator_Utility.buildDocFabUrl(
          docFabSetting.URL__c,
          externalRecordUuid,
          selection.formUuid
        );
      }

      String recordUuidOrError = DF_DocFabricator_Utility.AuthenticateCurrentSalesforceUser_Apex(
        String.valueOf(selection.recordModelId.longValue()),
        journalData,
        selection.fieldConfigurationJson
      );
      if (String.isBlank(recordUuidOrError)) {
        DFJ_ErrorLogController.addErrorLogs(
          journalData[0].Id,
          'DocFab creation',
          '',
          'Error',
          'Empty DocFab response for model ' +
          String.valueOf(selection.recordModelId),
          '',
          ''
        );
        return 'Can not create record in DocFabricator. Please contact your admin.';
      }
      if (
        recordUuidOrError.contains('Current user with') ||
        recordUuidOrError.contains('Error')
      ) {
        DFJ_ErrorLogController.addErrorLogs(
          journalData[0].Id,
          'DocFab creation',
          recordUuidOrError,
          'Error',
          'DocFab returned error for model ' +
          String.valueOf(selection.recordModelId),
          '',
          ''
        );
        return recordUuidOrError;
      }

      journalData[0].External_record_uuid__c = recordUuidOrError;
      journalData[0].DocFab_Record_Model_ID__c = selection.recordModelId != null
        ? String.valueOf(selection.recordModelId)
        : null;
      update journalData;

      return DF_DocFabricator_Utility.buildDocFabUrl(
        docFabSetting.URL__c,
        recordUuidOrError,
        selection.formUuid
      );
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        journalData[0].Id,
        'Selecting DocFab configuration',
        ex.getMessage(),
        'Error',
        'processDocFabSelection apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      return null;
    }
  }
  // End

  private static String handleLeadDocFabFlow(
    DF_DocFabricator_Utility.DocFabSelectionResult selection,
    Doc_Fabricator_Setting__c docFabSetting,
    String resolvedMarketUnit,
    String leadId,
    String targetModelId
  ) {
    List<Journal__c> leadJournals = new List<Journal__c>();
    if (!String.isBlank(leadId)) {
      leadJournals = [
        SELECT
          Id,
          Name,
          External_record_uuid__c,
          DocFab_Record_Model_ID__c,
          Market_Unit__c,
          CreatedDate
        FROM Journal__c
        WHERE Lead__c = :leadId
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate DESC
        LIMIT 10000
      ];
    }

    if (leadJournals.isEmpty()) {
      return null;
    }

    List<Journal__c> matchingDocFab = new List<Journal__c>();
    for (Journal__c j : leadJournals) {
      if (String.isBlank(j.External_record_uuid__c)) {
        continue;
      }
      if (
        !String.isBlank(targetModelId) &&
        targetModelId == j.DocFab_Record_Model_ID__c
      ) {
        matchingDocFab.add(j);
      }
    }

    if (!matchingDocFab.isEmpty()) {
      // Journals are ordered DESC by CreatedDate; take the newest match.
      return DF_DocFabricator_Utility.buildDocFabUrl(
        docFabSetting.URL__c,
        matchingDocFab[0].External_record_uuid__c,
        selection.formUuid
      );
    }

    // No matching DocFab journal exists; check if there's a blank journal we can reuse
    // (one without External_record_uuid__c - possibly created by journalAssociatedWithLead)
    Journal__c journalToUse = null;
    for (Journal__c j : leadJournals) {
      if (
        String.isBlank(j.External_record_uuid__c) &&
        String.isBlank(j.DocFab_Record_Model_ID__c)
      ) {
        // Found a blank journal - reuse it instead of creating a new one
        journalToUse = j;
        break;
      }
    }

    // If no blank journal exists, create a new one
    if (journalToUse == null) {
      journalToUse = new Journal__c();
      journalToUse.Lead__c = leadId;
      if (!String.isBlank(resolvedMarketUnit)) {
        journalToUse.Market_Unit__c = resolvedMarketUnit;
      }
    }

    List<Journal__c> transientList = new List<Journal__c>{ journalToUse };
    String recordUuidOrError = DF_DocFabricator_Utility.AuthenticateCurrentSalesforceUser_Apex(
      String.valueOf(selection.recordModelId.longValue()),
      transientList,
      selection.fieldConfigurationJson
    );
    if (String.isBlank(recordUuidOrError)) {
      DFJ_ErrorLogController.addErrorLogs(
        leadId,
        'DocFab creation',
        '',
        'Error',
        'Empty DocFab response for model ' +
        String.valueOf(selection.recordModelId),
        '',
        ''
      );
      return 'Can not create record in DocFabricator. Please contact your admin.';
    }
    if (
      recordUuidOrError.contains('Current user with') ||
      recordUuidOrError.contains('Error')
    ) {
      DFJ_ErrorLogController.addErrorLogs(
        leadId,
        'DocFab creation',
        recordUuidOrError,
        'Error',
        'DocFab returned error for model ' +
        String.valueOf(selection.recordModelId),
        '',
        ''
      );
      return recordUuidOrError;
    }

    journalToUse.External_record_uuid__c = recordUuidOrError;
    journalToUse.DocFab_Record_Model_ID__c = targetModelId;

    // Use upsert to handle both new and existing journals
    upsert journalToUse;

    return DF_DocFabricator_Utility.buildDocFabUrl(
      docFabSetting.URL__c,
      recordUuidOrError,
      selection.formUuid
    );
  }

  //Changes DIN-371 : Populating Related Journal Lookup Field
  //Start
  // Description : Updates the Journal lookup field on related journal records

  public static Boolean updateLookupFieldOfJournal(
    List<Journal__c> journalData,
    String journalExternalUuid,
    String journalSObjectName
  ) {
    try {
      String query =
        'SELECT uuid__c, Id, version__c,Journal__c FROM ' +
        journalSObjectName +
        ' WHERE uuid__c =\'' +
        journalExternalUuid +
        '\' LIMIT 1';
      List<SObject> journalRecordToUpdate = Database.query(query);
      if (!journalRecordToUpdate.isEmpty() && !journalData.isEmpty()) {
        journalRecordToUpdate[0].put('Journal__c', journalData[0].Id);
        update journalRecordToUpdate;
        return true;
      }
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        journalData[0].Id,
        'Updating ' + journalSObjectName + ' Object with Journal LookUp Field',
        ex.getMessage(),
        'Error',
        'DFJ_JournalForm.updateLookupFieldOfJournal apex method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
    }
    return false;
  }
  //End

  private static String resolveMarketUnit(
    Journal__c journalRecord,
    String objectName,
    String contextRecordId
  ) {
    if (
      journalRecord != null && !String.isBlank(journalRecord.Market_Unit__c)
    ) {
      return journalRecord.Market_Unit__c;
    }
    if (objectName == 'Lead' && !String.isBlank(contextRecordId)) {
      List<Lead> leads = [
        SELECT Market_Unit__c
        FROM Lead
        WHERE Id = :contextRecordId
        LIMIT 1
      ];
      if (!leads.isEmpty() && !String.isBlank(leads[0].Market_Unit__c)) {
        return leads[0].Market_Unit__c;
      }
    }
    if (objectName == 'Opportunity' && !String.isBlank(contextRecordId)) {
      List<Opportunity> opps = [
        SELECT Market_Unit__c
        FROM Opportunity
        WHERE Id = :contextRecordId
        LIMIT 1
      ];
      if (!opps.isEmpty() && !String.isBlank(opps[0].Market_Unit__c)) {
        return opps[0].Market_Unit__c;
      }
    }
    List<User> users = [
      SELECT Market_Unit__c
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    if (!users.isEmpty() && !String.isBlank(users[0].Market_Unit__c)) {
      return users[0].Market_Unit__c;
    }
    return null;
  }

  private static List<DocFabOption> buildDocFabOptionsForLead(
    String leadId,
    Decimal targetRecordModelId,
    String selectedFormUuid
  ) {
    List<DocFabOption> options = new List<DocFabOption>();
    if (String.isBlank(leadId)) {
      return options;
    }
    Doc_Fabricator_Setting__c docFabSetting = Doc_Fabricator_Setting__c.getOrgDefaults();
    if (docFabSetting == null || String.isBlank(docFabSetting.URL__c)) {
      return options;
    }
    List<Journal__c> leadJournals = [
      SELECT
        Id,
        Name,
        External_record_uuid__c,
        DocFab_Record_Model_ID__c,
        Market_Unit__c
      FROM Journal__c
      WHERE Lead__c = :leadId AND External_record_uuid__c != NULL
      WITH SECURITY_ENFORCED
      LIMIT 10000
    ];
    for (Journal__c j : leadJournals) {
      if (String.isBlank(j.DocFab_Record_Model_ID__c)) {
        continue;
      }
      Decimal recordModel;
      try {
        recordModel = Decimal.valueOf(j.DocFab_Record_Model_ID__c);
      } catch (Exception e) {
        continue;
      }
      if (targetRecordModelId != null && targetRecordModelId != recordModel) {
        continue;
      }
      // Use the selected form UUID directly instead of looking it up again
      String url = DF_DocFabricator_Utility.buildDocFabUrl(
        docFabSetting.URL__c,
        j.External_record_uuid__c,
        selectedFormUuid
      );
      if (String.isBlank(url)) {
        continue;
      }
      DocFabOption opt = new DocFabOption();
      opt.label = 'Model ' + String.valueOf(recordModel) + ' - ' + j.Name;
      opt.url = url;
      opt.recordModelId = recordModel;
      options.add(opt);
    }
    return options;
  }

  /**
   * Clean up a lead-scoped journal that failed DocFab creation (no external UUID or record model).
   * Also removes any related Person__c rows created alongside it.
   */
  private static void cleanupLeadDraftJournal(String journalId) {
    if (String.isBlank(journalId)) {
      return;
    }
    try {
      List<Journal__c> journals = [
        SELECT Id, External_record_uuid__c, DocFab_Record_Model_ID__c, Lead__c
        FROM Journal__c
        WHERE Id = :journalId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (journals.isEmpty()) {
        return;
      }
      Journal__c j = journals[0];
      // Only delete if we never linked to DocFab
      if (
        !String.isBlank(j.External_record_uuid__c) ||
        !String.isBlank(j.DocFab_Record_Model_ID__c)
      ) {
        return;
      }
      // Remove related persons first to avoid orphan data
      List<Person__c> people = [
        SELECT Id
        FROM Person__c
        WHERE Journal__c = :journalId
        WITH SECURITY_ENFORCED
        LIMIT 10000
      ];
      if (!people.isEmpty()) {
        delete people;
      }
      delete j;
    } catch (Exception e) {
      DFJ_ErrorLogController.addErrorLogs(
        journalId,
        'cleanupLeadDraftJournal',
        e.getMessage(),
        'Error',
        'Failed to clean up draft journal after DocFab failure',
        e.getStackTraceString(),
        String.valueOf(e.getLineNumber())
      );
    }
  }
  //Changes DIN-383 : Improve Journal History
  //Start
  // Description :Creation the Old and New record of Journal Hstroy Object
  @AuraEnabled
  public static List<Journal__c> updateJournalHistroyRecord(
    String journalHistoryData
  ) {
    try {
      if (String.isNotBlank(journalHistoryData)) {
        Journal_History__c journalHistoryInstance = new Journal_History__c();
        journalHistoryInstance = (Journal_History__c) JSON.deserialize(
          journalHistoryData,
          Journal_History__c.class
        );
        insert journalHistoryInstance;
        //DFJ-160 changes added Retskreds__c on the Query param
        List<Journal__c> journalList = new List<Journal__c>();
        journalList = [
          SELECT
            Id,
            LastModifiedDate,
            Journal_States__c,
            Retskreds__c,
            Responsible_Lawyer__c,
            journal_Deadline__c
          FROM Journal__c
          WHERE Id = :journalHistoryInstance.Journal__c
          WITH SECURITY_ENFORCED
          LIMIT 1
        ];
        return journalList;
      }
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Inserting Records of journal History',
        ex.getMessage(),
        'Error',
        'DFJ_JournalForm.updateLookupFieldOfJournal apex method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
    }
    return null;
  }
  //end

  //Start Changes TCS_53 Additonal Journal on account
  // Description :Creation the New record of Journal on Account
  // Changes DFJ-77 Starts Added the String orderId param to class to associate order with Journal(if selected)
  // Updated: Added recordModelId parameter for two-tier permission-based selection
  @AuraEnabled
  public static List<Journal__c> journalAssociatedWithAccount(
    String recordId,
    String orderId,
    String recordModelId
  ) {
    if (recordId.trim() != '' && recordId != null) {
      List<Account> listOfAccount = new List<Account>();
      List<Journal__c> listOfJournals = new List<Journal__c>();
      listOfAccount = [
        SELECT Name, FirstName, LastName, Market_Unit__c
        FROM Account
        WHERE Id = :recordId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];

      //Checking for the value of the field Civil Statu

      if (!listOfAccount.isEmpty()) {
        Journal__c journalInstance = new Journal__c();
        journalInstance.Account__c = recordId;
        //Changes DFJ-77 Starts
        if (orderId != null && orderId.trim() != '') {
          journalInstance.Order__c = orderId;
        }
        //End
        // Set Record Model ID for two-tier selection
        if (recordModelId != null && recordModelId.trim() != '') {
          journalInstance.DocFab_Record_Model_ID__c = recordModelId;
        }
        journalInstance.Market_Unit__c = listOfAccount[0].Market_Unit__c;
        listOfJournals.add(journalInstance);
      }
      if (!listOfJournals.isEmpty()) {
        upsert listOfJournals;
        return listOfJournals;
      }
    }
    return null;
  }

  //Start Changes DFJ-77 Add picklist value for Order related to that account
  // Description :Show the Order  related to the account when clicking the Create New Journal Button on Account.
  @AuraEnabled
  public static List<Order> ordersAssociatedWithAccount(String recordId) {
    if (recordId.trim() != '' && recordId != null) {
      List<Order> listOfOrders = new List<Order>();
      listOfOrders = [
        SELECT Id, Account.name, Provision_Value__c, OrderNumber
        FROM Order
        WHERE AccountId = :recordId
      ];
      if (!listOfOrders.isEmpty()) {
        return listOfOrders;
      }
    }
    return null;
  }
}
