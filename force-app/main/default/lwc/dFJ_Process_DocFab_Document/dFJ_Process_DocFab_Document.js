import { LightningElement, wire, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";

import getJournalOptions from "@salesforce/apex/DFJ_ProcessDocFabDocument_Apex.getJournalOptions";

export default class DFJ_Process_DocFab_Document extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  @api objectApiName;
  journalOptions = [];
  isSelectionModalOpen = false;

  get isUrlNotAvailable() {
    return this.journalOptions.length === 0;
  }

  @wire(getJournalOptions, {
    recordId: "$recordId",
    objectApiName: "$objectApiName"
  })
  wiredJournalOptions(value) {
    const { data, error } = value;
    if (data) {
      this.journalOptions = Array.isArray(data) ? data : [];
    }
    if (error) {
      console.error(
        "Error in DFJ_Process_DocFab_Document.wiredJournalOptions:",
        JSON.stringify(error)
      );
      this.journalOptions = [];
    }
  }

  handleProcessDocFabDocumentButtonClick() {
    try {
      if (!this.journalOptions || this.journalOptions.length === 0) {
        return;
      }

      if (this.journalOptions.length === 1) {
        this.navigateToUrl(this.journalOptions[0].url);
        return;
      }

      this.isSelectionModalOpen = true;
    } catch (ex) {
      console.error("Error--" + ex);
    }
  }

  handleSelectionModalClose() {
    this.isSelectionModalOpen = false;
  }

  handleJournalSelect(event) {
    const journalId = event.currentTarget?.dataset?.id;
    if (!journalId) {
      return;
    }
    const selected = (this.journalOptions || []).find(
      (o) => o.journalId === journalId
    );
    if (!selected || !selected.url) {
      return;
    }

    this.isSelectionModalOpen = false;
    this.navigateToUrl(selected.url);
  }

  navigateToUrl(url) {
    if (!url) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: {
        url: url
      }
    });
  }
}
