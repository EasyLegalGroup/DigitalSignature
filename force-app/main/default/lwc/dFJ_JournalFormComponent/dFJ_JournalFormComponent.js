import { api, LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import LEAD_FIELD from "@salesforce/schema/Journal__c.Lead__c";
import EXTERNAL_UUID_FIELD from "@salesforce/schema/Journal__c.External_record_uuid__c";
import DOCFAB_MODEL_ID_FIELD from "@salesforce/schema/Journal__c.DocFab_Record_Model_ID__c";

import getJournalData_Apex from "@salesforce/apex/DFJ_JournalForm.getJournalData_Apex";
import journalAssociatedWithLead from "@salesforce/apex/DFJ_JournalForm.journalAssociatedWithLead";
import journalAssociatedWithOpportunity from "@salesforce/apex/DFJ_JournalForm.journalAssociatedWithOpportunity";
import getAccessibleOptionsWithContext from "@salesforce/apex/DF_DocFabricator_Utility.getAccessibleOptionsWithContext";
import getFormsForRecordModel from "@salesforce/apex/DF_DocFabricator_Utility.getFormsForRecordModel";

export default class DFJ_JournalFormComponent extends LightningElement {
  @api recordId;
  @api objectApiName;

  // New page layout properties for two-tier selection
  @api formNumbers = ""; // Comma-separated Form Numbers (e.g., "17, 51, 22")
  @api buttonLabel = "Open Journal Form"; // Customizable button label
  @api buttonIcon = ""; // Optional icon for the button (e.g., "utility:edit_form")
  @api openBehavior = "modal"; // modal | newTab | inline

  // DEPRECATED: Legacy properties kept for backwards compatibility
  // Remove these after migrating all page layouts to new architecture
  @api recordModelId; // DEPRECATED - use recordModelIds
  @api formUuid; // DEPRECATED - use formNumbers
  @api formUuids; // DEPRECATED - use formNumbers
  @api formTypeUniqueName; // DEPRECATED - no longer used
  @api allowMultipleDocFabJournals; // DEPRECATED - Leads now always support multiple journals

  // Internal state
  isJournalFormClicked = true;
  docFabFormUrl;
  isShowFormInModal = false;
  isShowInline = false;
  isInitialized = false;
  relatedLeadId;
  isFetchingForm = false;
  isIframeLoading = false;

  // Two-tier selection state
  isSelectionModalOpen = false;
  selectionStep = "recordModel"; // 'recordModel' or 'form'
  recordModelOptions = [];
  formOptions = [];
  selectedRecordModelId = null;
  selectedFormUuid = null;
  fieldConfigurationJson = null;

  get isFormLoading() {
    return this.isFetchingForm || this.isIframeLoading;
  }

  get shouldRenderInlineArea() {
    return (
      this.openBehavior === "inline" &&
      (this.isShowInline || this.isFormLoading)
    );
  }

  get journalRecordId() {
    return this.objectApiName === "Journal__c" ? this.recordId : null;
  }

  // Journal record data (for context-aware selection)
  journalExternalUuid;
  journalRecordModelId;

  @wire(getRecord, {
    recordId: "$journalRecordId",
    fields: [LEAD_FIELD, EXTERNAL_UUID_FIELD, DOCFAB_MODEL_ID_FIELD]
  })
  fieldsData({ data }) {
    if (data) {
      this.relatedLeadId = getFieldValue(data, LEAD_FIELD);
      this.journalExternalUuid = getFieldValue(data, EXTERNAL_UUID_FIELD);
      this.journalRecordModelId = getFieldValue(data, DOCFAB_MODEL_ID_FIELD);
    }
  }

  async handleOpenJournalFormButtonClick() {
    if (this.isFormLoading) {
      return;
    }

    // If already initialized and showing, toggle visibility
    if (this.isInitialized) {
      const isCurrentlyVisible =
        this.openBehavior === "inline"
          ? this.isShowInline
          : this.isShowFormInModal;

      if (isCurrentlyVisible) {
        this.toggleVisibility();
        return;
      }

      this.isIframeLoading = true;
      this.toggleVisibility(true);
      return;
    }

    // First click - start the selection flow
    this.isFetchingForm = true;
    try {
      await this.startSelectionFlow();
    } finally {
      this.isFetchingForm = false;
    }
  }

  /**
   * Start the two-tier selection flow by getting accessible options
   */
  async startSelectionFlow() {
    try {
      const options = await getAccessibleOptionsWithContext({
        recordModelIdsCsv: "",
        formNumbersCsv: this.formNumbers || "",
        objectApiName: this.objectApiName || "Journal__c",
        recordId: this.recordId,
        existingExternalUuid: this.journalExternalUuid || "",
        existingRecordModelId: this.journalRecordModelId || ""
      });

      // Check for errors
      if (options.errorMessage) {
        this.showToast("Configuration Error", options.errorMessage, "error");
        return;
      }

      // Check if we have a direct open URL (existing DocFab without page layout config)
      if (options.directOpenUrl) {
        this.docFabFormUrl = options.directOpenUrl;
        this.isInitialized = true;
        this.isIframeLoading = this.openBehavior !== "newTab";
        this.toggleVisibility(true);
        return;
      }

      // Store the options
      this.recordModelOptions = options.recordModels || [];
      this.formOptions = options.forms || [];

      // Determine what to show
      if (
        !options.requiresRecordModelSelection &&
        !options.requiresFormSelection
      ) {
        // Direct open - only one option
        this.selectedRecordModelId = options.resolvedRecordModelId;
        this.selectedFormUuid = options.resolvedFormUuid;
        this.fieldConfigurationJson = options.fieldConfigurationJson;
        await this.openJournalForm();
      } else if (
        !options.requiresRecordModelSelection &&
        options.requiresFormSelection
      ) {
        // Skip record model selection, show form picker
        this.selectedRecordModelId = options.resolvedRecordModelId;
        this.fieldConfigurationJson = options.fieldConfigurationJson;
        this.selectionStep = "form";
        this.isSelectionModalOpen = true;
      } else {
        // Show record model picker first
        this.selectionStep = "recordModel";
        this.isSelectionModalOpen = true;
      }
    } catch (error) {
      const message =
        (error && error.body && error.body.message) ||
        error.message ||
        "Unexpected error";
      this.showToast("Error", message, "error");
    }
  }

  /**
   * Handle record model selection
   */
  async handleRecordModelSelect(event) {
    const recordModelId = event.currentTarget.dataset.id;
    if (!recordModelId) return;

    this.selectedRecordModelId = recordModelId;
    this.isFetchingForm = true;

    try {
      // Get forms for this record model
      const options = await getFormsForRecordModel({
        recordModelId: recordModelId,
        formNumbersCsv: this.formNumbers || ""
      });

      if (options.errorMessage) {
        this.showToast("Error", options.errorMessage, "error");
        this.isFetchingForm = false;
        return;
      }

      this.formOptions = options.forms || [];
      this.fieldConfigurationJson = options.fieldConfigurationJson;

      if (!options.requiresFormSelection && options.resolvedFormUuid) {
        // Only one form - open directly
        this.selectedFormUuid = options.resolvedFormUuid;
        this.isSelectionModalOpen = false;
        await this.openJournalForm();
      } else {
        // Multiple forms - show form picker
        this.selectionStep = "form";
      }
    } catch (error) {
      const message =
        (error && error.body && error.body.message) ||
        error.message ||
        "Unexpected error";
      this.showToast("Error", message, "error");
    } finally {
      this.isFetchingForm = false;
    }
  }

  /**
   * Handle form selection
   */
  async handleFormSelect(event) {
    const formUuid = event.currentTarget.dataset.id;
    if (!formUuid) return;

    this.selectedFormUuid = formUuid;
    this.isSelectionModalOpen = false;

    this.isFetchingForm = true;
    try {
      await this.openJournalForm();
    } finally {
      this.isFetchingForm = false;
    }
  }

  /**
   * Open the journal form with selected record model and form
   */
  async openJournalForm() {
    try {
      let journalId = this.recordId;
      let contextRecordId = this.relatedLeadId;

      const isLeadContext = this.objectApiName === "Lead";
      if (isLeadContext) {
        contextRecordId = this.recordId;
        const journals = await journalAssociatedWithLead({
          recordId: this.recordId
        });
        if (!journals || !journals.length) {
          this.showToast(
            "Error opening journal",
            "No journal found or created for this lead.",
            "error"
          );
          return;
        }
        journalId = journals[0].Id;
      }

      const isOpportunityContext = this.objectApiName === "Opportunity";
      if (isOpportunityContext) {
        contextRecordId = this.recordId;
        const journals = await journalAssociatedWithOpportunity({
          opportunityId: this.recordId,
          recordModelId: this.selectedRecordModelId
        });
        if (!journals || !journals.length) {
          this.showToast(
            "Error opening journal",
            "No journal found or created for this opportunity.",
            "error"
          );
          return;
        }
        journalId = journals[0].Id;
      }

      const response = await getJournalData_Apex({
        JournalId: journalId,
        contextRecordId: contextRecordId,
        objectName: this.objectApiName || "Journal__c",
        journlaFormClicked: this.isJournalFormClicked,
        componentRecordModelId: parseFloat(this.selectedRecordModelId),
        componentFormUuid: this.selectedFormUuid,
        componentFormTypeName: null
      });

      let docFabUrl = response && response.docFabUrl;

      if (!docFabUrl) {
        this.showToast(
          "Error opening journal",
          "DocFab URL not available for this record.",
          "error"
        );
        return;
      }

      if (this.isDocFabError(docFabUrl)) {
        this.showToast("Error opening journal", docFabUrl, "error");
        return;
      }

      this.docFabFormUrl = docFabUrl;
      this.isInitialized = true;
      this.isIframeLoading = this.openBehavior !== "newTab";
      this.toggleVisibility(true);
    } catch (error) {
      const message =
        (error && error.body && error.body.message) ||
        error.message ||
        "Unexpected error";
      this.showToast("Error opening journal", message, "error");
    }
  }

  /**
   * Go back from form selection to record model selection
   */
  handleBackToRecordModels() {
    this.selectionStep = "recordModel";
    this.selectedRecordModelId = null;
  }

  get displayButtonLabel() {
    if (this.isFormLoading) {
      return "Loading Journal Form...";
    }
    return this.computedButtonLabel;
  }

  get buttonAriaLabel() {
    return this.displayButtonLabel;
  }

  get buttonIconName() {
    if (this.isFormLoading) {
      return null;
    }
    // Return the configured icon, or null if none specified
    return this.buttonIcon || null;
  }

  get computedButtonLabel() {
    const customLabel = this.buttonLabel || "Open Journal Form";

    if (this.openBehavior === "newTab") {
      return customLabel;
    }
    const isShowing =
      this.openBehavior === "inline"
        ? this.isShowInline
        : this.isShowFormInModal;
    if (!this.isInitialized) {
      return customLabel;
    }
    return isShowing ? "Hide Journal Form" : "Show Journal Form";
  }

  get selectionModalTitle() {
    return this.selectionStep === "recordModel"
      ? "Select Journal Type"
      : "Select Form View";
  }

  get selectionModalSubtitle() {
    return this.selectionStep === "recordModel"
      ? "Choose which type of journal you want to open or create"
      : "Choose how you want to view this journal";
  }

  get selectionModalIcon() {
    return this.selectionStep === "recordModel"
      ? "standard:form"
      : "standard:article";
  }

  get showRecordModelSelection() {
    return this.selectionStep === "recordModel";
  }

  get showFormSelection() {
    return this.selectionStep === "form";
  }

  get showBackButton() {
    return this.selectionStep === "form" && this.recordModelOptions.length > 1;
  }

  get currentFormOptions() {
    // Filter forms to only those for the selected record model
    if (!this.selectedRecordModelId) {
      return this.formOptions;
    }
    return this.formOptions.filter(
      (f) => f.recordModelId === this.selectedRecordModelId
    );
  }

  toggleVisibility(forceShow = false) {
    if (!this.docFabFormUrl) {
      return;
    }

    if (this.openBehavior === "newTab") {
      window.open(this.docFabFormUrl, "_blank");
      this.isShowFormInModal = false;
      this.isShowInline = false;
      this.isIframeLoading = false;
    } else if (this.openBehavior === "inline") {
      const shouldShow = forceShow ? true : !this.isShowInline;
      this.isShowInline = shouldShow;
      this.isShowFormInModal = false;
      this.isIframeLoading = shouldShow ? this.isIframeLoading : false;
    } else {
      const shouldShow = forceShow ? true : !this.isShowFormInModal;
      this.isShowFormInModal = shouldShow;
      this.isShowInline = false;
      this.isIframeLoading = shouldShow ? this.isIframeLoading : false;
    }
  }

  handleCloseModal() {
    this.isShowFormInModal = false;
    this.isIframeLoading = false;
  }

  handleSelectionModalClose() {
    this.isSelectionModalOpen = false;
    this.selectionStep = "recordModel";
    this.selectedRecordModelId = null;
    this.selectedFormUuid = null;
  }

  handleIframeLoad() {
    this.isIframeLoading = false;
  }

  isDocFabError(url) {
    const errorSnippets = [
      "Current user with",
      "No form configuration found",
      "Can not open",
      "Can not create",
      "Error",
      "is required",
      "do not have access",
      "not configured"
    ];
    return errorSnippets.some((snippet) => url.includes(snippet));
  }

  showToast(title, message, variant = "info") {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant,
        mode: "sticky"
      })
    );
  }
}
