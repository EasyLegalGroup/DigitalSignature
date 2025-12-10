import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

// Apex methods
import createSignatureRequest from '@salesforce/apex/SignatureRequestService.createSignatureRequest';
import getSignatureRequestsForDocument from '@salesforce/apex/SignatureRequestService.getSignatureRequestsForDocument';
import getSignatureRequest from '@salesforce/apex/SignatureRequestService.getSignatureRequest';
import cancelSignatureRequest from '@salesforce/apex/SignatureRequestService.cancelSignatureRequest';

// Account fields
import PERSON_EMAIL from '@salesforce/schema/Account.PersonEmail';
import FIRST_NAME from '@salesforce/schema/Account.FirstName';
import LAST_NAME from '@salesforce/schema/Account.LastName';

const ACCOUNT_FIELDS = [PERSON_EMAIL, FIRST_NAME, LAST_NAME];

export default class SignatureRequestModal extends LightningElement {
    @api documentId;        // Shared_Document__c Id
    @api documentName;      // Document name for display
    @api journalId;         // Journal__c Id
    @api accountId;         // Account Id
    @api marketUnit;        // Market unit for the journal

    @track isOpen = false;
    @track isLoading = false;
    @track existingRequests = [];
    @track showNewRequestForm = false;

    // Form fields
    @track signerName = '';
    @track signerEmail = '';
    @track title = '';
    @track expirationDays = 14;
    @track language = 'da';

    // Account data from wire
    accountData;

    @wire(getRecord, { recordId: '$accountId', fields: ACCOUNT_FIELDS })
    wiredAccount({ data, error }) {
        if (data) {
            this.accountData = data;
            // Pre-fill signer info from account
            const firstName = getFieldValue(data, FIRST_NAME) || '';
            const lastName = getFieldValue(data, LAST_NAME) || '';
            this.signerName = `${firstName} ${lastName}`.trim();
            this.signerEmail = getFieldValue(data, PERSON_EMAIL) || '';
        } else if (error) {
            console.warn('Could not load account:', error);
        }
    }

    get languageOptions() {
        return [
            { label: 'Danish', value: 'da' },
            { label: 'English', value: 'en' },
            { label: 'Swedish', value: 'sv' },
            { label: 'Norwegian', value: 'no' }
        ];
    }

    get expirationOptions() {
        return [
            { label: '7 days', value: 7 },
            { label: '14 days', value: 14 },
            { label: '30 days', value: 30 },
            { label: '60 days', value: 60 }
        ];
    }

    get hasExistingRequests() {
        return this.existingRequests && this.existingRequests.length > 0;
    }

    get modalTitle() {
        return `Request Signature: ${this.documentName || 'Document'}`;
    }

    get canCreateNew() {
        // Check if there's an active request already
        const activeStatuses = ['Pending', 'Sent', 'Opened'];
        const hasActive = this.existingRequests.some(r => activeStatuses.includes(r.Status__c));
        return !hasActive;
    }

    get disableCreateButton() {
        return !this.signerName || !this.signerEmail || this.isLoading;
    }

    // Public method to open the modal
    // Can optionally pass docId and docName directly to avoid timing issues with @api properties
    @api
    open(docId, docName) {
        // If values are passed directly, use them (otherwise fall back to @api properties)
        if (docId) {
            this.documentId = docId;
        }
        if (docName) {
            this.documentName = docName;
        }
        this.isOpen = true;
        this.showNewRequestForm = false;
        this.loadExistingRequests();
    }

    // Public method to close the modal
    @api
    close() {
        this.isOpen = false;
        this.showNewRequestForm = false;
    }

    async loadExistingRequests() {
        if (!this.documentId) return;

        this.isLoading = true;
        try {
            this.existingRequests = await getSignatureRequestsForDocument({ 
                sharedDocumentId: this.documentId 
            });
        } catch (error) {
            console.error('Error loading signature requests:', error);
            this.showToast('Error', 'Could not load existing requests', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleClose() {
        this.close();
    }

    handleShowNewForm() {
        this.showNewRequestForm = true;
        // Pre-fill title with document name
        this.title = this.documentName || '';
    }

    handleCancelNewForm() {
        this.showNewRequestForm = false;
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        if (field) {
            this[field] = event.target.value;
        }
    }

    handleLanguageChange(event) {
        this.language = event.detail.value;
    }

    handleExpirationChange(event) {
        this.expirationDays = parseInt(event.detail.value, 10);
    }

    async handleCreateRequest() {
        if (!this.validateForm()) return;

        this.isLoading = true;
        try {
            const input = {
                accountId: this.accountId,
                journalId: this.journalId,
                sharedDocumentId: this.documentId,
                signerName: this.signerName,
                signerEmail: this.signerEmail,
                title: this.title || this.documentName,
                language: this.language,
                expirationDays: this.expirationDays,
                marketUnit: this.marketUnit,
                environment: 'sandbox' // TODO: Make configurable
            };

            const result = await createSignatureRequest({ input });

            if (result.success) {
                this.showToast('Success', 'Signature request created successfully', 'success');
                this.showNewRequestForm = false;
                await this.loadExistingRequests();
                // Fire event for parent to refresh
                this.dispatchEvent(new CustomEvent('signaturecreated', {
                    detail: { signatureRequestId: result.signatureRequestId }
                }));
            } else {
                this.showToast('Error', result.errorMessage || 'Failed to create request', 'error');
            }
        } catch (error) {
            console.error('Error creating signature request:', error);
            this.showToast('Error', error.body?.message || 'An unexpected error occurred', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleCancelRequest(event) {
        const requestId = event.target.dataset.id;
        if (!requestId) return;

        this.isLoading = true;
        try {
            const result = await cancelSignatureRequest({ signatureRequestId: requestId });
            if (result.success) {
                this.showToast('Success', 'Signature request cancelled', 'success');
                await this.loadExistingRequests();
            } else {
                this.showToast('Error', result.message || 'Failed to cancel', 'error');
            }
        } catch (error) {
            console.error('Error cancelling request:', error);
            this.showToast('Error', 'Could not cancel request', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleRefreshStatus(event) {
        const requestId = event.target.dataset.id;
        if (!requestId) return;

        this.isLoading = true;
        try {
            await getSignatureRequest({ signatureRequestId: requestId });
            await this.loadExistingRequests();
            this.showToast('Success', 'Status refreshed', 'success');
        } catch (error) {
            console.error('Error refreshing status:', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleCopyLink(event) {
        const link = event.target.dataset.link;
        if (link) {
            navigator.clipboard.writeText(link).then(() => {
                this.showToast('Success', 'Signing link copied to clipboard', 'success');
            }).catch(() => {
                this.showToast('Error', 'Could not copy link', 'error');
            });
        }
    }

    validateForm() {
        const allValid = [...this.template.querySelectorAll('lightning-input, lightning-combobox')]
            .reduce((valid, input) => {
                input.reportValidity();
                return valid && input.checkValidity();
            }, true);
        return allValid;
    }

    getStatusBadgeClass(status) {
        const statusClasses = {
            'New': 'slds-badge',
            'Pending': 'slds-badge slds-badge_inverse',
            'Sent': 'slds-badge slds-theme_info',
            'Opened': 'slds-badge slds-theme_warning',
            'Signed': 'slds-badge slds-theme_success',
            'Completed': 'slds-badge slds-theme_success',
            'Rejected': 'slds-badge slds-theme_error',
            'Expired': 'slds-badge slds-theme_shade',
            'Failed': 'slds-badge slds-theme_error'
        };
        return statusClasses[status] || 'slds-badge';
    }

    formatDate(dateValue) {
        if (!dateValue) return '';
        try {
            const d = new Date(dateValue);
            return d.toLocaleDateString('da-DK', {
                day: '2-digit',
                month: '2-digit',
                year: 'numeric'
            });
        } catch {
            return '';
        }
    }

    get requestsWithMeta() {
        return this.existingRequests.map(r => ({
            ...r,
            statusBadgeClass: this.getStatusBadgeClass(r.Status__c),
            formattedCreatedDate: this.formatDate(r.CreatedDate),
            formattedExpirationDate: this.formatDate(r.Expiration_Date__c),
            formattedCompletedDate: this.formatDate(r.Completed_Date__c),
            canCancel: ['Pending', 'Sent'].includes(r.Status__c),
            hasLink: !!r.Signing_Link__c,
            isActive: ['Pending', 'Sent', 'Opened'].includes(r.Status__c)
        }));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
