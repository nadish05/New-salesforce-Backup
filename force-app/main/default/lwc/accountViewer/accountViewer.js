import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccounts from '@salesforce/apex/AccountController.getAccounts';
import updateAccounts from '@salesforce/apex/AccountController.updateAccounts';

/**
 * @description Production-ready LWC for displaying and editing Account records
 * Features: Inline editing, draft tracking, bulk updates, error handling, user feedback
 */
export default class AccountViewer extends LightningElement {
    // Data properties
    @track accounts = [];
    @track draftValues = [];

    // UI state properties
    @track isLoading = false;

    // Datatable column definitions with editable fields
    columns = [
        { 
            label: 'Account Name', 
            fieldName: 'Name',
            type: 'text',
            editable: true
        },
        { 
            label: 'Industry', 
            fieldName: 'Industry',
            type: 'text',
            editable: false
        },
        { 
            label: 'Phone', 
            fieldName: 'Phone',
            type: 'phone',
            editable: true
        }
    ];

    /**
     * @description Getter - Check if Save button should be disabled
     * Save disabled when no draft changes or loading
     */
    get isSaveDisabled() {
        return this.draftValues.length === 0 || this.isLoading;
    }

    /**
     * @description Getter - Check if Discard button should be disabled
     * Discard disabled when no draft changes
     */
    get isDiscardDisabled() {
        return this.draftValues.length === 0;
    }

    /**
     * @description Getter - Check if there are draft values
     */
    get hasDraftValues() {
        return this.draftValues.length > 0;
    }

    /**
     * @description Getter - Count of draft values for display
     */
    get draftValueCount() {
        return this.draftValues.length;
    }

    /**
     * @description Load accounts from Salesforce
     * Called when user clicks "Load Accounts" button
     */
    handleLoadAccounts() {
        this.isLoading = true;
        this.draftValues = [];

        getAccounts()
            .then(result => {
                this.accounts = result;
                this.showToast('Success', 'Accounts loaded successfully', 'success');
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading accounts:', error);
                this.showToast(
                    'Error',
                    'Failed to load accounts: ' + (error.body?.message || error.message),
                    'error'
                );
                this.isLoading = false;
            });
    }

    /**
     * @description Handle inline editing of datatable rows
     * Captures draft values when user edits cells
     * @param event - Custom event from lightning-datatable
     */
    handleSave(event) {
        // Get draft values from datatable
        const draftValuesList = event.detail.draftValues;

        // Update internal draft tracking
        this.draftValues = draftValuesList;

        console.log('Draft changes tracked:', this.draftValues);
    }

    /**
     * @description Save all edited records to Salesforce
     * Prepares payload from draft values, calls Apex, handles response
     */
    handleSaveAccounts() {
        // Validate draft values exist
        if (this.draftValues.length === 0) {
            this.showToast('Info', 'No changes to save', 'info');
            return;
        }

        this.isLoading = true;

        // Build update payload from draft values and original data
        const recordsToUpdate = this.buildUpdatePayload();

        // Call Apex to update records
        updateAccounts({ accountsToUpdate: recordsToUpdate })
            .then(result => {
                this.handleSaveResponse(result);
            })
            .catch(error => {
                console.error('Error updating accounts:', error);
                this.showToast(
                    'Error',
                    'Failed to update accounts: ' + (error.body?.message || error.message),
                    'error'
                );
                this.isLoading = false;
            });
    }

    /**
     * @description Build the update payload by merging draft values with original data
     * @return Array of Account objects ready for update
     */
    buildUpdatePayload() {
        const recordsToUpdate = [];

        // Create a map of existing accounts for quick lookup
        const accountMap = new Map();
        this.accounts.forEach(account => {
            accountMap.set(account.Id, { ...account });
        });

        // Apply draft changes to accounts
        this.draftValues.forEach(draft => {
            const existingAccount = accountMap.get(draft.Id);
            if (existingAccount) {
                // Merge draft values into account
                const updatedAccount = { ...existingAccount, ...draft };
                recordsToUpdate.push(updatedAccount);
            }
        });

        return recordsToUpdate;
    }

    /**
     * @description Handle Apex response and update UI
     * @param result - Response object from updateAccounts Apex method
     */
    handleSaveResponse(result) {
        try {
            if (result.success) {
                this.showToast('Success', result.message, 'success');
                // Clear draft values after successful update
                this.draftValues = [];
                // Refresh data from server to reflect updates
                this.handleLoadAccounts();
            } else {
                this.showToast('Error', result.message, 'error');
                this.isLoading = false;
            }
        } catch (error) {
            console.error('Error processing save response:', error);
            this.showToast('Error', 'Unexpected error: ' + error.message, 'error');
            this.isLoading = false;
        }
    }

    /**
     * @description Discard all draft changes
     */
    handleDiscardChanges() {
        this.draftValues = [];
        this.showToast('Info', 'Changes discarded', 'info');
    }

    /**
     * @description Display toast notification to user
     * @param title - Toast title
     * @param message - Toast message
     * @param variant - Toast type (success, error, warning, info)
     */
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissible'
        });
        this.dispatchEvent(evt);
    }
}