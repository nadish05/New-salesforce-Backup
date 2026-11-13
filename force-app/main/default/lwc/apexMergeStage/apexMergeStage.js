import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createMergeSession from '@salesforce/apex/ApexMergeController.createMergeSession';
import previewClassMerge from '@salesforce/apex/ApexMergeController.previewClassMerge';
import resolveClassMerge from '@salesforce/apex/ApexMergeController.resolveClassMerge';
import sealMergeManifest from '@salesforce/apex/ApexMergeController.sealMergeManifest';
function resolveApexClassIdentity(record) {
    if (!record) {
        return '';
    }
    const fileName = record.File_Name__c || '';
    if (/\.cls$/i.test(fileName) && !/\.cls-meta\.xml$/i.test(fileName)) {
        return fileName.replace(/\.cls$/i, '');
    }
    const filePath = record.File_Path__c || '';
    if (filePath.includes('/')) {
        const base = filePath.split('/').pop() || '';
        if (/\.cls$/i.test(base)) {
            return base.replace(/\.cls$/i, '');
        }
    }
    return '';
}

const CLASS_STATUS = {
    PENDING: 'PENDING',
    PREVIEWING: 'PREVIEWING',
    CONFLICT: 'CONFLICT',
    RESOLVED: 'RESOLVED',
    FAILED: 'FAILED'
};

export default class ApexMergeStage extends LightningElement {
    @api comparisonId;
    @api deploymentPlanId;
    @api mergeScopeKey;

    _eligibleRecords = [];

    @api
    get eligibleRecords() {
        return this._eligibleRecords;
    }

    set eligibleRecords(value) {
        this._eligibleRecords = Array.isArray(value) ? value : [];
        this._syncClassRows();
    }

    @track classRows = [];
    @track isInitializing = false;
    @track isSealing = false;
    @track mergeSessionId;
    @track selectedClassKey;
    @track previewData;
    @track isLoadingPreview = false;
    @track isResolving = false;
    @track sessionError;

    statusPollingInterval;

    connectedCallback() {
        this.initializeSession();
    }

    disconnectedCallback() {
        this.stopStatusPolling();
    }

    get hasEligibleClasses() {
        return this.classRows.length > 0;
    }

    get allClassesSealed() {
        return (
            this.classRows.length > 0 &&
            this.classRows.every(
                (row) => row.status === CLASS_STATUS.RESOLVED
            )
        );
    }

    get isContinueDisabled() {
        return (
            !this.allClassesSealed ||
            this.isInitializing ||
            this.isSealing ||
            this.isLoadingPreview ||
            this.isResolving
        );
    }

    get selectedRow() {
        return this.classRows.find(
            (row) => row.key === this.selectedClassKey
        );
    }

    get hasPreview() {
        return !!this.previewData;
    }

    get conflictItems() {
        const conflicts = this.previewData?.conflicts;
        if (!Array.isArray(conflicts)) {
            return [];
        }
        return conflicts.map((conflict, index) => ({
            ...conflict,
            _key: conflict?.id || `conflict-${index}`,
            message: conflict?.message || conflict?.description || String(conflict)
        }));
    }

    get hasConflicts() {
        return this.conflictItems.length > 0;
    }

    get mergedPreviewText() {
        return (
            this.previewData?.mergedContent ||
            this.previewData?.mergedPreview ||
            ''
        );
    }

    get showConflictPanel() {
        return this.hasPreview && this.hasConflicts;
    }

    _syncClassRows() {
        this.classRows = this._eligibleRecords.map((record) => {
            const metadataName = resolveApexClassIdentity(record);
            return {
                key: metadataName || record.Id,
                recordId: record.Id,
                metadataName,
                filePath: record.File_Path__c,
                status: CLASS_STATUS.PENDING,
                statusLabel: 'Pending',
                badgeClass: 'slds-badge slds-theme_warning',
                errorMessage: null
            };
        });

        if (this.classRows.length && !this.selectedClassKey) {
            this.selectedClassKey = this.classRows[0].key;
        }
    }

    async initializeSession() {
        if (
            !this.comparisonId ||
            !this.deploymentPlanId ||
            !this._eligibleRecords.length
        ) {
            return;
        }

        this.isInitializing = true;
        this.sessionError = null;

        const eligiblePayload = this._eligibleRecords.map((record) => ({
            comparisonResultId: record.Id,
            metadataType: 'ApexClass',
            metadataName: resolveApexClassIdentity(record),
            classFilePath: record.File_Path__c
        }));

        try {
            const raw = await createMergeSession({
                comparisonId: this.comparisonId,
                deploymentPlanId: this.deploymentPlanId,
                eligibleClassesJson: JSON.stringify(eligiblePayload)
            });
            const parsed = this._parseJson(raw);
            if (!parsed?.mergeSessionId) {
                throw new Error(
                    parsed?.error || 'Merge session did not return mergeSessionId.'
                );
            }
            this.mergeSessionId = parsed.mergeSessionId;
        } catch (error) {
            this.sessionError =
                error?.body?.message ||
                error?.message ||
                'Unable to initialize merge session.';
            this._dispatchMergeError(this.sessionError);
        } finally {
            this.isInitializing = false;
        }
    }

    handleClassSelect(event) {
        const key = event.currentTarget.dataset.key;
        if (!key) {
            return;
        }
        this.selectedClassKey = key;
        this.previewData = null;
    }

    async handlePreviewFullMerge() {
        const row = this.selectedRow;
        if (!row || !this.mergeSessionId) {
            return;
        }

        this._setRowStatus(row.key, CLASS_STATUS.PREVIEWING);
        this.isLoadingPreview = true;
        this.previewData = null;

        try {
            const raw = await previewClassMerge({
                comparisonId: this.comparisonId,
                deploymentPlanId: this.deploymentPlanId,
                mergeSessionId: this.mergeSessionId,
                requestJson: JSON.stringify({
                    metadataName: row.metadataName,
                    mode: 'FULL'
                })
            });
            const parsed = this._parseJson(raw);
            if (parsed?.success === false) {
                throw new Error(parsed.error || 'Preview failed.');
            }
            this.previewData = parsed;
            const hasConflict =
                parsed.hasConflicts === true ||
                (Array.isArray(parsed.conflicts) && parsed.conflicts.length);
            if (hasConflict) {
                this._setRowStatus(row.key, CLASS_STATUS.CONFLICT);
            } else {
                this._setRowStatus(row.key, CLASS_STATUS.RESOLVED);
                this._dispatchBindingChange();
            }
        } catch (error) {
            this._setRowStatus(row.key, CLASS_STATUS.FAILED, this._errorText(error));
            this._dispatchMergeError(this._errorText(error));
        } finally {
            this.isLoadingPreview = false;
        }
    }

    async handleAcceptSource() {
        await this._resolveWithStrategy('ACCEPT_SOURCE');
    }

    async handleAcceptTarget() {
        await this._resolveWithStrategy('ACCEPT_TARGET');
    }

    async _resolveWithStrategy(strategy) {
        const row = this.selectedRow;
        if (!row || !this.mergeSessionId || !this.previewData) {
            return;
        }

        this.isResolving = true;

        try {
            const raw = await resolveClassMerge({
                comparisonId: this.comparisonId,
                deploymentPlanId: this.deploymentPlanId,
                mergeSessionId: this.mergeSessionId,
                requestJson: JSON.stringify({
                    metadataName: row.metadataName,
                    mode: 'FULL',
                    resolutionStrategy: strategy
                })
            });
            const parsed = this._parseJson(raw);
            if (parsed?.success === false) {
                throw new Error(parsed.error || 'Resolve failed.');
            }

            this.previewData = {
                ...this.previewData,
                ...parsed,
                mergedContent:
                    parsed.mergedContent || parsed.mergedPreview || ''
            };

            const stillHasConflict =
                parsed.hasConflicts === true ||
                (Array.isArray(parsed.conflicts) && parsed.conflicts.length);

            if (stillHasConflict) {
                this._setRowStatus(row.key, CLASS_STATUS.CONFLICT);
            } else {
                this._setRowStatus(row.key, CLASS_STATUS.RESOLVED);
                this._dispatchBindingChange();
            }
        } catch (error) {
            this._setRowStatus(row.key, CLASS_STATUS.FAILED, this._errorText(error));
            this._dispatchMergeError(this._errorText(error));
        } finally {
            this.isResolving = false;
        }
    }

    async handleContinueToReview() {
        if (!this.allClassesSealed || !this.mergeSessionId) {
            return;
        }

        this.isSealing = true;

        try {
            const raw = await sealMergeManifest({
                comparisonId: this.comparisonId,
                deploymentPlanId: this.deploymentPlanId,
                mergeSessionId: this.mergeSessionId
            });
            const parsed = this._parseJson(raw);
            if (parsed?.success === false) {
                throw new Error(parsed.error || 'Unable to seal merge manifest.');
            }

            const manifest =
                parsed.apexMergeManifest ||
                parsed.manifest ||
                parsed;

            this.dispatchEvent(
                new CustomEvent('mergecomplete', {
                    detail: {
                        mergeSessionId: this.mergeSessionId,
                        apexMergeManifest: manifest,
                        mergeManifestId:
                            manifest?.mergeManifestId ||
                            parsed.mergeManifestId,
                        mergeBindingVersion:
                            manifest?.mergeBindingVersion ||
                            parsed.mergeBindingVersion ||
                            Date.now()
                    }
                })
            );
        } catch (error) {
            this._dispatchMergeError(this._errorText(error));
        } finally {
            this.isSealing = false;
        }
    }

    _setRowStatus(key, status, errorMessage) {
        const statusLabels = {
            [CLASS_STATUS.PENDING]: { label: 'Pending', cls: 'slds-theme_warning' },
            [CLASS_STATUS.PREVIEWING]: {
                label: 'Previewed',
                cls: 'slds-theme_info'
            },
            [CLASS_STATUS.CONFLICT]: {
                label: 'Conflict',
                cls: 'slds-theme_error'
            },
            [CLASS_STATUS.RESOLVED]: {
                label: 'Resolved',
                cls: 'slds-theme_success'
            },
            [CLASS_STATUS.FAILED]: { label: 'Failed', cls: 'slds-theme_error' }
        };

        const meta = statusLabels[status] || statusLabels[CLASS_STATUS.PENDING];

        this.classRows = this.classRows.map((row) => {
            if (row.key !== key) {
                return row;
            }
            return {
                ...row,
                status,
                statusLabel: meta.label,
                badgeClass: `slds-badge ${meta.cls}`,
                errorMessage: errorMessage || null
            };
        });
    }

    _dispatchBindingChange() {
        this.dispatchEvent(
            new CustomEvent('mergebindingchange', {
                detail: {
                    mergeSessionId: this.mergeSessionId,
                    mergeScopeKey: this.mergeScopeKey
                }
            })
        );
    }

    _dispatchMergeError(message) {
        this.dispatchEvent(
            new CustomEvent('mergeerror', {
                detail: { message }
            })
        );
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Apex Merge',
                message,
                variant: 'error',
                mode: 'dismissable'
            })
        );
    }

    stopStatusPolling() {
        if (this.statusPollingInterval) {
            clearInterval(this.statusPollingInterval);
            this.statusPollingInterval = null;
        }
    }

    _parseJson(raw) {
        if (!raw) {
            return null;
        }
        if (typeof raw === 'object') {
            return raw;
        }
        try {
            return JSON.parse(raw);
        } catch (e) {
            return { success: false, error: 'Invalid JSON response.' };
        }
    }

    _errorText(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'An unexpected error occurred.'
        );
    }
}