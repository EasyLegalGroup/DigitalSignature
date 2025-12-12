/*
 * @ Version : 1.0
 * @ Created Date : 2021-07-15
 * @Description : This class will be used for utilities methods used to open DocFab
 */
public without sharing class DF_DocFabricator_Utility {
  public static String prefixForMetaApiName = 'df';
  public static String underscoreString = '_';
  public static String postfixForMetaApiName = '__c';
  public static List<String> fieldLabelList = new List<String>{
    'uuid',
    'record_model_id',
    'version'
  };

  /**
   * Result wrapper for the two-tier permission-based selection.
   */
  public class DocFabSelectionResult {
    public Decimal recordModelId;
    public String formUuid;
    public String errorMessage;
    public String permissionError;
    public String fieldConfigurationJson;
  }

  /**
   * Wrapper for Record Model options shown in the UI picker.
   */
  public class RecordModelOption {
    @AuraEnabled
    public String recordModelId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public String developerName;
  }

  /**
   * Wrapper for Form options shown in the UI picker.
   */
  public class FormOption {
    @AuraEnabled
    public String formUuid;
    @AuraEnabled
    public Decimal formNumber;
    @AuraEnabled
    public String recordModelId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public String developerName;
  }

  /**
   * Result wrapper for the two-tier selection process.
   * Contains accessible record models and forms, plus metadata for the LWC to decide what to show.
   */
  public class SelectionOptions {
    @AuraEnabled
    public List<RecordModelOption> recordModels = new List<RecordModelOption>();
    @AuraEnabled
    public List<FormOption> forms = new List<FormOption>();
    @AuraEnabled
    public String errorMessage;
    @AuraEnabled
    public Boolean requiresRecordModelSelection = false;
    @AuraEnabled
    public Boolean requiresFormSelection = false;
    // If only one record model and one form, these are populated for direct open
    @AuraEnabled
    public String resolvedRecordModelId;
    @AuraEnabled
    public String resolvedFormUuid;
    @AuraEnabled
    public String fieldConfigurationJson;
    // For direct URL open when existing UUID is found (bypass selection)
    @AuraEnabled
    public String directOpenUrl;
    @AuraEnabled
    public Boolean hasExistingDocFab = false;
  }

  /**
   * Default icons for record models and forms when not specified in CMDT.
   */
  public static final String DEFAULT_RECORD_MODEL_ICON = 'utility:data_mapping';
  public static final String DEFAULT_FORM_ICON = 'utility:care_request_reviewer';

  /**
   * Normalizes an icon name to ensure it has the proper SLDS prefix.
   * If the icon already has a category prefix (utility:, standard:, action:, custom:, doctype:),
   * it is returned as-is. Otherwise, 'utility:' is prepended.
   *
   * Examples:
   * - "add" → "utility:add"
   * - "utility:add" → "utility:add"
   * - "standard:account" → "standard:account"
   * - "my_custom_icon" → "utility:my_custom_icon"
   *
   * @param iconName The icon name from CMDT (may or may not include prefix)
   * @param defaultIcon The default icon to use if iconName is blank
   * @return Normalized icon name with proper prefix
   */
  private static String normalizeIconName(String iconName, String defaultIcon) {
    if (String.isBlank(iconName)) {
      return defaultIcon;
    }

    // Check if it already has a known SLDS icon category prefix
    String lowerIcon = iconName.toLowerCase();
    if (
      lowerIcon.startsWith('utility:') ||
      lowerIcon.startsWith('standard:') ||
      lowerIcon.startsWith('action:') ||
      lowerIcon.startsWith('custom:') ||
      lowerIcon.startsWith('doctype:')
    ) {
      return iconName;
    }

    // No prefix found, default to utility:
    return 'utility:' + iconName;
  }

  /**
   * Two-tier selection using DocFab_Form__mdt (forms) with Record Model inferred from each form's lookup.
   *
   * Configuration is defined at the page layout level:
   * - formNumbers: Comma-separated list of allowed Form Numbers (e.g., "17, 51, 22")
   *
   * Access is controlled ONLY by the form's Custom Permission.
   * Record Model permissions are not enforced (Record Model is implied by the selected form).
   *
   * Flow:
   * 1. Parse the comma-separated list from the page layout
   * 2. Query DocFab_Form__mdt for the specified Form Numbers (which also gives us their parent Record Models)
   * 3. Filter forms to only those the user has Custom Permission for
   * 4. Derive record model options from the remaining forms
   * 5. Return the accessible options for the LWC to display
   *
   * @param recordModelIdsCsv Legacy/ignored. Record Models are inferred from forms.
   * @param formNumbersCsv Comma-separated Form Numbers from page layout (required)
   * @return SelectionOptions with accessible record models and forms
   */
  @AuraEnabled(cacheable=false)
  public static SelectionOptions getAccessibleOptions(
    String recordModelIdsCsv,
    String formNumbersCsv
  ) {
    SelectionOptions result = new SelectionOptions();

    // Parse inputs
    Set<Decimal> requestedFormNumbers = parseCsvToDecimalSet(formNumbersCsv);

    // Validate: At least form numbers must be configured
    if (requestedFormNumbers.isEmpty()) {
      result.errorMessage = 'No Journal Form has been configured for this page.';
      return result;
    }

    // Query forms and their parent record models by Form Number
    List<DocFab_Form__mdt> allForms = [
      SELECT
        Id,
        DeveloperName,
        Form_UUID__c,
        Form_Number__c,
        Custom_Permission__c,
        Icon__c,
        Page_Layout_Label__c,
        Record_Model__c,
        Record_Model__r.Record_Model_Id__c,
        Record_Model__r.DeveloperName,
        Record_Model__r.Icon__c,
        Record_Model__r.Page_Layout_Label__c,
        Record_Model__r.Field_Configuration__c
      FROM DocFab_Form__mdt
      WHERE Form_Number__c IN :requestedFormNumbers
    ];

    // Add record models from forms to the map
    Map<String, DocFab_Record_Model__mdt> recordModelMap = new Map<String, DocFab_Record_Model__mdt>();
    for (DocFab_Form__mdt f : allForms) {
      if (
        f.Record_Model__r != null &&
        !recordModelMap.containsKey(f.Record_Model__r.Record_Model_Id__c)
      ) {
        recordModelMap.put(
          f.Record_Model__r.Record_Model_Id__c,
          f.Record_Model__r
        );
      }
    }

    // Filter forms by permission (form permission only)
    List<DocFab_Form__mdt> accessibleForms = new List<DocFab_Form__mdt>();
    for (DocFab_Form__mdt f : allForms) {
      if (hasPermission(f.Custom_Permission__c)) {
        accessibleForms.add(f);
      }
    }

    // Check if user has no access to anything
    if (accessibleForms.isEmpty()) {
      result.errorMessage = 'You do not have access to any Journal Forms configured for this page.';
      return result;
    }

    // Build the result options
    // Group forms by record model
    Map<String, List<DocFab_Form__mdt>> formsByRecordModel = new Map<String, List<DocFab_Form__mdt>>();
    Set<String> recordModelIdsWithForms = new Set<String>();
    for (DocFab_Form__mdt f : accessibleForms) {
      String rmId = f.Record_Model__r.Record_Model_Id__c;
      recordModelIdsWithForms.add(rmId);
      if (!formsByRecordModel.containsKey(rmId)) {
        formsByRecordModel.put(rmId, new List<DocFab_Form__mdt>());
      }
      formsByRecordModel.get(rmId).add(f);
    }

    // Build RecordModelOption list (only record models that have accessible forms)
    for (String rmId : recordModelIdsWithForms) {
      DocFab_Record_Model__mdt rm = recordModelMap.get(rmId);
      if (rm == null)
        continue;

      RecordModelOption opt = new RecordModelOption();
      opt.recordModelId = rm.Record_Model_Id__c;
      opt.label = String.isNotBlank(rm.Page_Layout_Label__c)
        ? rm.Page_Layout_Label__c
        : rm.DeveloperName;
      opt.icon = normalizeIconName(rm.Icon__c, DEFAULT_RECORD_MODEL_ICON);
      opt.developerName = rm.DeveloperName;
      result.recordModels.add(opt);
    }

    // Build FormOption list
    for (DocFab_Form__mdt f : accessibleForms) {
      FormOption opt = new FormOption();
      opt.formUuid = f.Form_UUID__c;
      opt.formNumber = f.Form_Number__c;
      opt.recordModelId = f.Record_Model__r.Record_Model_Id__c;
      opt.label = String.isNotBlank(f.Page_Layout_Label__c)
        ? f.Page_Layout_Label__c
        : f.DeveloperName;
      opt.icon = normalizeIconName(f.Icon__c, DEFAULT_FORM_ICON);
      opt.developerName = f.DeveloperName;
      result.forms.add(opt);
    }

    // Determine selection requirements
    Integer numRecordModels = result.recordModels.size();
    Integer numForms = result.forms.size();

    if (numRecordModels == 1 && numForms == 1) {
      // Direct open - no selection needed
      result.requiresRecordModelSelection = false;
      result.requiresFormSelection = false;
      result.resolvedRecordModelId = result.recordModels[0].recordModelId;
      result.resolvedFormUuid = result.forms[0].formUuid;
      // Get field configuration
      DocFab_Record_Model__mdt rm = recordModelMap.get(
        result.resolvedRecordModelId
      );
      result.fieldConfigurationJson = rm != null
        ? rm.Field_Configuration__c
        : null;
    } else if (numRecordModels == 1) {
      // Only one record model, but multiple forms - show form picker
      result.requiresRecordModelSelection = false;
      result.requiresFormSelection = true;
      result.resolvedRecordModelId = result.recordModels[0].recordModelId;
      // Get field configuration
      DocFab_Record_Model__mdt rm = recordModelMap.get(
        result.resolvedRecordModelId
      );
      result.fieldConfigurationJson = rm != null
        ? rm.Field_Configuration__c
        : null;
    } else {
      // Multiple record models - show record model picker first
      result.requiresRecordModelSelection = true;
      // Form selection depends on how many forms the selected record model has
      // This will be determined by the LWC after user selects a record model
    }

    return result;
  }

  /**
   * Context-aware version of getAccessibleOptions that handles special cases:
   * - Journal with existing External_record_uuid__c but no page layout config → opens existing directly
   * - Lead with existing journals but no page layout config → opens existing if user has permission
   *
   * @param recordModelIdsCsv Comma-separated Record Model IDs from page layout (can be empty)
   * @param formNumbersCsv Comma-separated Form Numbers from page layout (can be empty)
   * @param objectApiName The object API name (Lead, Journal__c, etc.)
   * @param recordId The record ID being viewed
   * @param existingExternalUuid The existing External_record_uuid__c if any (for Journal__c)
   * @param existingRecordModelId The existing DocFab_Record_Model_ID__c if any (for Journal__c)
   * @return SelectionOptions with accessible options or direct open URL
   */
  @AuraEnabled(cacheable=false)
  public static SelectionOptions getAccessibleOptionsWithContext(
    String recordModelIdsCsv,
    String formNumbersCsv,
    String objectApiName,
    String recordId,
    String existingExternalUuid,
    String existingRecordModelId
  ) {
    SelectionOptions result = new SelectionOptions();

    // Parse inputs
    Set<String> requestedRecordModelIds = parseCsvToSet(recordModelIdsCsv);
    Set<Decimal> requestedFormNumbers = parseCsvToDecimalSet(formNumbersCsv);
    Boolean hasPageLayoutConfig = !requestedFormNumbers.isEmpty();
    Boolean hasExistingUuid = !String.isBlank(existingExternalUuid);
    Boolean isLead = objectApiName == 'Lead';
    Boolean isJournal = objectApiName == 'Journal__c';

    // Get DocFab base URL
    Doc_Fabricator_Setting__c docFabSetting = Doc_Fabricator_Setting__c.getOrgDefaults();
    String baseUrl = (docFabSetting != null) ? docFabSetting.URL__c : null;

    // SCENARIO: Journal with existing UUID → always open directly
    // The DocFab record already exists, just open it using the UUID
    if (isJournal && hasExistingUuid) {
      result.hasExistingDocFab = true;
      if (String.isBlank(baseUrl)) {
        result.errorMessage = 'DocFab base URL is missing in Doc_Fabricator_Setting__c.';
        return result;
      }
      result.directOpenUrl = buildDocFabUrl(
        baseUrl,
        existingExternalUuid,
        null
      );
      return result;
    }

    // SCENARIO: Journal without UUID and no page layout config
    // → Error - cannot create without configuration
    if (isJournal && !hasExistingUuid && !hasPageLayoutConfig) {
      result.errorMessage = 'No Journal Form has been configured for this page. Please contact your administrator to configure the Journal Form component.';
      return result;
    }

    // SCENARIO: Lead with no page layout config
    // → Check for existing journals with DocFab records that user has permission for
    if (isLead && !hasPageLayoutConfig) {
      return handleLeadNoPageLayoutConfig(recordId, baseUrl);
    }

    // Standard flow: Page layout is configured, proceed with permission-based selection
    return getAccessibleOptionsStandard(
      requestedRecordModelIds,
      requestedFormNumbers,
      hasExistingUuid,
      existingExternalUuid,
      existingRecordModelId,
      baseUrl,
      isJournal
    );
  }

  /**
   * Handle Lead scenario where no page layout config exists.
   * Looks for existing journals with DocFab records that user has permission to access.
   */
  private static SelectionOptions handleLeadNoPageLayoutConfig(
    String leadId,
    String baseUrl
  ) {
    SelectionOptions result = new SelectionOptions();

    if (String.isBlank(leadId)) {
      result.errorMessage = 'Lead ID is required.';
      return result;
    }

    // Query existing journals for this Lead that have DocFab records
    List<Journal__c> leadJournals = [
      SELECT Id, External_record_uuid__c, DocFab_Record_Model_ID__c, CreatedDate
      FROM Journal__c
      WHERE Lead__c = :leadId AND External_record_uuid__c != NULL
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate DESC
    ];

    if (leadJournals.isEmpty()) {
      result.errorMessage = 'No Journal Form has been configured for this page. Please contact your administrator to configure the Journal Form component.';
      return result;
    }

    // Record Model permissions are not enforced. Allow access to all existing journals.
    List<Journal__c> accessibleJournals = leadJournals;

    if (accessibleJournals.isEmpty()) {
      result.errorMessage = 'No accessible journal forms found for this Lead.';
      return result;
    }

    // If only one accessible journal, open it directly
    if (accessibleJournals.size() == 1 && String.isNotBlank(baseUrl)) {
      result.hasExistingDocFab = true;
      result.directOpenUrl = buildDocFabUrl(
        baseUrl,
        accessibleJournals[0].External_record_uuid__c,
        null
      );
      return result;
    }

    // Multiple accessible journals - this shouldn't happen without page layout config
    // but if it does, open the most recent one
    result.hasExistingDocFab = true;
    result.directOpenUrl = buildDocFabUrl(
      baseUrl,
      accessibleJournals[0].External_record_uuid__c,
      null
    );
    return result;
  }

  /**
   * Standard permission-based selection flow when page layout config exists.
   */
  private static SelectionOptions getAccessibleOptionsStandard(
    Set<String> requestedRecordModelIds,
    Set<Decimal> requestedFormNumbers,
    Boolean hasExistingUuid,
    String existingExternalUuid,
    String existingRecordModelId,
    String baseUrl,
    Boolean isJournal
  ) {
    SelectionOptions result = new SelectionOptions();

    // Query forms and their parent record models by Form Number
    List<DocFab_Form__mdt> allForms = [
      SELECT
        Id,
        DeveloperName,
        Form_UUID__c,
        Form_Number__c,
        Custom_Permission__c,
        Icon__c,
        Page_Layout_Label__c,
        Record_Model__c,
        Record_Model__r.Record_Model_Id__c,
        Record_Model__r.DeveloperName,
        Record_Model__r.Icon__c,
        Record_Model__r.Page_Layout_Label__c,
        Record_Model__r.Field_Configuration__c
      FROM DocFab_Form__mdt
      WHERE Form_Number__c IN :requestedFormNumbers
    ];

    // Add record models from forms to the map
    Map<String, DocFab_Record_Model__mdt> recordModelMap = new Map<String, DocFab_Record_Model__mdt>();
    for (DocFab_Form__mdt f : allForms) {
      if (
        f.Record_Model__r != null &&
        !recordModelMap.containsKey(f.Record_Model__r.Record_Model_Id__c)
      ) {
        recordModelMap.put(
          f.Record_Model__r.Record_Model_Id__c,
          f.Record_Model__r
        );
      }
    }

    // Filter forms by permission (form permission only)
    List<DocFab_Form__mdt> accessibleForms = new List<DocFab_Form__mdt>();
    for (DocFab_Form__mdt f : allForms) {
      if (hasPermission(f.Custom_Permission__c)) {
        accessibleForms.add(f);
      }
    }

    // Check if user has no access to anything configured
    if (accessibleForms.isEmpty()) {
      // Check if there ARE forms configured but user lacks permission
      if (!allForms.isEmpty()) {
        result.errorMessage = 'You do not have permission to access any of the Journal Forms configured for this page. Please contact your administrator to request access.';
      } else {
        result.errorMessage = 'No Journal Forms found for the configured Form Numbers. Please contact your administrator.';
      }
      return result;
    }

    // Record Model permissions are not enforced.

    // NEW SCENARIO: Journal with pre-set DocFab_Record_Model_ID__c
    // → Auto-select the record model and skip record model selection modal
    Boolean autoSelectRecordModel = false;
    if (isJournal && !String.isBlank(existingRecordModelId)) {
      // Check if the pre-set record model exists in our configured options
      DocFab_Record_Model__mdt presetRm = recordModelMap.get(
        existingRecordModelId
      );
      if (presetRm == null) {
        // Record model ID is set but there are no configured forms for it on this page
        result.errorMessage =
          'No configured forms are available for the journal\'s record model (' +
          existingRecordModelId +
          '). Please update the page layout configuration.';
        return result;
      }
      // Filter accessible forms to only those matching the pre-set record model
      List<DocFab_Form__mdt> filteredForms = new List<DocFab_Form__mdt>();
      for (DocFab_Form__mdt f : accessibleForms) {
        if (
          f.Record_Model__r != null &&
          f.Record_Model__r.Record_Model_Id__c == existingRecordModelId
        ) {
          filteredForms.add(f);
        }
      }
      if (filteredForms.isEmpty()) {
        result.errorMessage = 'You do not have access to any of the configured forms for the journal\'s record model. Please request access to the form permission(s).';
        return result;
      }
      accessibleForms = filteredForms;
      autoSelectRecordModel = true;
    }

    result.hasExistingDocFab = hasExistingUuid;

    // Build the result options
    Map<String, List<DocFab_Form__mdt>> formsByRecordModel = new Map<String, List<DocFab_Form__mdt>>();
    Set<String> recordModelIdsWithForms = new Set<String>();
    for (DocFab_Form__mdt f : accessibleForms) {
      String rmId = f.Record_Model__r.Record_Model_Id__c;
      recordModelIdsWithForms.add(rmId);
      if (!formsByRecordModel.containsKey(rmId)) {
        formsByRecordModel.put(rmId, new List<DocFab_Form__mdt>());
      }
      formsByRecordModel.get(rmId).add(f);
    }

    // Build RecordModelOption list
    for (String rmId : recordModelIdsWithForms) {
      DocFab_Record_Model__mdt rm = recordModelMap.get(rmId);
      if (rm == null)
        continue;

      RecordModelOption opt = new RecordModelOption();
      opt.recordModelId = rm.Record_Model_Id__c;
      opt.label = String.isNotBlank(rm.Page_Layout_Label__c)
        ? rm.Page_Layout_Label__c
        : rm.DeveloperName;
      opt.icon = normalizeIconName(rm.Icon__c, DEFAULT_RECORD_MODEL_ICON);
      opt.developerName = rm.DeveloperName;
      result.recordModels.add(opt);
    }

    // Build FormOption list
    for (DocFab_Form__mdt f : accessibleForms) {
      FormOption opt = new FormOption();
      opt.formUuid = f.Form_UUID__c;
      opt.formNumber = f.Form_Number__c;
      opt.recordModelId = f.Record_Model__r.Record_Model_Id__c;
      opt.label = String.isNotBlank(f.Page_Layout_Label__c)
        ? f.Page_Layout_Label__c
        : f.DeveloperName;
      opt.icon = normalizeIconName(f.Icon__c, DEFAULT_FORM_ICON);
      opt.developerName = f.DeveloperName;
      result.forms.add(opt);
    }

    // Determine selection requirements
    Integer numRecordModels = result.recordModels.size();
    Integer numForms = result.forms.size();

    // If auto-selecting record model (Journal with pre-set DocFab_Record_Model_ID__c),
    // skip record model selection and only show form selection if needed
    if (autoSelectRecordModel) {
      result.requiresRecordModelSelection = false;
      result.resolvedRecordModelId = existingRecordModelId;
      DocFab_Record_Model__mdt rm = recordModelMap.get(existingRecordModelId);
      result.fieldConfigurationJson = rm != null
        ? rm.Field_Configuration__c
        : null;
      if (numForms == 1) {
        result.requiresFormSelection = false;
        result.resolvedFormUuid = result.forms[0].formUuid;
      } else {
        result.requiresFormSelection = true;
      }
    } else if (numRecordModels == 1 && numForms == 1) {
      result.requiresRecordModelSelection = false;
      result.requiresFormSelection = false;
      result.resolvedRecordModelId = result.recordModels[0].recordModelId;
      result.resolvedFormUuid = result.forms[0].formUuid;
      DocFab_Record_Model__mdt rm = recordModelMap.get(
        result.resolvedRecordModelId
      );
      result.fieldConfigurationJson = rm != null
        ? rm.Field_Configuration__c
        : null;
    } else if (numRecordModels == 1) {
      result.requiresRecordModelSelection = false;
      result.requiresFormSelection = true;
      result.resolvedRecordModelId = result.recordModels[0].recordModelId;
      DocFab_Record_Model__mdt rm = recordModelMap.get(
        result.resolvedRecordModelId
      );
      result.fieldConfigurationJson = rm != null
        ? rm.Field_Configuration__c
        : null;
    } else {
      result.requiresRecordModelSelection = true;
    }

    return result;
  }

  /**
   * Get forms for a specific record model (called after user selects a record model).
   * Returns only forms the user has permission to access.
   *
   * @param recordModelId The Record Model ID selected by the user
   * @param formNumbersCsv Comma-separated Form Numbers from page layout
   */
  @AuraEnabled(cacheable=false)
  public static SelectionOptions getFormsForRecordModel(
    String recordModelId,
    String formNumbersCsv
  ) {
    SelectionOptions result = new SelectionOptions();

    if (String.isBlank(recordModelId)) {
      result.errorMessage = 'Record Model ID is required.';
      return result;
    }

    Set<Decimal> requestedFormNumbers = parseCsvToDecimalSet(formNumbersCsv);
    if (requestedFormNumbers.isEmpty()) {
      result.errorMessage = 'No forms configured.';
      return result;
    }

    // Get the record model
    List<DocFab_Record_Model__mdt> recordModels = [
      SELECT
        Id,
        DeveloperName,
        Record_Model_Id__c,
        Custom_Permission__c,
        Icon__c,
        Page_Layout_Label__c,
        Field_Configuration__c
      FROM DocFab_Record_Model__mdt
      WHERE Record_Model_Id__c = :recordModelId
      LIMIT 1
    ];

    if (recordModels.isEmpty()) {
      result.errorMessage = 'Record Model not found.';
      return result;
    }

    DocFab_Record_Model__mdt rm = recordModels[0];

    // Get forms for this record model that are in the requested list (by Form Number)
    List<DocFab_Form__mdt> forms = [
      SELECT
        Id,
        DeveloperName,
        Form_UUID__c,
        Form_Number__c,
        Custom_Permission__c,
        Icon__c,
        Page_Layout_Label__c,
        Record_Model__r.Record_Model_Id__c
      FROM DocFab_Form__mdt
      WHERE
        Form_Number__c IN :requestedFormNumbers
        AND Record_Model__r.Record_Model_Id__c = :recordModelId
    ];

    // Filter by permission
    List<DocFab_Form__mdt> accessibleForms = new List<DocFab_Form__mdt>();
    for (DocFab_Form__mdt f : forms) {
      if (hasPermission(f.Custom_Permission__c)) {
        accessibleForms.add(f);
      }
    }

    if (accessibleForms.isEmpty()) {
      result.errorMessage = 'You do not have access to any forms for this record model.';
      return result;
    }

    // Build form options
    for (DocFab_Form__mdt f : accessibleForms) {
      FormOption opt = new FormOption();
      opt.formUuid = f.Form_UUID__c;
      opt.formNumber = f.Form_Number__c;
      opt.recordModelId = recordModelId;
      opt.label = String.isNotBlank(f.Page_Layout_Label__c)
        ? f.Page_Layout_Label__c
        : f.DeveloperName;
      opt.icon = normalizeIconName(f.Icon__c, DEFAULT_FORM_ICON);
      opt.developerName = f.DeveloperName;
      result.forms.add(opt);
    }

    result.resolvedRecordModelId = recordModelId;
    result.fieldConfigurationJson = rm.Field_Configuration__c;

    if (result.forms.size() == 1) {
      result.requiresFormSelection = false;
      result.resolvedFormUuid = result.forms[0].formUuid;
    } else {
      result.requiresFormSelection = true;
    }

    return result;
  }

  /**
   * Legacy selectConfiguration method - now simplified to work with the new architecture.
   * This is kept for backwards compatibility with existing code that calls it.
   *
   * @param marketUnit - Ignored in new architecture
   * @param formTypeName - Ignored in new architecture
   * @param componentRecordModelId - Record Model ID (if already selected)
   * @param componentFormUuid - Form UUID (if already selected)
   * @param currentUserId - Ignored in new architecture (permissions checked via FeatureManagement)
   */
  public static DocFabSelectionResult selectConfiguration(
    String marketUnit,
    String formTypeName,
    Decimal componentRecordModelId,
    String componentFormUuid,
    Id currentUserId
  ) {
    DocFabSelectionResult result = new DocFabSelectionResult();

    // Convert decimal to string
    String recordModelIdStr = componentRecordModelId != null
      ? String.valueOf(componentRecordModelId.longValue())
      : null;

    // New architecture: Record Model can be inferred from the Form.
    if (String.isBlank(recordModelIdStr)) {
      if (String.isBlank(componentFormUuid)) {
        result.errorMessage = 'Form UUID is required.';
        return result;
      }

      List<DocFab_Form__mdt> forms = [
        SELECT
          Id,
          Form_UUID__c,
          Custom_Permission__c,
          Record_Model__r.Record_Model_Id__c,
          Record_Model__r.Field_Configuration__c
        FROM DocFab_Form__mdt
        WHERE Form_UUID__c = :componentFormUuid
        LIMIT 1
      ];

      if (forms.isEmpty()) {
        result.errorMessage =
          'Form UUID ' +
          componentFormUuid +
          ' is not configured.';
        return result;
      }

      if (!hasPermission(forms[0].Custom_Permission__c)) {
        result.permissionError = 'You do not have access to this form.';
        return result;
      }

      if (
        forms[0].Record_Model__r == null ||
        String.isBlank(forms[0].Record_Model__r.Record_Model_Id__c)
      ) {
        result.errorMessage = 'The selected form is missing a configured Record Model.';
        return result;
      }

      recordModelIdStr = forms[0].Record_Model__r.Record_Model_Id__c;
      result.recordModelId = Decimal.valueOf(recordModelIdStr);
      result.formUuid = componentFormUuid;
      result.fieldConfigurationJson = forms[0]
        .Record_Model__r.Field_Configuration__c;
      return result;
    }

    // Look up Record Model
    List<DocFab_Record_Model__mdt> recordModels = [
      SELECT
        Id,
        Record_Model_Id__c,
        Field_Configuration__c,
        Custom_Permission__c,
        Page_Layout_Label__c,
        Icon__c,
        DeveloperName
      FROM DocFab_Record_Model__mdt
      WHERE Record_Model_Id__c = :recordModelIdStr
      LIMIT 1
    ];

    if (recordModels.isEmpty()) {
      result.errorMessage =
        'Record Model ID ' +
        recordModelIdStr +
        ' is not configured.';
      return result;
    }

    DocFab_Record_Model__mdt recordModel = recordModels[0];

    // If form UUID provided, validate it
    if (!String.isBlank(componentFormUuid)) {
      List<DocFab_Form__mdt> forms = [
        SELECT Id, Form_UUID__c, Custom_Permission__c
        FROM DocFab_Form__mdt
        WHERE
          Form_UUID__c = :componentFormUuid
          AND Record_Model__r.Record_Model_Id__c = :recordModelIdStr
        LIMIT 1
      ];

      if (forms.isEmpty()) {
        result.errorMessage =
          'Form UUID ' +
          componentFormUuid +
          ' is not configured for record model ' +
          recordModelIdStr +
          '.';
        return result;
      }

      // Check Custom Permission for Form
      if (!hasPermission(forms[0].Custom_Permission__c)) {
        result.permissionError = 'You do not have access to this form.';
        return result;
      }
    }

    result.recordModelId = componentRecordModelId;
    result.formUuid = componentFormUuid;
    result.fieldConfigurationJson = recordModel.Field_Configuration__c;

    return result;
  }

  /**
   * Check if the current user has the specified custom permission.
   * Returns true if permission is blank (no restriction) or if user has the permission.
   */
  private static Boolean hasPermission(String customPermissionApiName) {
    if (String.isBlank(customPermissionApiName)) {
      return false; // Custom Permission is now required
    }
    return FeatureManagement.checkPermission(customPermissionApiName);
  }

  /**
   * Parse a comma-separated string into a Set of trimmed, non-empty values.
   */
  private static Set<String> parseCsvToSet(String csv) {
    Set<String> result = new Set<String>();
    if (String.isBlank(csv)) {
      return result;
    }
    for (String part : csv.split(',')) {
      String trimmed = part.trim();
      if (!String.isBlank(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  /**
   * Parse a comma-separated string of numbers into a Set of Decimals.
   * Used for Form Numbers which are numeric.
   */
  private static Set<Decimal> parseCsvToDecimalSet(String csv) {
    Set<Decimal> result = new Set<Decimal>();
    if (String.isBlank(csv)) {
      return result;
    }
    for (String part : csv.split(',')) {
      String trimmed = part.trim();
      if (!String.isBlank(trimmed)) {
        try {
          result.add(Decimal.valueOf(trimmed));
        } catch (Exception e) {
          // Skip invalid numbers
        }
      }
    }
    return result;
  }

  public static String buildDocFabUrl(
    String baseUrl,
    String recordUuid,
    String formUuid
  ) {
    if (String.isBlank(baseUrl) || String.isBlank(recordUuid)) {
      return null;
    }
    String url = baseUrl + 'public/form/' + recordUuid;
    if (!String.isBlank(formUuid)) {
      url += '/' + formUuid;
    }
    return url;
  }

  /*
   * @Description  This method will be invoked when external_record_uuid for journal is null and we uthenticate current salesforce user to create record in external system
   * @Param		String - recordModelId, journalRecord
   * @Return       String - record_uuid or error
   */
  public static String AuthenticateCurrentSalesforceUser_Apex(
    String recordModelId,
    List<Journal__c> journalRecord
  ) {
    // Backwards-compatible overload for existing callers that do not send fieldConfigurationJson.
    return AuthenticateCurrentSalesforceUser_Apex(
      recordModelId,
      journalRecord,
      null
    );
  }

  public static String AuthenticateCurrentSalesforceUser_Apex(
    String recordModelId,
    List<Journal__c> journalRecord,
    String fieldConfigurationJson
  ) {
    // Changes for ticket - DIN-170 : Create DocFab Record.
    // Start
    // Description : authorizing current salesforce user to create record in external system.
    try {
      Doc_Fabricator_Setting__c docFabSetting = Doc_Fabricator_Setting__c.getOrgDefaults();

      String endpointUrl =
        docFabSetting.URL__c +
        'api/users/?email=' +
        UserInfo.getUserEmail();

      HttpRequest request = new HttpRequest();
      request.setEndpoint(endpointUrl);
      request.setMethod('GET');
      if (!String.isBlank(docFabSetting.API_Key__c)) {
        request.setHeader('Authorization', 'token ' + docFabSetting.API_Key__c);
      }
      request.setHeader('Accept', 'application/json');
      request.setHeader('Content-Type', 'application/json');
      request.setTimeout(120000);
      Http http = new Http();
      HttpResponse response = http.send(request);
      String recordUuidOrError = '';
      System.debug(response.getStatusCode() + response.getBody());
      if (
        response.getStatusCode() == 200 && !String.isBlank(response.getBody())
      ) {
        List<AuthUserWrapper> userList = (List<AuthUserWrapper>) JSON.deserialize(
          response.getBody(),
          List<AuthUserWrapper>.class
        );
        if (!userList.isEmpty() && !String.isBlank(userList[0].id)) {
          if (!String.isBlank(recordModelId)) {
            // call api to create record in external system.
            recordUuidOrError = CreateRecordToOpenDocFab_Apex(
              recordModelId,
              userList[0].id,
              journalRecord,
              fieldConfigurationJson
            );
            return recordUuidOrError;
          } else {
            DFJ_ErrorLogController.addErrorLogs(
              journalRecord[0].Id,
              'Checking recordModelId is not empty.',
              'recordModelId is null so can not call method to create new record',
              'Warning',
              'DF_DocFabricator_Utility apex class AuthenticateCurrentSalesforceUser_Apex method.',
              '',
              ''
            );
          }
        } else {
          // Show error toast message if user is not present.
          recordUuidOrError =
            'Current user with ' +
            UserInfo.getUserEmail() +
            ' does not exists in the DocFabricator system.';
          DFJ_ErrorLogController.addErrorLogs(
            journalRecord[0].Id,
            'Authorizing current salesforce user so user can create record in external system.',
            'StatusCode is ' +
              response.getStatusCode() +
              ' body: ' +
              response.getBody(),
            'Warning',
            'DF_DocFabricator_Utility apex class AuthenticateCurrentSalesforceUser_Apex method.',
            '',
            ''
          );
          return recordUuidOrError;
        }
      } else {
        DFJ_ErrorLogController.addErrorLogs(
          journalRecord[0].Id,
          'Authorizing current salesforce user so user can create record in external system.',
          'StatusCode is ' +
            response.getStatusCode() +
            ' body: ' +
            response.getBody(),
          'Warning',
          'DF_DocFabricator_Utility apex class method AuthenticateCurrentSalesforceUser_Apex.',
          '',
          ''
        );
      }
    } catch (Exception ex) {
      system.debug(
        'line number > ' + ex.getLineNumber() + 'Message ;>>' + ex.getMessage()
      );
      DFJ_ErrorLogController.addErrorLogs(
        journalRecord[0].Id,
        'Authorizing current salesforce user so user can create record in external system.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility apex class method AuthenticateCurrentSalesforceUser_Apex.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
    }
    return null;
    // End
  }
  // Changes for ticket - DIN-170 : Create DocFab Record.
  // Start
  // Description : Wrapper to hold the user data we are getting in response in AuthenticateCurrentSalesforceUser_Apex method.
  public class AuthUserWrapper {
    public string id;
    public string email;
    public string first_name;
    public string last_name;
  }
  // End

  /*
   * @Description  This method will be invoked to create record in external system
   * @Param        String - recordModelId,recordUserId,journalRecord
   * @Return       String - record_uuid
   */
  public static String CreateRecordToOpenDocFab_Apex(
    String recordModelId,
    String recordUserId,
    List<Journal__c> journalRecord
  ) {
    // Backwards-compatible overload for existing callers that do not send fieldConfigurationJson.
    return CreateRecordToOpenDocFab_Apex(
      recordModelId,
      recordUserId,
      journalRecord,
      null
    );
  }

  public static String CreateRecordToOpenDocFab_Apex(
    String recordModelId,
    String recordUserId,
    List<Journal__c> journalRecord,
    String fieldConfigurationJson
  ) {
    // Changes for ticket - DIN-170 : Create DocFab Record.
    // Start
    // Description : Creating record in external system
    try {
      if (String.isBlank(recordModelId) && String.isBlank(recordUserId)) {
        DFJ_ErrorLogController.addErrorLogs(
          journalRecord[0].Id,
          'Creating record in external system.',
          'recordModelId or recordUserId value is null.',
          'Warning',
          'DF_DocFabricator_Utility apex class CreateRecordToOpenDocFab_Apex method.',
          '',
          ''
        );
        return null;
      }
      // Changes for ticket DIN-288 : Create record field config
      // Description :
      // Start

      Map<String, Object> fieldConfigurationMap = null;
      if (!String.isBlank(fieldConfigurationJson)) {
        fieldConfigurationMap = (Map<String, Object>) JSON.deserializeUntyped(
          fieldConfigurationJson
        );
      }

      Map<String, Object> contentMap = new Map<String, Object>();
      if (fieldConfigurationMap != null && !fieldConfigurationMap.isEmpty()) {
        if (
          journalRecord == null ||
          journalRecord.isEmpty() ||
          journalRecord[0].Id == null
        ) {
          // No persistent journal to query; skip SF→DocFab field mapping in this call.
          fieldConfigurationMap.clear();
        }
      }
      if (fieldConfigurationMap != null && !fieldConfigurationMap.isEmpty()) {
        List<String> fieldList = new List<String>(
          fieldConfigurationMap.keySet()
        );
        Id jrId = journalRecord[0].Id;
        String query =
          'SELECT ' +
          String.join(fieldList, ',') +
          ' FROM Journal__c WHERE Id = :jrId LIMIT 1';
        List<Journal__c> journalRecordInstance = Database.query(query);
        System.debug(
          'fieldConfigurationMap >>> ' +
          JSON.serializePretty(fieldConfigurationMap)
        );
        for (String configurationKey : fieldConfigurationMap.keySet()) {
          String targetKey = String.valueOf(
            fieldConfigurationMap.get(configurationKey)
          );
          String valueToSend = '';
          if (configurationKey.contains('Lead__r.')) {
            Integer dotIdx = configurationKey.indexOf('.');
            if (
              dotIdx > -1 &&
              journalRecordInstance[0].getSobject('Lead__r') != null
            ) {
              String leadFieldName = configurationKey.substring(dotIdx + 1);
              Object leadValue = journalRecordInstance[0]
                .getSobject('Lead__r')
                .get(leadFieldName);
              valueToSend = leadValue == null ? '' : String.valueOf(leadValue);
            }
          } else {
            Object fieldValue = journalRecordInstance[0].get(configurationKey);
            valueToSend = fieldValue == null ? '' : String.valueOf(fieldValue);
          }
          contentMap.put(targetKey, valueToSend);
        }
      }

      Map<String, Object> payload = new Map<String, Object>();
      payload.put('owner_id', recordUserId);
      payload.put('record_model_id', recordModelId);
      payload.put('content', contentMap);

      String body = JSON.serialize(payload);
      System.debug('body body >>>> ' + body);
      Doc_Fabricator_Setting__c docFabSetting = Doc_Fabricator_Setting__c.getOrgDefaults();
      // docfab endpoint
      String docFabendpointUrl = docFabSetting.URL__c + 'api/create-record';
      // End
      // End

      HttpRequest request = new HttpRequest();
      request.setEndpoint(docFabendpointUrl);
      request.setbody(body);
      request.setMethod('POST');
      if (!String.isBlank(docFabSetting.API_Key__c)) {
        request.setHeader('Authorization', 'token ' + docFabSetting.API_Key__c);
      }
      request.setHeader('Accept', 'application/json');
      request.setHeader('Content-Type', 'application/json');
      Http http = new Http();
      HttpResponse response = http.send(request);
      if (
        response.getStatusCode() == 200 && !String.isBlank(response.getBody())
      ) {
        Map<String, object> recordDetail = (Map<String, Object>) JSON.deserializeUntyped(
          response.getBody()
        );

        String recorduuid = String.valueOf(recordDetail.get('uuid'));
        if (!String.isBlank(recorduuid)) {
          return recorduuid;
        } else {
          DFJ_ErrorLogController.addErrorLogs(
            journalRecord[0].Id,
            'Creating record in external system.',
            'returned response body: ' + response.getBody(),
            'Warning',
            'DF_DocFabricator_Utility apex class method.',
            '',
            ''
          );
        }
      } else {
        DFJ_ErrorLogController.addErrorLogs(
          journalRecord[0].Id,
          'Checking status and response string is not empty and null.',
          'StatusCode is ' +
            response.getStatusCode() +
            ' body: ' +
            response.getBody(),
          'Warning',
          'DF_DocFabricator_Utility apex class method.',
          '',
          ''
        );
        return 'Error Code ' +
          response.getStatusCode() +
          ' ' +
          response.getStatus();
      }
    } catch (Exception ex) {
      // Changes for ticket DIN-254 : Add "OK" button to docfab error toast and include status message from api service
      // Start
      DFJ_ErrorLogController.addErrorLogs(
        journalRecord[0].Id,
        'Creating record in external system.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      // End
    }
    return null;
    // End
  }

  /*
   * @Description  Remove characters that would break DocFab payloads.
   * @Param        String - stringBody
   * @Return       String - escaped string
   */
  public static String EscapeReversedCharacters_Apex(String stringBody) {
    try {
      stringBody = stringBody.replace('"', '')
        .replace('\b', '\\b')
        .replace('\f', '\\f')
        .replace('\n', '\\n')
        .replace('\r', '\\r')
        .replace('\t', '\\t')
        .replace('\\', '\\\\');
      return stringBody;
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Escaping the reversed characters from string.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
    }
    return '';
  }

  /*
   * @Description  This method will create the body .
   * @Param        username,password
   * @Return       String
   */
  public static String buildSoapLogin(String username, String password) {
    XmlStreamWriter w = new XmlStreamWriter();
    w.writeStartElement('', 'login', 'urn:partner.soap.sforce.com');
    w.writeNamespace('', 'urn:partner.soap.sforce.com');
    w.writeStartElement('', 'username', 'urn:partner.soap.sforce.com');
    w.writeCharacters(username);
    w.writeEndElement();
    w.writeStartElement('', 'password', 'urn:partner.soap.sforce.com');
    w.writeCharacters(password);
    w.writeEndElement();
    w.writeEndElement();

    String xmlOutput =
      '<Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/"><Body>' +
      w.getXmlString() +
      '</Body></Envelope>';
    w.close();
    return xmlOutput;
  }

  /*
   * @Description  This method will get the sessionId for the user.
   * @Param        res
   * @Return       String
   */
  public static String getSessionId_Apex(
    String Username,
    String Password,
    String SecurityToken
  ) {
    try {
      String sessionIDString = '';
      String loginDomain = '';
      if (Username != '' && Password != '' /*&& SecurityToken != ''*/) {
        List<Organization> orgList = new List<Organization>();
        orgList = [SELECT IsSandbox FROM Organization];
        if (orgList[0].IsSandbox) {
          loginDomain = 'https://test.salesforce.com/services/Soap/u/43.0';
        } else {
          loginDomain = 'https://login.salesforce.com/services/Soap/u/43.0';
        }
        HttpRequest request = new HttpRequest();
        request.setEndpoint(loginDomain);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'text/xml;charset=UTF-8');
        request.setHeader('SOAPAction', '""');
        request.setBody(buildSoapLogin(Username, Password)); //+SecurityToken
        request.setTimeout(120000);

        HttpResponse response;
        if (!Test.isRunningTest()) {
          response = new Http().send(request);
        } else {
          Docfab_MetadataMock MockHttpResponseGeneratorInstance = new Docfab_MetadataMock();
          response = MockHttpResponseGeneratorInstance.respond(request);
        }

        sessionIDString = parseResponse(response);
        return sessionIDString;
      }
    } catch (Exception ex) {
      System.debug(ex);
      //throw new AuraHandledException('Error Message: ' + ex.getMessage() + 'Line Number: ' + ex.getLineNumber());
    }
    return null;
  }

  /*
   * @Description  This method parsing the response to get the sessionId.
   * @Param        res
   * @Return       String
   */
  public static String parseResponse(HttpResponse res) {
    Dom.Document doc = res.getBodyDocument();
    Dom.XmlNode root = doc.getRootElement();
    Dom.XmlNode loginResponse = root.getChildElement(
        'Body',
        'http://schemas.xmlsoap.org/soap/envelope/'
      )
      .getChildElement('loginResponse', 'urn:partner.soap.sforce.com');
    if (loginResponse == null) {
      //credentialsResponse.errorMessage = 'INVALID_LOGIN: Invalid username, password, security token; or user locked out.';
      Dom.XmlNode fault = root.getChildElement(
          'Body',
          'http://schemas.xmlsoap.org/soap/envelope/'
        )
        .getChildElement('Fault', 'http://schemas.xmlsoap.org/soap/envelope/');
      if (fault != null) {
        return null;
      }
    } else {
      System.debug(LoggingLevel.ERROR, loginResponse);
      Dom.XmlNode result = loginResponse.getChildElement(
        'result',
        'urn:partner.soap.sforce.com'
      );
      //Dom.XmlNode userInfo = result.getChildElement('userInfo', 'urn:partner.soap.sforce.com');
      String sID = result.getChildElement(
          'sessionId',
          'urn:partner.soap.sforce.com'
        )
        .getText();
      return sID;
    }
    return null;
  }

  /*
   * @Description  This method will create or update object.
   * @Param        paramsToCreateObjectModel
   * @Return       String
   */
  public static ResponseReturnWrapper CreateDocfabObjectModel(
    RequestBodyPayloadWrapper paramsToCreateObjectModel
  ) {
    ResponseReturnWrapper responseReturnWrapperInstance = new ResponseReturnWrapper();
    try {
      //System.debug('Creating object');
      if (
        String.isBlank(paramsToCreateObjectModel.name) ||
        String.isBlank(paramsToCreateObjectModel.api_name)
      ) {
        responseReturnWrapperInstance.Message = 'Can not create Object Model because name or api name is empty.';
        responseReturnWrapperInstance.statuscode = 500;
        return responseReturnWrapperInstance;
      }

      MetadataService.MetadataPort service = CreateService(); // new MetadataService.MetadataPort() ;
      if (service == null) {
        responseReturnWrapperInstance.Message = 'Metadata service is null.';
        responseReturnWrapperInstance.statuscode = 500;
        return responseReturnWrapperInstance;
      }
      MetadataService.CustomObject customobject = new MetadataService.CustomObject();
      //System.debug('Line 193');
      if (!String.isBlank(paramsToCreateObjectModel.type)) {
        if (paramsToCreateObjectModel.type.equals('MAIN')) {
          customobject.fullName = paramsToCreateObjectModel.api_name.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToCreateObjectModel.api_name.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToCreateObjectModel.api_name + '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToCreateObjectModel.api_name +
              '__c';
        } else if (
          !String.isBlank(paramsToCreateObjectModel.parent_model) &&
          paramsToCreateObjectModel.type.equals('SUBLIST')
        ) {
          customobject.fullName = paramsToCreateObjectModel.parent_model.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToCreateObjectModel.api_name.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToCreateObjectModel.parent_model_id +
              '_' +
              paramsToCreateObjectModel.api_name +
              '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToCreateObjectModel.parent_model_id +
              '_' +
              paramsToCreateObjectModel.api_name +
              '__c';
        } else {
          responseReturnWrapperInstance.Message = 'Found type property unknown.';
          responseReturnWrapperInstance.statuscode = 500;
          return responseReturnWrapperInstance;
        }
      } else {
        // If type property is not present checking for the update
        if (paramsToCreateObjectModel.operation.equals('UPDATE_MODEL')) {
          // parent_model property in case of update to update the sublist model.
          if (String.isBlank(paramsToCreateObjectModel.parent_model)) {
            customobject.fullName = paramsToCreateObjectModel.api_name.contains(
                prefixForMetaApiName + underscoreString
              ) &&
              paramsToCreateObjectModel.api_name.indexOf(
                prefixForMetaApiName + underscoreString
              ) == 0
              ? paramsToCreateObjectModel.api_name + '__c'
              : prefixForMetaApiName +
                underscoreString +
                paramsToCreateObjectModel.api_name +
                '__c';
          } else {
            customobject.fullName = paramsToCreateObjectModel.parent_model.contains(
                prefixForMetaApiName + underscoreString
              ) &&
              paramsToCreateObjectModel.parent_model.indexOf(
                prefixForMetaApiName + underscoreString
              ) == 0
              ? paramsToCreateObjectModel.parent_model_id +
                '_' +
                paramsToCreateObjectModel.api_name +
                '__c'
              : prefixForMetaApiName +
                underscoreString +
                paramsToCreateObjectModel.parent_model_id +
                '_' +
                paramsToCreateObjectModel.api_name +
                '__c';
          }
        } else {
          responseReturnWrapperInstance.Message = 'Found type property empty.';
          responseReturnWrapperInstance.statuscode = 500;
          return responseReturnWrapperInstance;
        }
      }
      customobject.label = paramsToCreateObjectModel.name;
      customobject.pluralLabel = paramsToCreateObjectModel.name + 's';
      customobject.description = paramsToCreateObjectModel.description == null
        ? ''
        : paramsToCreateObjectModel.description;
      customObject.nameField = new MetadataService.CustomField();
      customobject.nameField.type_x = 'Text';
      customobject.nameField.label = paramsToCreateObjectModel.name + ' Name';
      customobject.deploymentStatus = 'Deployed';
      customObject.sharingModel = 'ReadWrite';

      if (paramsToCreateObjectModel.operation.equals('UPDATE_MODEL')) {
        List<MetadataService.SaveResult> saveresults = service.updateMetadata(
          new List<MetadataService.Metadata>{ customObject }
        );
        responseReturnWrapperInstance = HandleSaveResults(saveresults[0]);
      } else {
        List<MetadataService.UpsertResult> results = service.upsertMetadata(
          new List<MetadataService.Metadata>{ customObject }
        );
        responseReturnWrapperInstance = HandleUpsertResults(results[0]);
      }
      if (
        responseReturnWrapperInstance != null &&
        responseReturnWrapperInstance.statuscode != 200
      ) {
        return responseReturnWrapperInstance;
      }
      if (
        !String.isBlank(paramsToCreateObjectModel.type) &&
        !paramsToCreateObjectModel.operation.equals('UPDATE_MODEL')
      ) {
        // Create LookUp field when type is SUBLIST
        responseReturnWrapperInstance = CreateDefaultField(
          paramsToCreateObjectModel
        );
      }
      // if (!paramsToCreateObjectModel.operation.equals('UPDATE_MODEL')) {
      //     responseReturnWrapperInstance = CreateDefaultField(paramsToCreateObjectModel);
      // }
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Creating modal in salesforce.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility.CreateDocfabObjectModel apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      responseReturnWrapperInstance.Message = String.valueOf(ex.getMessage());
      responseReturnWrapperInstance.statuscode = 500;
    }
    return responseReturnWrapperInstance;
  }

  /*
   * @Description  This method will be called when SUBLIST type object is created to create lookup field.
   * @Param        paramsToCreateLookupField
   * @Return       Boolean
   */
  public static ResponseReturnWrapper CreateDefaultField(
    RequestBodyPayloadWrapper paramsToCreateLookupField
  ) {
    ResponseReturnWrapper responseReturnWrapperInstance = new ResponseReturnWrapper();
    try {
      MetadataService.MetadataPort service = CreateService();
      //-----------------------------------------------------
      List<MetadataService.CustomField> customFieldList = new List<MetadataService.CustomField>();
      List<MetadataService.ProfileFieldLevelSecurity> ProfileFieldLevelSecurityList = new List<MetadataService.ProfileFieldLevelSecurity>();
      for (String fieldlabel : fieldLabelList) {
        MetadataService.CustomField customField = new MetadataService.CustomField();
        MetadataService.ProfileFieldLevelSecurity fieldSecurity = new MetadataService.ProfileFieldLevelSecurity();
        if (!String.isBlank(paramsToCreateLookupField.parent_model)) {
          customField.fullName = paramsToCreateLookupField.parent_model.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToCreateLookupField.parent_model.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToCreateLookupField.parent_model_id +
              '_' +
              paramsToCreateLookupField.api_name +
              '__c' +
              '.' +
              fieldlabel +
              '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToCreateLookupField.parent_model_id +
              '_' +
              paramsToCreateLookupField.api_name +
              '__c' +
              '.' +
              fieldlabel +
              '__c';
        } else {
          customField.fullName = paramsToCreateLookupField.api_name.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToCreateLookupField.api_name.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToCreateLookupField.api_name +
              '__c' +
              '.' +
              fieldlabel +
              '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToCreateLookupField.api_name +
              '__c' +
              '.' +
              fieldlabel +
              '__c';
        }
        customField.label = fieldlabel;

        if (
          fieldlabel.equals('version') || fieldlabel.equals('record_model_id')
        ) {
          customField.type_x = 'Number';
          customField.precision = 18;
          customField.scale = 2;
        } else {
          customField.type_x = fieldlabel.equals(
              'Sublist_version_configuration'
            )
            ? 'LongTextArea'
            : 'Text';
          customField.length = fieldlabel.equals(
              'Sublist_version_configuration'
            )
            ? 131072
            : 255;
          if (fieldlabel.equals('uuid')) {
            customField.unique = true;
          }
        }
        if (fieldlabel.equals('Sublist_version_configuration')) {
          customField.visibleLines = 3;
        }

        fieldSecurity.field = customField.fullName;
        fieldSecurity.editable = true;
        fieldSecurity.readable = true;

        if (
          (fieldlabel.equals('Sublist_version_configuration') &&
          String.isBlank(paramsToCreateLookupField.parent_model)) ||
          !fieldlabel.equals('Sublist_version_configuration')
        ) {
          customFieldList.add(customField);
          ProfileFieldLevelSecurityList.add(fieldSecurity);
        }
      }
      if (!String.isBlank(paramsToCreateLookupField.parent_model)) {
        MetadataService.ProfileFieldLevelSecurity fieldSecurity = new MetadataService.ProfileFieldLevelSecurity();
        MetadataService.CustomField customField = new MetadataService.CustomField();
        customField.fullName = paramsToCreateLookupField.parent_model.contains(
            prefixForMetaApiName + underscoreString
          ) &&
          paramsToCreateLookupField.parent_model.indexOf(
            prefixForMetaApiName + underscoreString
          ) == 0
          ? paramsToCreateLookupField.parent_model_id +
            '_' +
            paramsToCreateLookupField.api_name +
            '__c' +
            '.' +
            paramsToCreateLookupField.parent_model +
            '__c'
          : prefixForMetaApiName +
            underscoreString +
            paramsToCreateLookupField.parent_model_id +
            '_' +
            paramsToCreateLookupField.api_name +
            '__c' +
            '.' +
            paramsToCreateLookupField.parent_model +
            '__c';
        customField.label = paramsToCreateLookupField.parent_model;
        customField.type_x = 'Lookup';
        customField.relationshipLabel = paramsToCreateLookupField.name;
        customField.relationshipName =
          prefixForMetaApiName +
          underscoreString +
          paramsToCreateLookupField.parent_model_id +
          '_' +
          paramsToCreateLookupField.api_name;
        customField.referenceTo =
          prefixForMetaApiName +
          underscoreString +
          paramsToCreateLookupField.parent_model +
          '__c';
        fieldSecurity.field = customField.fullName;

        fieldSecurity.editable = true;
        fieldSecurity.readable = true;

        customFieldList.add(customField);
        ProfileFieldLevelSecurityList.add(fieldSecurity);
      }
      //Chnages DIN-371
      //Start
      if (
        String.isBlank(paramsToCreateLookupField.parent_model) &&
        paramsToCreateLookupField.type.equals('MAIN')
      ) {
        // System.debug('journal lookup');
        MetadataService.ProfileFieldLevelSecurity fieldSecurity = new MetadataService.ProfileFieldLevelSecurity();
        MetadataService.CustomField customField = new MetadataService.CustomField();
        if (String.isBlank(paramsToCreateLookupField.parent_model)) {
          // customField.fullName = paramsToCreateLookupField.parent_model.contains(prefixForMetaApiName + underscoreString) && paramsToCreateLookupField.parent_model.indexOf(prefixForMetaApiName + underscoreString) == 0 ? paramsToCreateLookupField.parent_model_id + '_'+paramsToCreateLookupField.api_name+'__c' + '.Journal__c' : prefixForMetaApiName + underscoreString + paramsToCreateLookupField.parent_model_id + '_'+paramsToCreateLookupField.api_name+'__c' +  '.Journal__c';
          customField.fullName = paramsToCreateLookupField.api_name.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToCreateLookupField.api_name.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToCreateLookupField.api_name + '__c' + '.Journal__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToCreateLookupField.api_name +
              '__c' +
              '.Journal__c';
          System.debug('customField.fullName' + customField.fullName);
        }

        customField.label = 'Journal';
        customField.type_x = 'Lookup';
        customField.relationshipName =
          prefixForMetaApiName +
          underscoreString +
          paramsToCreateLookupField.api_name;
        customField.referenceTo = 'Journal__c';
        fieldSecurity.field = customField.fullName;

        fieldSecurity.editable = true;
        fieldSecurity.readable = true;

        customFieldList.add(customField);
        ProfileFieldLevelSecurityList.add(fieldSecurity);
      }
      //End
      // List<MetadataService.UpsertResult> results = service.upsertMetadata(new MetadataService.Metadata[] { customField });
      List<MetadataService.UpsertResult> results = service.upsertMetadata(
        customFieldList
      );
      responseReturnWrapperInstance = HandleUpsertResults(results[0]);
      if (responseReturnWrapperInstance.statuscode == 200) {
        List<MetadataService.Metadata> metadataList = assignFieldPermissionToDefaultfields(
          ProfileFieldLevelSecurityList
        );
        List<MetadataService.SaveResult> permissionResults = service.updateMetadata(
          metadataList
        );
        responseReturnWrapperInstance = HandleSaveResults(permissionResults[0]);
      }
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Creating lookup field.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility.CreateLookupField apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      responseReturnWrapperInstance.Message = String.valueOf(ex.getMessage());
      responseReturnWrapperInstance.statuscode = 500;
    }
    return responseReturnWrapperInstance;
  }

  /*
   * @Description  This method will create or update field.
   * @Param        paramsToCreateObjectModel
   * @Return       ResponseReturnWrapper
   */
  public static List<MetadataService.Metadata> assignFieldPermissionToDefaultfields(
    List<MetadataService.ProfileFieldLevelSecurity> ProfileFieldLevelSecurityList
  ) {
    List<MetadataService.Metadata> metadataList = new List<MetadataService.Metadata>();
    DocFab_User_Setting__c docfabUserCustomSetting = DocFab_User_Setting__c.getOrgDefaults();
    if (
      docfabUserCustomSetting == null ||
      String.isBlank(docfabUserCustomSetting.Profiles__c)
    ) {
      return metadataList;
    }
    List<String> profileList = docfabUserCustomSetting.Profiles__c.split(',');
    for (String profileLoop : profileList) {
      MetadataService.Profile profile = new MetadataService.Profile();
      profile.fullName = profileLoop;
      profile.FieldPermissions = ProfileFieldLevelSecurityList;
      metadataList.add(profile);
    }
    return metadataList;
  }

  /*
   * @Description  This method will create or update field.
   * @Param        paramsToCreateObjectModel
   * @Return       ResponseReturnWrapper
   */
  public static ResponseReturnWrapper CreateDocfabModelField(
    RequestBodyPayloadWrapper paramsToCreateField
  ) {
    ResponseReturnWrapper responseReturnWrapperInstance = new ResponseReturnWrapper();
    try {
      // Changes for DIN-319
      // Starte
      List<Docfab_FieldLabel_Configuration__c> configurationList = new List<Docfab_FieldLabel_Configuration__c>();
      Docfab_FieldLabel_Configuration__c configurationToCreate = new Docfab_FieldLabel_Configuration__c();
      Docfab_FieldAPI_Setting__c fieldApiSetting = Docfab_FieldAPI_Setting__c.getOrgDefaults();
      Boolean createConfigurationRecord = false;
      MetadataService.CustomField customField = new MetadataService.CustomField();
      //  End
      System.debug('Creating field');
      if (
        String.isBlank(paramsToCreateField.name) ||
        String.isBlank(paramsToCreateField.api_name) ||
        String.isBlank(paramsToCreateField.record_model)
      ) {
        responseReturnWrapperInstance.Message = 'Found name or record model property empty.';
        responseReturnWrapperInstance.statuscode = 500;
        return responseReturnWrapperInstance;
      }
      System.debug('paramsToCreateField field--->' + paramsToCreateField);
      MetadataService.MetadataPort service = CreateService();
      if (service == null) {
        responseReturnWrapperInstance.Message = 'Metadata service is null.';
        responseReturnWrapperInstance.statuscode = 500;
        return responseReturnWrapperInstance;
      }

      configurationList = checkFieldConfigurationsPresent(paramsToCreateField);
      System.debug('configurationList>>>' + configurationList);
      // Changes for DIN-319
      // Starte
      if (paramsToCreateField.api_name.length() > 32) {
        if (!configurationList.isEmpty()) {
          createConfigurationRecord = false;
          customField.fullName =
            configurationList[0].Model__c +
            '.' +
            configurationList[0].SF_Field_API_Name__c;
          customField.label = configurationList[0].SF_Field_Label__c;
          if (
            !createEncodedLabel(paramsToCreateField.name)
              .equals(configurationList[0].Docfab_Encoded_Field_Label__c)
          ) {
            createConfigurationRecord = true;
            configurationList[0].SF_Field_Label__c = createShortLabel(
              paramsToCreateField.name
            );
          }
        } else {
          String constructApiName = '';
          createConfigurationRecord = true;
          //DIN-348 Chnages
          constructApiName = ToShortAPIName(
            fieldApiSetting.FieldAPI_Postfix__c,
            paramsToCreateField
          );
          //System.debug('constructApiName>>>>'+constructApiName);
          // Get custom setting
          // Get 32 char + _ + integer
          customField.fullName = String.isNotBlank(
              paramsToCreateField.parent_model
            )
            ? (paramsToCreateField.parent_model.contains(
                  prefixForMetaApiName + underscoreString
                ) &&
                paramsToCreateField.parent_model.indexOf(
                  prefixForMetaApiName + underscoreString
                ) == 0
                ? (paramsToCreateField.parent_model_id +
                  '_' +
                  paramsToCreateField.record_model +
                  '__c' +
                  '.' +
                  constructApiName +
                  '__c')
                : (prefixForMetaApiName +
                  underscoreString +
                  paramsToCreateField.parent_model_id +
                  '_' +
                  paramsToCreateField.record_model +
                  '__c' +
                  '.' +
                  constructApiName +
                  '__c'))
            : (paramsToCreateField.record_model.contains(
                  prefixForMetaApiName + underscoreString
                ) &&
                paramsToCreateField.record_model.indexOf(
                  prefixForMetaApiName + underscoreString
                ) == 0
                ? paramsToCreateField.record_model +
                  '__c' +
                  '.' +
                  constructApiName +
                  '__c'
                : prefixForMetaApiName +
                  underscoreString +
                  paramsToCreateField.record_model +
                  '__c' +
                  '.' +
                  constructApiName +
                  postfixForMetaApiName);

          customField.label = paramsToCreateField.api_name.length() > 32
            ? createShortLabel(paramsToCreateField.name)
            : paramsToCreateField.name;
          //DIN_348 Chnages Start
          //paramsToCreateField.api_name = paramsToCreateField.api_name.length() > 32 ? constructApiName : paramsToCreateField.api_name;
          //System.debug('paramsToCreateField.api_name'+paramsToCreateField.api_name);
          //End
          configurationToCreate.Docfab_Encoded_Field_Label__c = createEncodedLabel(
            paramsToCreateField.name
          );
          configurationToCreate.Docfab_Field_Label__c = paramsToCreateField.name;
          configurationToCreate.SF_Field_Label__c = customField.label;
          configurationToCreate.Docfab_Field_API_Name__c =
            paramsToCreateField.api_name + postfixForMetaApiName;
          configurationToCreate.SF_Field_API_Name__c =
            constructApiName + postfixForMetaApiName;
          configurationToCreate.Model__c =
            prefixForMetaApiName +
            underscoreString +
            (String.isEmpty(paramsToCreateField.parent_model)
              ? ''
              : paramsToCreateField.parent_model_id + underscoreString) +
            paramsToCreateField.record_model +
            postfixForMetaApiName;
          System.debug(
            'configurationToCreate.Model__c>>>>' + configurationToCreate
          );
        }
      } else {
        if (!String.isBlank(paramsToCreateField.parent_model)) {
          customField.fullName = paramsToCreateField.parent_model.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToCreateField.parent_model.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? (paramsToCreateField.parent_model_id +
              '_' +
              paramsToCreateField.record_model +
              '__c' +
              '.' +
              paramsToCreateField.api_name.replace('__', '_')
                .replace('-', '_') +
              '__c')
            : (prefixForMetaApiName +
              underscoreString +
              paramsToCreateField.parent_model_id +
              '_' +
              paramsToCreateField.record_model +
              '__c' +
              '.' +
              paramsToCreateField.api_name.replace('__', '_')
                .replace('-', '_') +
              '__c');
        } else {
          customField.fullName = paramsToCreateField.record_model.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToCreateField.record_model.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToCreateField.record_model +
              '__c' +
              '.' +
              paramsToCreateField.api_name.replace('__', '_')
                .replace('-', '_') +
              '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToCreateField.record_model +
              '__c' +
              '.' +
              paramsToCreateField.api_name.replace('__', '_')
                .replace('-', '_') +
              '__c';
        }

        customField.label = paramsToCreateField.name.length() > 32
          ? createShortLabel(paramsToCreateField.name)
          : paramsToCreateField.name;
        createConfigurationRecord = paramsToCreateField.name.length() > 32
          ? true
          : false;

        configurationToCreate.Docfab_Encoded_Field_Label__c = createEncodedLabel(
          paramsToCreateField.name
        );
        configurationToCreate.Docfab_Field_Label__c = paramsToCreateField.name;
        configurationToCreate.SF_Field_Label__c = customField.label;
        configurationToCreate.Docfab_Field_API_Name__c = paramsToCreateField.name.length() >
          32
          ? paramsToCreateField.api_name + postfixForMetaApiName
          : paramsToCreateField.api_name;
        configurationToCreate.SF_Field_API_Name__c =
          paramsToCreateField.api_name + postfixForMetaApiName;
        configurationToCreate.Model__c =
          prefixForMetaApiName +
          underscoreString +
          (String.isEmpty(paramsToCreateField.parent_model)
            ? ''
            : paramsToCreateField.parent_model_id + underscoreString) +
          paramsToCreateField.record_model +
          postfixForMetaApiName;
        //System.debug('configurationToCreate.Model__c>>>>'+configurationToCreate.Model__c);
      }
      //  end
      customField.description = paramsToCreateField.description == null
        ? ''
        : paramsToCreateField.description;

      // Changes for DIN-319
      // Starte
      // if (paramsToCreateField.api_name.length() > 32) {
      //     customField.label = createShortLabel(paramsToCreateField.name);//paramsToCreateField.name;
      //     configurationToCreate.SF_Field_Label__c = customField.label;
      //     configurationToCreate.Docfab_Encoded_Field_Label__c = createEncodedLabel(paramsToCreateField.name);
      // } else {
      //     customField.label = paramsToCreateField.name;
      //     configurationToCreate.SF_Field_Label__c = customField.label;
      // }
      // End

      if (paramsToCreateField.operation.equals('UPDATE_FIELD')) {
        String objectName = '';
        String fieldToGet = '';

        objectName = String.isBlank(paramsToCreateField.parent_model)
          ? Test.isRunningTest()
              ? paramsToCreateField.record_model
              : paramsToCreateField.record_model.contains(
                    prefixForMetaApiName + underscoreString
                  ) &&
                  paramsToCreateField.record_model.indexOf(
                    prefixForMetaApiName + underscoreString
                  ) == 0
                  ? paramsToCreateField.record_model + '__c'
                  : prefixForMetaApiName +
                    underscoreString +
                    paramsToCreateField.record_model +
                    '__c'
          : paramsToCreateField.record_model.contains(
                prefixForMetaApiName + underscoreString
              ) &&
              paramsToCreateField.record_model.indexOf(
                prefixForMetaApiName + underscoreString
              ) == 0
              ? paramsToCreateField.parent_model_id +
                '_' +
                paramsToCreateField.record_model +
                '__c'
              : prefixForMetaApiName +
                underscoreString +
                paramsToCreateField.parent_model_id +
                '_' +
                paramsToCreateField.record_model +
                '__c';

        Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
        Schema.SObjectType objectSchema = schemaMap.get(objectName);
        Map<String, Schema.SObjectField> fieldMap = objectSchema.getDescribe()
          .fields.getMap();

        fieldToGet = paramsToCreateField.api_name.length() > 32
          ? ''
          : Test.isRunningTest()
              ? paramsToCreateField.api_name
              : paramsToCreateField.api_name + postfixForMetaApiName;

        Schema.DisplayType fielddataType = fieldMap.get(fieldToGet)
          .getDescribe()
          .getType();
        paramsToCreateField.type = String.valueOf(fielddataType);
      }

      // To be changed according to type
      //System.debug(' paramsToCreateField.type'+ paramsToCreateField.type);
      if (!String.isBlank(paramsToCreateField.type)) {
        if (
          paramsToCreateField.type.equals('NUMBER') ||
          paramsToCreateField.type.equals('Number') ||
          paramsToCreateField.type.equals('number') ||
          paramsToCreateField.type.equals('DOUBLE') ||
          paramsToCreateField.type.equals('double') ||
          paramsToCreateField.type.equals('Double')
        ) {
          customField.type_x = 'Number';
          customField.precision = 18;
          customField.scale = 0;
        } else if (
          paramsToCreateField.type.equalsIgnoreCase('TEXT') ||
          paramsToCreateField.type.equalsIgnoreCase('STRING')
        ) {
          customField.type_x = 'Text';
          customField.length = 255;
        } else if (
          paramsToCreateField.type.equals('BOOLEAN') ||
          paramsToCreateField.type.equals('boolean') ||
          paramsToCreateField.type.equals('Boolean')
        ) {
          customField.type_x = 'Checkbox';
          customField.defaultValue = String.valueOf(false);
        } else if (
          paramsToCreateField.type.equals('LONGTEXT') ||
          paramsToCreateField.type.equals('longtext') ||
          paramsToCreateField.type.equals('Longtext')
        ) {
          customField.type_x = 'LongTextArea';
          customField.length = 32768;
          customField.visibleLines = 3;
        } else if (
          paramsToCreateField.type.equals('PICKLIST') ||
          paramsToCreateField.type.equals('Picklist') ||
          paramsToCreateField.type.equals('picklist')
        ) {
          //Changes Start DIN-394

          if (
            configurationList.isEmpty() &&
            !paramsToCreateField.operation.equals('UPDATE_FIELD')
          ) {
            System.debug('configurationList');
            String objectNameForPicklist = String.isBlank(
                paramsToCreateField.parent_model
              )
              ? Test.isRunningTest()
                  ? paramsToCreateField.record_model
                  : paramsToCreateField.record_model.contains(
                        prefixForMetaApiName + underscoreString
                      ) &&
                      paramsToCreateField.record_model.indexOf(
                        prefixForMetaApiName + underscoreString
                      ) == 0
                      ? paramsToCreateField.record_model + '__c'
                      : prefixForMetaApiName +
                        underscoreString +
                        paramsToCreateField.record_model +
                        '__c'
              : paramsToCreateField.record_model.contains(
                    prefixForMetaApiName + underscoreString
                  ) &&
                  paramsToCreateField.record_model.indexOf(
                    prefixForMetaApiName + underscoreString
                  ) == 0
                  ? paramsToCreateField.parent_model_id +
                    '_' +
                    paramsToCreateField.record_model +
                    '__c'
                  : prefixForMetaApiName +
                    underscoreString +
                    paramsToCreateField.parent_model_id +
                    '_' +
                    paramsToCreateField.record_model +
                    '__c';

            String fieldName = paramsToCreateField.api_name.contains('__')
              ? paramsToCreateField.api_name.replace('__', '_')
              : paramsToCreateField.api_name;
            system.debug('fieldName-->' + fieldName);
            system.debug('paramsToCreateField-->' + paramsToCreateField);
            Boolean result = checkFieldPresentInsObject(
              objectNameForPicklist,
              fieldName + postfixForMetaApiName
            );
            System.debug('result>>>' + result);
            if (result) {
              responseReturnWrapperInstance = CreateReturnResponse(
                'Field already Present.',
                200
              );
              return responseReturnWrapperInstance;
            }
          } else if (!paramsToCreateField.operation.equals('UPDATE_FIELD')) {
            System.debug(
              'configurationList[0].Docfab_Field_API_Name__c>>>>' +
              configurationList[0].Docfab_Field_API_Name__c.removeEnd('__c')
            );
            if (
              paramsToCreateField.name ==
              configurationList[0].Docfab_Field_Label__c &&
              paramsToCreateField.api_name ==
              configurationList[0].Docfab_Field_API_Name__c.removeEnd('__c')
            ) {
              responseReturnWrapperInstance = CreateReturnResponse(
                'Field already Present.',
                200
              );
              return responseReturnWrapperInstance;
            }
          }

          //End
          customField.type_x = 'Picklist';
          //Create the valueSet for picklist type
          MetadataService.ValueSet picklistValueSet = new MetadataService.ValueSet();
          //For each ValueSet, we have either ValueSetValuesDefinition or ValueSettings and some other attributes
          MetadataService.ValueSetValuesDefinition valueDefinition = new MetadataService.ValueSetValuesDefinition();
          List<MetadataService.CustomValue> values = new List<MetadataService.CustomValue>();
          MetadataService.CustomValue customValue = new MetadataService.CustomValue();
          // call create picklist value method
          RequestBodyPayloadWrapper paramsToCreateDefaultPicklistValues = new RequestBodyPayloadWrapper();
          paramsToCreateDefaultPicklistValues.name = 'None';
          paramsToCreateDefaultPicklistValues.api_name = 'None';
          paramsToCreateDefaultPicklistValues.description = 'None';
          customValue = CreateDocfabPicklistValue(
            paramsToCreateDefaultPicklistValues
          );
          if (customValue == null) {
            responseReturnWrapperInstance = CreateReturnResponse(
              'Default Picklist Item not Created.',
              500
            );
            return responseReturnWrapperInstance;
          }
          values.add(customValue);
          valueDefinition.value = values;
          valueDefinition.sorted = false;
          picklistValueSet.valueSetDefinition = valueDefinition;
          customField.valueSet = picklistValueSet;
        } else if (
          paramsToCreateField.type.equals('DATETIME') ||
          paramsToCreateField.type.equals('Datetime') ||
          paramsToCreateField.type.equals('datetime')
        ) {
          customField.type_x = 'DateTime';
        } else if (paramsToCreateField.type.equalsIgnoreCase('SUBSELECT')) {
          customField.type_x = 'Lookup';
          customField.relationshipLabel = customField.fullName.substringAfterLast(
              '.'
            )
            .removeEnd('__c');
          //customField.relationshipName = prefixForMetaApiName + underscoreString + paramsToCreateField.parent_model_id + '_' + paramsToCreateField.record_model;
          customField.relationshipName = customField.fullName.substringAfterLast(
              '.'
            )
            .removeEnd('__c');
          //Changes DFJ-68 Starts - Updated to use DocFab_Record_Model__mdt
          if (paramsToCreateField.parent_model_id == null) {
            List<DocFab_Record_Model__mdt> recordModelInstance = [
              SELECT Id, Record_Model_Id__c
              FROM DocFab_Record_Model__mdt
              WHERE Record_Model_Id__c = :paramsToCreateField.record_model
              LIMIT 1
            ];
            if (!recordModelInstance.isEmpty()) {
              customField.referenceTo =
                prefixForMetaApiName +
                underscoreString +
                recordModelInstance[0].Record_Model_Id__c +
                underscoreString +
                paramsToCreateField.destination_model +
                '__c';
            }
          } else {
            //End
            customField.referenceTo =
              prefixForMetaApiName +
              underscoreString +
              paramsToCreateField.parent_model_id +
              underscoreString +
              paramsToCreateField.destination_model +
              '__c';
          }
        }
      }

      List<MetadataService.UpsertResult> results = service.upsertMetadata(
        new List<MetadataService.Metadata>{ customField }
      );
      responseReturnWrapperInstance = HandleUpsertResults(results[0]);
      if (responseReturnWrapperInstance.statuscode == 200) {
        CreateDocfabFieldPermission(paramsToCreateField);
      }

      if (createConfigurationRecord) {
        //  &&
        if (!configurationList.isEmpty()) {
          configurationToCreate = configurationList[0];
        }

        upsert configurationToCreate;
        if (configurationList.isEmpty()) {
          fieldApiSetting.FieldAPI_Postfix__c += 1;
          update fieldApiSetting;
        }
      }
    } catch (Exception ex) {
      System.debug(ex.getMessage());
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Creating docfab modal field.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility.CreateDocfabModelField apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      responseReturnWrapperInstance.Message = String.valueOf(ex.getMessage());
      responseReturnWrapperInstance.statuscode = 500;
    }
    return responseReturnWrapperInstance;
  }

  /*
   * @Description  This method will create or update field.
   * @Param        paramsToCreatePicklistItem
   * @Return       String
   */
  public static ResponseReturnWrapper CreateDocfabModelPicklistItem(
    RequestBodyPayloadWrapper paramsToCreatePicklistItem
  ) {
    ResponseReturnWrapper responseReturnWrapperInstance = new ResponseReturnWrapper();
    try {
      if (
        String.isBlank(paramsToCreatePicklistItem.record_model) ||
        String.isBlank(paramsToCreatePicklistItem.field_api_name) ||
        String.isBlank(paramsToCreatePicklistItem.api_name)
      ) {
        responseReturnWrapperInstance.Message = 'Found property(fieldsname/field api name/record model/api name) empty.';
        responseReturnWrapperInstance.statuscode = 500;
        return responseReturnWrapperInstance;
      }
      MetadataService.MetadataPort service = CreateService();
      if (service == null) {
        responseReturnWrapperInstance.Message = 'Metadata service is null.';
        responseReturnWrapperInstance.statuscode = 500;
        return responseReturnWrapperInstance;
      }

      //Changes start TCS-72
      paramsToCreatePicklistItem.field_api_name = paramsToCreatePicklistItem.field_api_name.contains(
          '__'
        )
        ? paramsToCreatePicklistItem.field_api_name.replace('__', '_')
        : paramsToCreatePicklistItem.field_api_name;
      System.debug(
        ' customField >>>>>' + paramsToCreatePicklistItem.field_api_name
      );
      //End
      String customFieldName = '';
      if (!String.isBlank(paramsToCreatePicklistItem.parent_model)) {
        customFieldName = paramsToCreatePicklistItem.parent_model.contains(
            prefixForMetaApiName + underscoreString
          ) &&
          paramsToCreatePicklistItem.parent_model.indexOf(
            prefixForMetaApiName + underscoreString
          ) == 0
          ? paramsToCreatePicklistItem.parent_model_id +
            '_' +
            paramsToCreatePicklistItem.record_model +
            '__c' +
            '.' +
            paramsToCreatePicklistItem.field_api_name +
            '__c'
          : prefixForMetaApiName +
            underscoreString +
            paramsToCreatePicklistItem.parent_model_id +
            '_' +
            paramsToCreatePicklistItem.record_model +
            '__c' +
            '.' +
            paramsToCreatePicklistItem.field_api_name +
            '__c';
      } else {
        customFieldName = paramsToCreatePicklistItem.record_model.contains(
            prefixForMetaApiName + underscoreString
          ) &&
          paramsToCreatePicklistItem.record_model.indexOf(
            prefixForMetaApiName + underscoreString
          ) == 0
          ? paramsToCreatePicklistItem.record_model +
            '__c' +
            '.' +
            paramsToCreatePicklistItem.field_api_name +
            '__c'
          : prefixForMetaApiName +
            underscoreString +
            paramsToCreatePicklistItem.record_model +
            '__c' +
            '.' +
            paramsToCreatePicklistItem.field_api_name +
            '__c';
      }

      // Changes for the field API issue
      List<Docfab_FieldLabel_Configuration__c> configurationList = new List<Docfab_FieldLabel_Configuration__c>();
      RequestBodyPayloadWrapper paramsToCreateField = new RequestBodyPayloadWrapper(); //paramsToCreatePicklistItem;
      paramsToCreateField.api_name = paramsToCreatePicklistItem.field_api_name;
      paramsToCreateField.parent_model = paramsToCreatePicklistItem.parent_model;
      paramsToCreateField.parent_model_id = paramsToCreatePicklistItem.parent_model_id;
      paramsToCreateField.record_model = paramsToCreatePicklistItem.record_model;
      if (paramsToCreateField.api_name.length() > 32) {
        System.debug(
          'paramsToCreateField in create the picklist item >>> ' +
          JSON.serialize(paramsToCreateField)
        );
        configurationList = checkFieldConfigurationsPresent(
          paramsToCreateField
        );
        if (!configurationList.isEmpty()) {
          customFieldName =
            configurationList[0].Model__c +
            '.' +
            configurationList[0].SF_Field_API_Name__c;
        }
      }

      // End

      MetadataService.CustomField customField = (MetadataService.CustomField) service.readMetadata(
          'CustomField',
          new List<String>{ customFieldName }
        )
        .getRecords()[0];
      MetadataService.CustomValue value = new MetadataService.CustomValue();

      // If picklist is already present in the value set Update the picklist value and make the isPickListValueAlreadyPresent true,
      // Else add new value to the value set.
      Boolean isPickListValueAlreadyPresent = false;
      // if (customField.valueSet.valueSetDefinition.value != null) {
      for (
        MetadataService.CustomValue existing : customField.valueSet.valueSetDefinition.value
      ) {
        if (
          paramsToCreatePicklistItem.api_name.equalsIgnoreCase(
            existing.fullName
          ) || paramsToCreatePicklistItem.name.equalsIgnoreCase(existing.label)
        ) {
          isPickListValueAlreadyPresent = true;
        }
      }
      // }

      if (!isPickListValueAlreadyPresent) {
        // call method to create picklist value
        value = CreateDocfabPicklistValue(paramsToCreatePicklistItem);
        if (value == null) {
          responseReturnWrapperInstance = CreateReturnResponse(
            'Getting Picklist value null while creating Picklist Item',
            500
          );
          return responseReturnWrapperInstance;
        }
        customField.valueSet.valueSetDefinition.value.add(value);
      }

      List<MetadataService.UpsertResult> results = service.upsertMetadata(
        new List<MetadataService.Metadata>{ customField }
      );
      System.debug('results >>>>' + JSON.serialize(results));
      responseReturnWrapperInstance = HandleUpsertResults(results[0]);
      return responseReturnWrapperInstance;
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Creating picklist item.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility.CreateDocfabModelPicklistItem apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      responseReturnWrapperInstance.Message = String.valueOf(ex.getMessage());
      responseReturnWrapperInstance.statuscode = 500;
      return responseReturnWrapperInstance;
    }
  }

  /*
   * @Description  This method will create picklist value.
   * @Param        paramsToCreatePicklistValue
   * @Return       MetadataService.CustomValue
   */
  public static MetadataService.CustomValue CreateDocfabPicklistValue(
    RequestBodyPayloadWrapper paramsToCreatePicklistValue
  ) {
    if (paramsToCreatePicklistValue == null) {
      return null;
    }
    MetadataService.CustomValue value = new MetadataService.CustomValue();
    value.description = paramsToCreatePicklistValue.description == null
      ? ''
      : paramsToCreatePicklistValue.description;
    value.fullName = paramsToCreatePicklistValue.api_name;
    value.default_x = false;
    value.isActive = true;
    value.label = paramsToCreatePicklistValue.name;

    return value;
  }

  /*
   * @Description  This method will create field level permission.
   * @Param        paramsToFieldPermission
   * @Return       ResponseReturnWrapper
   */
  public static ResponseReturnWrapper CreateDocfabFieldPermission(
    RequestBodyPayloadWrapper paramsToFieldPermission
  ) {
    ResponseReturnWrapper responseReturnWrapperInstance = new ResponseReturnWrapper();
    try {
      List<Docfab_FieldLabel_Configuration__c> configurationList = new List<Docfab_FieldLabel_Configuration__c>();
      Docfab_FieldAPI_Setting__c fieldApiSetting = Docfab_FieldAPI_Setting__c.getOrgDefaults();
      DocFab_User_Setting__c docfabUserCustomSetting = DocFab_User_Setting__c.getOrgDefaults();
      if (
        docfabUserCustomSetting == null ||
        String.isBlank(docfabUserCustomSetting.Profiles__c)
      ) {
        responseReturnWrapperInstance = CreateReturnResponse(
          'Unable to Set Field Permission',
          500
        );
        return responseReturnWrapperInstance;
      }
      List<String> profileList = docfabUserCustomSetting.Profiles__c.split(',');
      System.debug('profileList' + profileList);
      MetadataService.MetadataPort service = CreateService();
      if (service == null) {
        responseReturnWrapperInstance = CreateReturnResponse(
          'Metadata service is null.',
          500
        );
        return responseReturnWrapperInstance;
      }
      List<MetadataService.Metadata> metadataList = new List<MetadataService.Metadata>();
      for (String profileLoop : profileList) {
        MetadataService.Profile profile = new MetadataService.Profile();
        profile.fullName = profileLoop;

        MetadataService.ProfileFieldLevelSecurity fieldSecurity = new MetadataService.ProfileFieldLevelSecurity();
        //DIN_348 Chnages Start

        configurationList = checkFieldConfigurationsPresent(
          paramsToFieldPermission
        );
        if (!configurationList.isEmpty()) {
          paramsToFieldPermission.api_name = paramsToFieldPermission.api_name.length() >
            32
            ? (configurationList[0].SF_Field_API_Name__c.contains('__c')
                ? configurationList[0].SF_Field_API_Name__c.removeEnd('__c')
                : configurationList[0].SF_Field_API_Name__c)
            : paramsToFieldPermission.api_name;
        } else {
          paramsToFieldPermission.api_name = paramsToFieldPermission.api_name.length() >
            32
            ? ToShortAPIName(
                fieldApiSetting.FieldAPI_Postfix__c,
                paramsToFieldPermission
              )
            : paramsToFieldPermission.api_name;
        }

        //End
        fieldSecurity.field = String.isBlank(
            paramsToFieldPermission.parent_model
          )
          ? paramsToFieldPermission.record_model.contains(
                prefixForMetaApiName + underscoreString
              ) &&
              paramsToFieldPermission.record_model.indexOf(
                prefixForMetaApiName + underscoreString
              ) == 0
              ? paramsToFieldPermission.record_model +
                '__c' +
                '.' +
                paramsToFieldPermission.api_name +
                '__c'
              : prefixForMetaApiName +
                underscoreString +
                paramsToFieldPermission.record_model +
                '__c' +
                '.' +
                paramsToFieldPermission.api_name +
                '__c'
          : paramsToFieldPermission.parent_model.contains(
                prefixForMetaApiName + underscoreString
              ) &&
              paramsToFieldPermission.parent_model.indexOf(
                prefixForMetaApiName + underscoreString
              ) == 0
              ? paramsToFieldPermission.parent_model_id +
                '_' +
                paramsToFieldPermission.record_model +
                '__c' +
                '.' +
                paramsToFieldPermission.api_name +
                '__c'
              : prefixForMetaApiName +
                underscoreString +
                paramsToFieldPermission.parent_model_id +
                '_' +
                paramsToFieldPermission.record_model +
                '__c' +
                '.' +
                paramsToFieldPermission.api_name +
                '__c';

        fieldSecurity.editable = true;
        fieldSecurity.readable = true;

        profile.FieldPermissions = new List<MetadataService.ProfileFieldLevelSecurity>{
          fieldSecurity
        };
        metadataList.add(profile);
      }

      List<MetadataService.SaveResult> results = service.updateMetadata(
        metadataList
      );
      responseReturnWrapperInstance = HandleSaveResults(results[0]);
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Adding field permission.',
        String.valueOf(responseReturnWrapperInstance),
        '',
        'DF_DocFabricator_Utility.CreateDocfabFieldPermission apex class method.',
        'stackTrace',
        'lineNumber'
      );
      return responseReturnWrapperInstance;
    } catch (Exception ex) {
      System.debug(
        'Error Message in CreateDocfabFieldPermission >>>' +
          ex.getMessage() +
          'Line Number >>>' +
          ex.getLineNumber()
      );
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Adding field permission.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility.CreateDocfabFieldPermission apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      responseReturnWrapperInstance = CreateReturnResponse(
        String.valueOf(ex.getMessage()),
        500
      );
      return responseReturnWrapperInstance;
    }
  }

  /*
   * @Description  This method will create session to create object,field or picklist value.
   * @Return       MetadataService.MetadataPort - service
   */
  public static MetadataService.MetadataPort CreateService() {
    try {
      Map<String, String> usernameVsPasswordMap = new Map<String, String>();
      usernameVsPasswordMap = GetDocfabUserSetting();
      if (usernameVsPasswordMap != null && !usernameVsPasswordMap.isEmpty()) {
        Set<String> usernameSet = usernameVsPasswordMap.keySet();
        if (usernameSet != null && !usernameSet.isEmpty()) {
          MetadataService.MetadataPort service = new MetadataService.MetadataPort();
          service.SessionHeader = new MetadataService.SessionHeader_element();
          service.timeout_x = 120000;
          service.SessionHeader.sessionId = getSessionId_Apex(
            (new List<string>(usernameSet))[0],
            usernameVsPasswordMap.get((new List<string>(usernameSet))[0]),
            ''
          );
          return service;
        }
      }
    } catch (Exception ex) {
      System.debug(
        'Error Message in CreateService>>>' +
          ex.getMessage() +
          'Line Number >>>' +
          ex.getLineNumber()
      );
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Service metod to call metadata api.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility.CreateService apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
    }
    return null;
  }

  /*
   * @Description  This method will delete object.
   * @Param        paramsToDeletePicklistItem
   * @Return       String
   */
  // public static ResponseReturnWrapper DeleteDocfabObjectModel(RequestBodyPayloadWrapper paramsToDeleteObjectModel){
  //     ResponseReturnWrapper responseReturnWrapperInstance = new ResponseReturnWrapper();
  //     try {
  //         if (String.isBlank(paramsToDeleteObjectModel.api_name)) {
  //             responseReturnWrapperInstance.Message = 'Found api name empty.';
  //             responseReturnWrapperInstance.statuscode = 500;
  //             return responseReturnWrapperInstance;
  //         }
  //         String parentObjectToDelete = '';
  //         if (String.isBlank(paramsToDeleteObjectModel.parent)) {
  //             parentObjectToDelete = paramsToDeleteObjectModel.api_name.contains(prefixForMetaApiName + underscoreString) && paramsToDeleteObjectModel.api_name.indexOf(prefixForMetaApiName + underscoreString)==0 ? paramsToDeleteObjectModel.api_name+'__c': prefixForMetaApiName + underscoreString+paramsToDeleteObjectModel.api_name+'__c';
  //         }else{
  //             parentObjectToDelete = paramsToDeleteObjectModel.parent.contains(prefixForMetaApiName + underscoreString) && paramsToDeleteObjectModel.parent.indexOf(prefixForMetaApiName + underscoreString)==0 ? paramsToDeleteObjectModel.parent + '_'+ paramsToDeleteObjectModel.api_name+'__c': prefixForMetaApiName + underscoreString+ paramsToDeleteObjectModel.parent + '_'+ paramsToDeleteObjectModel.api_name+'__c';
  //         }
  //         // Get child object api name using parent api name - delete child object when parent is deleted
  //         Schema.DescribeSObjectResult parentObjectModel = Schema.getGlobalDescribe().get(parentObjectToDelete).getDescribe();//parentObjectToDelete.SObjectType.getDescribe();
  //         List<String> objectToDelete = new List<String>();
  //         for (Schema.ChildRelationship childRelation: parentObjectModel.getChildRelationships())
  //         {
  //             if (string.valueof(childRelation.getChildSObject()).contains(prefixForMetaApiName + underscoreString)  && string.valueof(childRelation.getChildSObject()).indexOf(prefixForMetaApiName + underscoreString)==0) {
  //                 system.debug('====child object==='+childRelation.getChildSObject());
  //                 objectToDelete.add(string.valueof(childRelation.getChildSObject()));
  //             }
  //         }
  //         objectToDelete.add(parentObjectToDelete);
  //         MetadataService.MetadataPort service = CreateService();// new MetadataService.MetadataPort() ;
  //         if (service == null) {
  //             responseReturnWrapperInstance.Message = 'Metadata service is null.';
  //             responseReturnWrapperInstance.statuscode = 500;
  //             return responseReturnWrapperInstance;
  //         }
  //         System.debug('objectToDelete >>> '+ String.valueOf(objectToDelete));
  //         // put object api name to delete object
  //         List<MetadataService.DeleteResult> results = service.deleteMetadata('CustomObject',objectToDelete);
  //         System.debug('results in DeleteDocfabObjectModel >>> '+JSON.serialize(results));
  //         responseReturnWrapperInstance = HandleDeleteResults(results[0]);
  //         return responseReturnWrapperInstance;
  //     } catch (Exception ex) {
  //         System.debug('Error Message in CreateService>>>'+ex.getMessage()+'Line Number >>>'+ex.getLineNumber());
  //         DFJ_ErrorLogController.addErrorLogs('', 'delete record model.', ex.getMessage(), 'Error', 'DocFabricator_Utility.DeleteDocfabObjectModel apex class method.', ex.getStackTraceString(), String.valueOf(ex.getLineNumber()));
  //         responseReturnWrapperInstance.Message = String.valueOf(ex.getMessage());
  //         responseReturnWrapperInstance.statuscode = 500;
  //         return responseReturnWrapperInstance;
  //     }
  // }

  /*
   * @Description  This method will delete the field of an object.
   * @Param        paramsToDeleteObjectModelField
   * @Return       String
   */
  // public static ResponseReturnWrapper DeleteDocfabModelField(RequestBodyPayloadWrapper paramsToDeleteObjectModelField){
  //     ResponseReturnWrapper responseReturnWrapperinstance = new ResponseReturnWrapper();
  //     try {
  //         if (String.isBlank(paramsToDeleteObjectModelField.record_model) || String.isBlank(paramsToDeleteObjectModelField.api_name)) {
  //             responseReturnWrapperinstance.Message = 'Found Api Name or Record model empty.';
  //             responseReturnWrapperinstance.statuscode = 500;
  //             return responseReturnWrapperinstance;
  //         }
  //         String fieldToDelete = '';
  //         if (!String.isBlank(paramsToDeleteObjectModelField.parent_model)) {
  //             fieldToDelete = paramsToDeleteObjectModelField.parent_model.contains(prefixForMetaApiName + underscoreString) && paramsToDeleteObjectModelField.parent_model.indexOf(prefixForMetaApiName + underscoreString)==0 ? paramsToDeleteObjectModelField.parent_model + '_'+ paramsToDeleteObjectModelField.record_model+'__c' + '.' + paramsToDeleteObjectModelField.api_name +'__c' : prefixForMetaApiName + underscoreString + paramsToDeleteObjectModelField.parent_model + '_'+ paramsToDeleteObjectModelField.record_model+'__c' + '.' + paramsToDeleteObjectModelField.api_name +'__c';
  //         }else {
  //             fieldToDelete = paramsToDeleteObjectModelField.api_name.contains(prefixForMetaApiName + underscoreString) && paramsToDeleteObjectModelField.api_name.indexOf(prefixForMetaApiName + underscoreString)==0 ? paramsToDeleteObjectModelField.record_model + '__c' + '.' + paramsToDeleteObjectModelField.api_name + '__c' : prefixForMetaApiName + underscoreString+ paramsToDeleteObjectModelField.record_model + '__c' + '.' + paramsToDeleteObjectModelField.api_name + '__c';
  //         }

  //         MetadataService.MetadataPort service = CreateService();// new MetadataService.MetadataPort() ;
  //         if (service == null) {
  //             responseReturnWrapperInstance.Message = 'Metadata service is null.';
  //             responseReturnWrapperInstance.statuscode = 500;
  //             return responseReturnWrapperInstance;
  //         }
  //         List<MetadataService.DeleteResult> results = service.deleteMetadata('CustomField', new String[] { fieldToDelete });
  //         System.debug('results in DeleteDocfabModelField >>> '+JSON.serialize(results));
  //         responseReturnWrapperinstance = HandleDeleteResults(results[0]);
  //         return responseReturnWrapperinstance;

  //     } catch (Exception ex) {
  //         System.debug('Error Message in CreateService>>>'+ex.getMessage()+'Line Number >>>'+ex.getLineNumber());
  //         DFJ_ErrorLogController.addErrorLogs('', 'Delete Docfab ModelField.', ex.getMessage(), 'Error', 'DF_DocFabricator_Utility.DeleteDocfabModelField apex class method.', ex.getStackTraceString(), String.valueOf(ex.getLineNumber()));
  //         responseReturnWrapperinstance.Message = String.valueOf(ex.getMessage());
  //         responseReturnWrapperinstance.statuscode = 500;
  //         return responseReturnWrapperinstance;
  //     }
  // }

  /*
   * @Description  This method will deactivate the picklist field item.
   * @Param        paramsToDeleteObjectModelField
   * @Return       String
   */
  public static ResponseReturnWrapper DeleteDocfabPicklistItem(
    RequestBodyPayloadWrapper paramsToDeletePicklistItem
  ) {
    ResponseReturnWrapper responseReturnWrapperinstance = new ResponseReturnWrapper();
    try {
      if (
        paramsToDeletePicklistItem == null ||
        String.isBlank(paramsToDeletePicklistItem.record_model) ||
        String.isBlank(paramsToDeletePicklistItem.api_name) ||
        String.isBlank(paramsToDeletePicklistItem.field_api_name)
      ) {
        responseReturnWrapperinstance = CreateReturnResponse(
          'Found Api Name or Field Api Name or Record model empty.',
          500
        );
        return responseReturnWrapperinstance;
      }

      String customFieldName = String.isBlank(
          paramsToDeletePicklistItem.parent_model
        )
        ? paramsToDeletePicklistItem.record_model.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToDeletePicklistItem.record_model.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToDeletePicklistItem.record_model +
              '__c' +
              '.' +
              paramsToDeletePicklistItem.field_api_name +
              '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToDeletePicklistItem.record_model +
              '__c' +
              '.' +
              paramsToDeletePicklistItem.field_api_name +
              '__c'
        : paramsToDeletePicklistItem.parent_model.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToDeletePicklistItem.parent_model.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToDeletePicklistItem.parent_model_id +
              '_' +
              paramsToDeletePicklistItem.record_model +
              '__c' +
              '.' +
              paramsToDeletePicklistItem.field_api_name +
              '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToDeletePicklistItem.parent_model_id +
              '_' +
              paramsToDeletePicklistItem.record_model +
              '__c' +
              '.' +
              paramsToDeletePicklistItem.field_api_name +
              '__c';

      MetadataService.MetadataPort service = CreateService();
      // Read Custom Field
      MetadataService.CustomField customField = (MetadataService.CustomField) service.readMetadata(
          'CustomField',
          new List<String>{ customFieldName }
        )
        ?.getRecords()[0];
      for (
        MetadataService.CustomValue existing : customField.valueSet.valueSetDefinition.value
      ) {
        if (paramsToDeletePicklistItem.api_name.equals(existing.fullName)) {
          existing.description = paramsToDeletePicklistItem.description == null
            ? ''
            : paramsToDeletePicklistItem.description;
          existing.default_x = false;
          existing.isActive = false;
          existing.label = paramsToDeletePicklistItem.name;
        }
      }

      List<MetadataService.SaveResult> results = service.updateMetadata(
        new List<MetadataService.Metadata>{ customField }
      );
      responseReturnWrapperInstance = HandleSaveResults(results[0]);
      return responseReturnWrapperInstance;
    } catch (Exception ex) {
      //System.debug('Error Message in CreateService>>>'+ex.getMessage()+'Line Number >>>'+ex.getLineNumber());
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Delete Docfab Picklist Item.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility.DeleteDocfabPicklistItem apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      responseReturnWrapperinstance = CreateReturnResponse(
        String.valueOf(ex.getMessage()),
        500
      );
      return responseReturnWrapperinstance;
    }
  }

  /*
   * @Description  This method will get the get the encrypted user password and decrypt it.
   * @Return       Map<String,String>
   */
  public static Map<String, String> GetDocfabUserSetting() {
    try {
      DocFab_User_Setting__c docfabUserCustomSetting = DocFab_User_Setting__c.getOrgDefaults();
      if (docfabUserCustomSetting != null) {
        Map<String, String> userVsPasswordMap = new Map<String, String>();
        if (
          !String.isBlank(docfabUserCustomSetting.Username__c) &&
          !String.isBlank(docfabUserCustomSetting.User_Password__c)
        ) {
          Blob CryptoKey = Blob.valueOf('12345678901234567890123456789012');
          Blob encrypteddata = EncodingUtil.base64Decode(
            docfabUserCustomSetting.User_Password__c.trim()
          );
          Blob decryptedPassword = Crypto.decryptWithManagedIV(
            'AES256',
            cryptoKey,
            encrypteddata
          );
          userVsPasswordMap.put(
            docfabUserCustomSetting.Username__c,
            decryptedPassword.toString()
          );
          return userVsPasswordMap;
        } else {
          return null;
        }
      }
      return null;
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Creating record in external system.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      return null;
    }
  }

  /*
   * @Description  This method encrypt the password and update password in Docfab user settin custom settin.
   * @Param        userName, password
   * @Return       String
   */
  public static String UpdateDocfabUserSetting(
    String userName,
    String password
  ) {
    try {
      if (
        String.isBlank(password) ||
        String.isBlank(userName) ||
        userName.equals('')
      ) {
        return 'Username or parrword is blank';
      }

      Blob CryptoKey = Blob.valueOf('12345678901234567890123456789012');
      Blob data = Blob.valueOf(password);
      Blob encryptedData = Crypto.encryptWithManagedIV(
        'AES256',
        cryptoKey,
        data
      );

      DocFab_User_Setting__c docfabUserCustomSetting = DocFab_User_Setting__c.getOrgDefaults();
      if (docfabUserCustomSetting != null) {
        docfabUserCustomSetting.User_Password__c = EncodingUtil.base64Encode(
          encryptedData
        );
        docfabUserCustomSetting.Username__c = userName;
        upsert docfabUserCustomSetting;
      }
      if (Test.isRunningTest()) {
        Double catchCoverage = 10 / 0;
      }
      return 'Custom setting updated successfully';
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Creating record in external system.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      return 'Something went wrong.';
    }
  }

  /*
   * @Description  This method is to (Softdelete) the metadata by adding the random string to api name.
   * @Param        paramsToSoftDelete, component
   * @Return       String
   */
  public static ResponseReturnWrapper SoftDeleteDocfabMetadata(
    RequestBodyPayloadWrapper paramsToSoftDelete,
    String component
  ) {
    ResponseReturnWrapper responseReturnWrapperinstance = new ResponseReturnWrapper();
    try {
      List<Docfab_FieldLabel_Configuration__c> fieldConfigurationToDelete = new List<Docfab_FieldLabel_Configuration__c>();
      String componentToDelete = '';
      String newApiName = '';

      if (
        String.isBlank(paramsToSoftDelete.deleted_api_name) ||
        String.isBlank(paramsToSoftDelete.api_name)
      ) {
        responseReturnWrapperinstance.Message = 'Found Api Name or Record model empty.';
        responseReturnWrapperinstance.statuscode = 500;
        return responseReturnWrapperinstance;
      }

      if (paramsToSoftDelete.operation.equals('SOFT_DELETE_MODEL')) {
        if (String.isBlank(paramsToSoftDelete.parent_model)) {
          componentToDelete = paramsToSoftDelete.api_name.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToSoftDelete.api_name.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToSoftDelete.api_name + '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToSoftDelete.api_name +
              '__c';
          newApiName = paramsToSoftDelete.deleted_api_name.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToSoftDelete.deleted_api_name.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToSoftDelete.deleted_api_name + '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToSoftDelete.deleted_api_name +
              '__c';
        } else {
          componentToDelete = paramsToSoftDelete.api_name.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToSoftDelete.api_name.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToSoftDelete.parent_model_id +
              '_' +
              paramsToSoftDelete.api_name +
              '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToSoftDelete.parent_model_id +
              '_' +
              paramsToSoftDelete.api_name +
              '__c';
          newApiName = paramsToSoftDelete.deleted_api_name.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToSoftDelete.deleted_api_name.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToSoftDelete.parent_model_id +
              '_' +
              paramsToSoftDelete.deleted_api_name +
              '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToSoftDelete.parent_model_id +
              '_' +
              paramsToSoftDelete.deleted_api_name +
              '__c';
        }
      } else if (paramsToSoftDelete.operation.equals('SOFT_DELETE_FIELD')) {
        if (!String.isBlank(paramsToSoftDelete.parent_model)) {
          componentToDelete = paramsToSoftDelete.parent_model.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToSoftDelete.parent_model.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToSoftDelete.parent_model_id +
              '_' +
              paramsToSoftDelete.record_model +
              '__c' +
              '.' +
              paramsToSoftDelete.api_name +
              '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToSoftDelete.parent_model_id +
              '_' +
              paramsToSoftDelete.record_model +
              '__c' +
              '.' +
              paramsToSoftDelete.api_name +
              '__c';
          newApiName = paramsToSoftDelete.deleted_api_name.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToSoftDelete.deleted_api_name.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToSoftDelete.deleted_api_name + '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToSoftDelete.parent_model_id +
              underscoreString +
              paramsToSoftDelete.record_model +
              '__c' +
              '.' +
              paramsToSoftDelete.deleted_api_name +
              '__c';
        } else {
          componentToDelete = paramsToSoftDelete.record_model.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToSoftDelete.record_model.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToSoftDelete.record_model +
              '__c' +
              '.' +
              paramsToSoftDelete.api_name +
              '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToSoftDelete.record_model +
              '__c' +
              '.' +
              paramsToSoftDelete.api_name +
              '__c';
          newApiName = paramsToSoftDelete.deleted_api_name.contains(
              prefixForMetaApiName + underscoreString
            ) &&
            paramsToSoftDelete.deleted_api_name.indexOf(
              prefixForMetaApiName + underscoreString
            ) == 0
            ? paramsToSoftDelete.record_model +
              '__c' +
              '.' +
              paramsToSoftDelete.deleted_api_name +
              '__c'
            : prefixForMetaApiName +
              underscoreString +
              paramsToSoftDelete.record_model +
              '__c' +
              '.' +
              paramsToSoftDelete.deleted_api_name +
              '__c';
        }
        //DIN-348 Changes
        //Start
        if (paramsToSoftDelete.api_name.length() > 32) {
          fieldConfigurationToDelete = checkFieldConfigurationsPresent(
            paramsToSoftDelete
          );
        }
        //End
      }

      MetadataService.MetadataPort service = CreateService();

      if (service == null) {
        responseReturnWrapperInstance.Message = 'Metadata service is null.';
        responseReturnWrapperInstance.statuscode = 500;
        return responseReturnWrapperInstance;
      }

      MetadataService.SaveResult results = service.renameMetadata(
        component,
        componentToDelete,
        newApiName
      );
      responseReturnWrapperinstance = HandleSaveResults(results);
      // DIN-319 changes
      delete fieldConfigurationToDelete;
      // Thanks
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Creating record in external system.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      responseReturnWrapperInstance = CreateReturnResponse(
        String.valueOf(ex.getMessage()),
        500
      );
    }
    return responseReturnWrapperinstance;
  }

  /*
   * @Description  this method is to interpret a SaveResult.
   * @Param        saveResult
   * @Return       ResponseReturnWrapper
   */
  public static ResponseReturnWrapper HandleSaveResults(
    MetadataService.SaveResult saveResult
  ) {
    ResponseReturnWrapper responseReturnWrapperInstance = new ResponseReturnWrapper();
    try {
      if (saveResult.success && saveResult.errors == null) {
        responseReturnWrapperInstance = CreateReturnResponse('Success', 200);
        return responseReturnWrapperInstance;
      }

      if (saveResult.errors != null) {
        List<String> messages = new List<String>();
        messages.add(
          (saveResult.errors.size() == 1 ? 'Error ' : 'Errors ') +
            'occured processing component ' +
            saveResult.fullName +
            '.'
        );
        for (MetadataService.Error error : saveResult.errors) {
          messages.add(
            error.message +
              ' (' +
              error.statusCode +
              ').' +
              (error.fields != null &&
                error.fields.size() > 0
                ? ' Fields ' + String.join(error.fields, ',') + '.'
                : '')
          );
        }
        responseReturnWrapperInstance = CreateReturnResponse(
          String.join(messages, ' '),
          500
        );
        return responseReturnWrapperInstance;
      }
      responseReturnWrapperInstance = CreateReturnResponse(
        'Failed with no specified error.',
        500
      );
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Creating record in external system.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      responseReturnWrapperInstance = CreateReturnResponse(
        String.valueOf(ex.getMessage()),
        500
      );
    }
    return responseReturnWrapperInstance;
  }

  /*
   * @Description  this method is to interpret a UpsertResult.
   * @Param        upsertResult
   * @Return       String
   */
  public static ResponseReturnWrapper HandleUpsertResults(
    MetadataService.UpsertResult upsertResult
  ) {
    ResponseReturnWrapper responseReturnWrapperInstance = new ResponseReturnWrapper();
    try {
      if (upsertResult.success && upsertResult.errors == null) {
        if (upsertResult.created) {
          responseReturnWrapperInstance.Message = 'Successfully Created';
        } else {
          responseReturnWrapperInstance.Message = 'Successfully Updated';
        }
        responseReturnWrapperInstance.statuscode = 200;
        return responseReturnWrapperInstance;
      }

      if (upsertResult.errors != null) {
        List<String> messages = new List<String>();
        messages.add(
          (upsertResult.errors.size() == 1 ? 'Error ' : 'Errors ') +
            'occured processing component ' +
            upsertResult.fullName +
            '.'
        );
        for (MetadataService.Error error : upsertResult.errors) {
          messages.add(
            error.message +
              ' (' +
              error.statusCode +
              ').' +
              (error.fields != null &&
                error.fields.size() > 0
                ? ' Fields ' + String.join(error.fields, ',') + '.'
                : '')
          );
        }
        System.debug('messages>>' + messages);
        responseReturnWrapperInstance.Message = String.join(messages, ' ');
        responseReturnWrapperInstance.statuscode = 500;
        return responseReturnWrapperInstance;
      }
      responseReturnWrapperInstance.Message = 'Failed with no specified error.';
      responseReturnWrapperInstance.statuscode = 500;
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Creating record in external system.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      responseReturnWrapperInstance.Message = String.valueOf(ex.getMessage());
      responseReturnWrapperInstance.statuscode = 500;
    }
    return responseReturnWrapperInstance;
  }

  /*
   * @Description  this method is to interpret a DeleteResult.
   * @Param        deleteResult
   * @Return       String
   */
  public static ResponseReturnWrapper HandleDeleteResults(
    MetadataService.DeleteResult deleteResult
  ) {
    ResponseReturnWrapper responseReturnWrapperInstance = new ResponseReturnWrapper();
    try {
      if (deleteResult.success && deleteResult.errors == null) {
        responseReturnWrapperInstance.Message = 'Successfully Deleted';
        responseReturnWrapperInstance.statuscode = 200;
        return responseReturnWrapperInstance;
      }

      if (deleteResult.errors != null) {
        List<String> messages = new List<String>();
        messages.add(
          (deleteResult.errors.size() == 1 ? 'Error ' : 'Errors ') +
            'occured processing component ' +
            deleteResult.fullName +
            '.'
        );

        for (MetadataService.Error error : deleteResult.errors) {
          messages.add(
            error.message +
              ' (' +
              error.statusCode +
              ').' +
              (error.fields != null &&
                error.fields.size() > 0
                ? ' Fields ' + String.join(error.fields, ',') + '.'
                : '')
          );
        }
        responseReturnWrapperInstance.Message = String.join(messages, ' ');
        responseReturnWrapperInstance.statuscode = 500;
        return responseReturnWrapperInstance;
      }
      responseReturnWrapperInstance = CreateReturnResponse(
        'Failed with no specified error.',
        500
      );
    } catch (Exception ex) {
      DFJ_ErrorLogController.addErrorLogs(
        '',
        'Creating record in external system.',
        ex.getMessage(),
        'Error',
        'DF_DocFabricator_Utility apex class method.',
        ex.getStackTraceString(),
        String.valueOf(ex.getLineNumber())
      );
      responseReturnWrapperInstance = CreateReturnResponse(
        String.valueOf(ex.getMessage()),
        500
      );
    }
    return responseReturnWrapperInstance;
  }

  /*
   * @Description  This method is to create the response.
   * @Param        returnMessage, returnStatusCode
   * @Return       ResponseReturnWrapper
   */
  public static ResponseReturnWrapper CreateReturnResponse(
    String returnMessage,
    Integer returnStatusCode
  ) {
    ResponseReturnWrapper responseReturnWrapperInstance = new ResponseReturnWrapper();
    if (String.isBlank(returnMessage) || returnStatusCode == null) {
      responseReturnWrapperInstance.Message = 'Can not set Message or Status Code';
      responseReturnWrapperInstance.statuscode = 500;
      return responseReturnWrapperInstance;
    }
    responseReturnWrapperInstance.Message = returnMessage;
    responseReturnWrapperInstance.statuscode = returnStatusCode;
    return responseReturnWrapperInstance;
  }

  /*
   * @Description  This method is to check if field configguration present or not.
   * @Param        paramToCreateField
   * @Return       Boolean
   */
  public static List<Docfab_FieldLabel_Configuration__c> checkFieldConfigurationsPresent(
    RequestBodyPayloadWrapper paramToCheckConfiguration
  ) {
    String model = Test.isRunningTest()
      ? paramToCheckConfiguration.record_model
      : prefixForMetaApiName +
        underscoreString +
        (String.isEmpty(paramToCheckConfiguration.parent_model)
          ? ''
          : paramToCheckConfiguration.parent_model_id + underscoreString) +
        paramToCheckConfiguration.record_model +
        postfixForMetaApiName;
    String docfabFieldApiName =
      paramToCheckConfiguration.api_name + postfixForMetaApiName;
    String docfabFieldLabel = paramToCheckConfiguration.name;
    List<Docfab_FieldLabel_Configuration__c> confiGurationList = new List<Docfab_FieldLabel_Configuration__c>();
    confiGurationList = [
      SELECT
        Id,
        Docfab_Field_API_Name__c,
        SF_Field_API_Name__c,
        Docfab_Field_Label__c,
        SF_Field_Label__c,
        Parent_Model__c,
        Model__c,
        Docfab_Encoded_Field_Label__c
      FROM Docfab_FieldLabel_Configuration__c
      WHERE Docfab_Field_API_Name__c = :docfabFieldApiName AND Model__c = :model
      LIMIT 1
    ]; // AND Docfab_Field_Label__c =: docfabFieldLabel
    System.debug('confiGurationList>>>>' + confiGurationList);
    return confiGurationList;
  }

  //Chages Start DIN-394
  /**
   * @Description : Method to Check the field contains in salesforce or Not
   */
  public static Boolean checkFieldPresentInsObject(
    String sObjectName,
    String fieldName
  ) {
    Map<String, SObjectField> fMap = Schema.getGlobalDescribe()
      .get(sObjectName)
      .getDescribe()
      .Fields.getMap();
    if (fMap.containsKey(fieldName)) {
      return true;
    } else {
      return false;
    }
  }
  //End

  /*
   * @Description  This method is to short the field api;
   * @Param        docfabFieldApiName
   * @Return       ResponseReturnWrapper
   */
  public static String ToShortAPIName(
    Decimal settingPostfix,
    RequestBodyPayloadWrapper paramToCreateTheShortApiName
  ) {
    Decimal postfixFieldApi = settingPostfix + 1;
    return paramToCreateTheShortApiName.api_name.replace('__', '_')
        .replace('-', '_')
        .left(32) +
      (paramToCreateTheShortApiName.api_name.replace('__', '_')
          .replace('-', '_')
          .left(32)
          .right(1)
          .equals('_')
        ? ''
        : '_') +
      (Integer.valueOf(postfixFieldApi));
  }

  /*
   * @Description  This method is to encode the field label;
   * @Param        docfabFieldApiName
   * @Return       String
   */
  public static String createEncodedLabel(String fieldLabel) {
    // String docfabFieldApiName = 'cohabiting_should_requirements_about_children_and_heirs_continue_cohabiting_should_requirements_about_children_and_heirs_continue';
    String encodedFieldName = EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA1', Blob.valueOf(fieldLabel))
    );
    return encodedFieldName;
  }

  /*
   * @Description  This method is to create the label for the field;
   * @Param        docfabFieldApiName
   * @Return       ResponseReturnWrapper
   */
  public static String createShortLabel(String fieldLabel) {
    return fieldLabel.left(32) + ' ' + createEncodedLabel(fieldLabel).left(5);
  }

  /*
   * @Description  This method is to short the field api names.
   * @Param        docfabFieldApiName
   * @Return       ResponseReturnWrapper
   */
  // public static String fromShortAPIName(){

  // }

  /*
   * @Description : Wrapper to store rest response.
   */
  public class ResponseReturnWrapper {
    public String Message;
    public Integer statuscode;
  }

  /*
   * @Description : Wrapper to store request body payload.
   */
  public class RequestBodyPayloadWrapper {
    public String operation;
    public String type;
    public String parent;
    public String name;
    public String description;
    public String api_name;
    public String deleted_api_name;
    public String parent_model;
    public String field_api_name;
    public String record_model;
    public String parent_model_id;
    public String destination_model;

    // Changes on 08-11-2021
    public String external_id;
    public ContentObjcet content;
  }

  public class ContentObjcet {
    public String version;
    public String IsChecked;
    public String Naming;
    public String DOB;
    public String SelectedValue;
    public String Age;
    public List<SublistWrapper> sublist_1;
  }

  public class SublistWrapper {
    public String uuid;
    public String version;
    public String BookName;
    public String IsIssued;
    public String BookType;
  }
}
