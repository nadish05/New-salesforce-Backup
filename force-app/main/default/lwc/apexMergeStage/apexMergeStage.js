import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createMergeSession from '@salesforce/apex/ApexMergeController.createMergeSession';
import previewClassMerge from '@salesforce/apex/ApexMergeController.previewClassMerge';
import resolveClassMerge from '@salesforce/apex/ApexMergeController.resolveClassMerge';
import publishClassMerge from '@salesforce/apex/ApexMergeController.publishClassMerge';
import getMergeSessionStatus from '@salesforce/apex/ApexMergeController.getMergeSessionStatus';
import sealMergeManifest from '@salesforce/apex/ApexMergeController.sealMergeManifest';
import {
    FULL_MERGE_MODE,
    METHOD_MERGE_MODE,
    METHOD_RESOLUTION_STRATEGY,
    buildMethodInventoryRows,
    buildMethodResolutionEntry,
    classHasUnresolvedMethodConflicts,
    isFullMergePreview,
    isMethodMergePreview
} from './apexMergeMethodInventory';
import {
    DECLARATION_RESOLUTION_SIDE,
    buildDeclarationResolutionEntry,
    buildDeclarationRows,
    classHasUnresolvedMethodOrDeclarationConflicts,
    methodMergePreviewFullyResolved,
    previewRequiresRepreviewConfirmation
} from './apexMergeDeclarationInventory';
import {
    collectMethodPublishMetadataNames,
    isPublishOutcomeAmbiguous,
    isPublishResponseConfirmed,
    isSessionPublishConfirmed,
    resolveMergeModeFromResponse,
    sessionRequiresMethodPublish,
    SESSION_STATUS
} from './apexMergePublishLifecycle';

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
    @track isPublishing = false;
    @track mergeSessionId;
    @track selectedClassKey;
    @track previewData;
    @track isLoadingPreview = false;
    @track isResolving = false;
    @track showMethodRepreviewConfirm = false;
    @track sessionError;
    @track publishedCommitSha;
    @track sessionPublishConfirmed = false;

  _continueOperationInFlight = false;

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
            this.isPublishing ||
            this.isLoadingPreview ||
            this.isResolving ||
            this._continueOperationInFlight
        );
    }

    get showPublishStatus() {
        return this.sessionPublishConfirmed && Boolean(this.publishedCommitSha);
    }

    get publishStatusLabel() {
        if (!this.showPublishStatus) {
            return '';
        }
        const shortSha = String(this.publishedCommitSha).slice(0, 7);
        return `Published to Source (${shortSha})`;
    }

    get selectedRow() {
        return this.classRows.find(
            (row) => row.key === this.selectedClassKey
        );
    }

    get hasPreview() {
        return !!this.previewData;
    }

    get isFullMergePreview() {
        return isFullMergePreview(this.previewData);
    }

    get isMethodMergePreview() {
        return isMethodMergePreview(this.previewData);
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
        return (
            this.hasPreview &&
            this.isFullMergePreview &&
            this.hasConflicts
        );
    }

    get showFullMergedPreview() {
        return this.hasPreview && this.isFullMergePreview;
    }

    get showMethodMergedPreview() {
        return (
            this.hasPreview &&
            this.isMethodMergePreview &&
            methodMergePreviewFullyResolved(this.previewData) &&
            Boolean(this.mergedPreviewText)
        );
    }

    get showDeclarationSection() {
        return (
            this.hasPreview &&
            this.isMethodMergePreview &&
            Boolean(this.previewData?.declarations)
        );
    }

    get declarationRows() {
        return buildDeclarationRows(this.previewData?.declarations);
    }

    get methodInventoryRows() {
        return buildMethodInventoryRows(this.previewData?.methods);
    }

    get hasMethodInventory() {
        return this.methodInventoryRows.length > 0;
    }

    get showMethodInventory() {
        return this.hasPreview && this.isMethodMergePreview;
    }

    get methodPreviewEmpty() {
        return this.showMethodInventory && !this.hasMethodInventory;
    }

    get isMethodResolveBusy() {
        return this.isResolving;
    }

    get isMethodPreviewActionDisabled() {
        return this.isLoadingPreview || this.isResolving;
    }

    get methodPreviewSummary() {
        if (!this.isMethodMergePreview) {
            return '';
        }
        const methodCount = this.previewData?.conflictCount;
        const methodPart =
            typeof methodCount === 'number'
                ? `${methodCount} method conflict${methodCount === 1 ? '' : 's'}`
                : 'No method conflicts';
        const declCount = this.previewData?.declarationConflictCount;
        const declPart =
            typeof declCount === 'number' && declCount > 0
                ? `${declCount} declaration conflict${declCount === 1 ? '' : 's'}`
                : null;
        const parts = [methodPart];
        if (declPart) {
            parts.push(declPart);
        }
        const resolved = methodMergePreviewFullyResolved(this.previewData)
            ? ' — ready to continue'
            : '';
        return `Method merge preview: ${parts.join('; ')}${resolved}`;
    }

    get repreviewConfirmMessage() {
        return 'Re-previewing will replace the current comparison and clear existing method and class declaration resolutions. Continue?';
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
                errorMessage: null,
                mergeMode: null
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
        this.sessionPublishConfirmed = false;
        this.publishedCommitSha = null;

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
            await this._hydrateSessionPublishState();
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

    async _hydrateSessionPublishState() {
        if (!this.mergeSessionId) {
            return;
        }

        try {
            const statusPayload = await this._fetchMergeSessionStatus();
            if (isSessionPublishConfirmed(statusPayload)) {
                const publish = statusPayload.publish || statusPayload;
                this._markSessionPublished(publish.publishedCommitSha);
            }
        } catch (e) {
            /* non-blocking recovery */
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
        await this._previewClassMerge(FULL_MERGE_MODE);
    }

    async handlePreviewMethodMerge() {
        if (this._shouldConfirmMethodRepreview()) {
            this.showMethodRepreviewConfirm = true;
            return;
        }
        await this._previewClassMerge(METHOD_MERGE_MODE);
    }

    handleCancelMethodRepreview() {
        this.showMethodRepreviewConfirm = false;
    }

    async handleConfirmMethodRepreview() {
        this.showMethodRepreviewConfirm = false;
        await this._previewClassMerge(METHOD_MERGE_MODE);
    }

    _shouldConfirmMethodRepreview() {
        return previewRequiresRepreviewConfirmation(this.previewData);
    }

    async _previewClassMerge(mode) {
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
                    mode
                })
            });
            const parsed = this._parseJson(raw);
            if (parsed?.success === false) {
                throw new Error(parsed.error || 'Preview failed.');
            }
            this.previewData = parsed;
            const effectiveMode = resolveMergeModeFromResponse(parsed, mode);
            this._applyPreviewRowStatus(row.key, parsed, effectiveMode);
        } catch (error) {
            this._setRowStatus(row.key, CLASS_STATUS.FAILED, this._errorText(error));
            this._dispatchMergeError(this._errorText(error));
        } finally {
            this.isLoadingPreview = false;
        }
    }

    async handleMethodAcceptSource(event) {
        await this._resolveSingleMethod(
            event,
            METHOD_RESOLUTION_STRATEGY.ACCEPT_SOURCE
        );
    }

    async handleMethodAcceptDestination(event) {
        await this._resolveSingleMethod(
            event,
            METHOD_RESOLUTION_STRATEGY.ACCEPT_TARGET
        );
    }

    async handleDeclarationAcceptSource(event) {
        const conflictKey = event?.currentTarget?.dataset?.conflictKey;
        if (!conflictKey) {
            return;
        }
        await this._resolveSingleDeclaration(
            conflictKey,
            DECLARATION_RESOLUTION_SIDE.SOURCE
        );
    }

    async handleDeclarationAcceptDestination(event) {
        const conflictKey = event?.currentTarget?.dataset?.conflictKey;
        if (!conflictKey) {
            return;
        }
        await this._resolveSingleDeclaration(
            conflictKey,
            DECLARATION_RESOLUTION_SIDE.DESTINATION
        );
    }

    async _resolveSingleDeclaration(conflictKey, side) {
        if (this.isResolving) {
            return;
        }

        const row = this.selectedRow;

        if (
            !conflictKey ||
            !row ||
            !this.mergeSessionId ||
            !this.previewData ||
            !this.isMethodMergePreview
        ) {
            return;
        }

        const previewSnapshot = JSON.parse(JSON.stringify(this.previewData));
        this.isResolving = true;

        try {
            const raw = await resolveClassMerge({
                comparisonId: this.comparisonId,
                deploymentPlanId: this.deploymentPlanId,
                mergeSessionId: this.mergeSessionId,
                requestJson: JSON.stringify({
                    metadataName: row.metadataName,
                    declarationResolutions: [
                        buildDeclarationResolutionEntry(conflictKey, side)
                    ]
                })
            });
            const parsed = this._parseJson(raw);
            if (parsed?.success === false) {
                throw new Error(parsed.error || 'Resolve failed.');
            }

            this.previewData = {
                ...this.previewData,
                ...parsed,
                mergeMode: METHOD_MERGE_MODE,
                mergedContent:
                    parsed.mergedContent ??
                    parsed.mergedPreview ??
                    previewSnapshot.mergedContent
            };

            const effectiveMode = resolveMergeModeFromResponse(
                parsed,
                METHOD_MERGE_MODE
            );
            this._applyPreviewRowStatus(row.key, parsed, effectiveMode);
        } catch (error) {
            this.previewData = previewSnapshot;
            if (
                classHasUnresolvedMethodOrDeclarationConflicts(previewSnapshot)
            ) {
                this._setRowStatus(row.key, CLASS_STATUS.CONFLICT);
            }
            this._dispatchMergeError(this._errorText(error));
        } finally {
            this.isResolving = false;
        }
    }

    async _resolveSingleMethod(event, strategy) {
        if (this.isResolving) {
            return;
        }

        const methodKey = event?.currentTarget?.dataset?.methodKey;
        const row = this.selectedRow;

        if (
            !methodKey ||
            !row ||
            !this.mergeSessionId ||
            !this.previewData ||
            !this.isMethodMergePreview
        ) {
            return;
        }

        const previewSnapshot = JSON.parse(JSON.stringify(this.previewData));
        this.isResolving = true;

        try {
            const raw = await resolveClassMerge({
                comparisonId: this.comparisonId,
                deploymentPlanId: this.deploymentPlanId,
                mergeSessionId: this.mergeSessionId,
                requestJson: JSON.stringify({
                    metadataName: row.metadataName,
                    methodResolutions: [
                        buildMethodResolutionEntry(methodKey, strategy)
                    ]
                })
            });
            const parsed = this._parseJson(raw);
            if (parsed?.success === false) {
                throw new Error(parsed.error || 'Resolve failed.');
            }

            this.previewData = {
                ...this.previewData,
                ...parsed,
                mergeMode: METHOD_MERGE_MODE,
                mergedContent:
                    parsed.mergedContent ??
                    parsed.mergedPreview ??
                    this.previewData.mergedContent
            };

            const effectiveMode = resolveMergeModeFromResponse(
                parsed,
                METHOD_MERGE_MODE
            );
            this._applyPreviewRowStatus(row.key, parsed, effectiveMode);
        } catch (error) {
            this.previewData = previewSnapshot;
            if (
                classHasUnresolvedMethodOrDeclarationConflicts(previewSnapshot)
            ) {
                this._setRowStatus(row.key, CLASS_STATUS.CONFLICT);
            }
            this._dispatchMergeError(this._errorText(error));
        } finally {
            this.isResolving = false;
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

            const effectiveMode = resolveMergeModeFromResponse(
                parsed,
                FULL_MERGE_MODE
            );
            this._applyPreviewRowStatus(row.key, parsed, effectiveMode);
        } catch (error) {
            this._setRowStatus(row.key, CLASS_STATUS.FAILED, this._errorText(error));
            this._dispatchMergeError(this._errorText(error));
        } finally {
            this.isResolving = false;
        }
    }

    _applyPreviewRowStatus(classKey, parsed, mode) {
        const methodMode = mode === METHOD_MERGE_MODE;
        const hasConflict = methodMode
            ? classHasUnresolvedMethodOrDeclarationConflicts(parsed)
            : parsed.hasConflicts === true ||
              (Array.isArray(parsed.conflicts) && parsed.conflicts.length);

        if (hasConflict) {
            this._setRowStatus(classKey, CLASS_STATUS.CONFLICT, null, {
                mergeMode: mode
            });
            return;
        }

        this._setRowStatus(classKey, CLASS_STATUS.RESOLVED, null, {
            mergeMode: mode
        });
        this._dispatchBindingChange();
    }

    async handleContinueToReview() {
        if (
            !this.allClassesSealed ||
            !this.mergeSessionId ||
            this._continueOperationInFlight
        ) {
            return;
        }

        this._continueOperationInFlight = true;

        try {
            const methodPublishNames =
                collectMethodPublishMetadataNames(this.classRows);
            const requiresPublish = methodPublishNames.length > 0;

            if (requiresPublish && !this.sessionPublishConfirmed) {
                await this._ensureMethodPublishComplete(methodPublishNames);
            }

            await this._sealMergeSessionAndComplete();
        } catch (error) {
            this._dispatchMergeError(this._errorText(error));
        } finally {
            this._continueOperationInFlight = false;
        }
    }

    async _ensureMethodPublishComplete(metadataNames) {
        if (!metadataNames?.length) {
            return;
        }

        if (this.sessionPublishConfirmed) {
            return;
        }

        this.isPublishing = true;

        let parsed = null;

        try {
            const raw = await publishClassMerge({
                comparisonId: this.comparisonId,
                deploymentPlanId: this.deploymentPlanId,
                mergeSessionId: this.mergeSessionId,
                requestJson: JSON.stringify({
                    metadataNames
                })
            });
            parsed = this._parseJson(raw);

            if (isPublishResponseConfirmed(parsed)) {
                this._markSessionPublished(parsed.publishedCommitSha);
                this._dispatchMergeSuccess(
                    'Method merge published to the Source branch.'
                );
                return;
            }

            if (parsed?.success === false) {
                const reconciled = await this._reconcilePublishViaSessionStatus();
                if (reconciled) {
                    return;
                }
                throw new Error(
                    parsed.error ||
                        parsed.code ||
                        'Unable to publish method merge to Source.'
                );
            }

            const reconciled = await this._reconcilePublishViaSessionStatus();
            if (!reconciled) {
                throw new Error(
                    'Publish did not complete. Session status is unavailable or inconclusive.'
                );
            }
        } catch (error) {
            if (isPublishOutcomeAmbiguous(error, parsed)) {
                const reconciled = await this._reconcilePublishViaSessionStatus();
                if (reconciled) {
                    return;
                }
                throw new Error(
                    'Publish outcome is unknown. Could not confirm publication from the merge session.'
                );
            }

            const reconciled = await this._reconcilePublishViaSessionStatus();
            if (reconciled) {
                return;
            }

            throw error;
        } finally {
            this.isPublishing = false;
        }
    }

    async _reconcilePublishViaSessionStatus() {
        const statusPayload = await this._fetchMergeSessionStatus();

        if (!statusPayload) {
            return false;
        }

        if (statusPayload.status === SESSION_STATUS.SEALED) {
            throw new Error(
                'Merge session is already sealed. Refresh the page and continue to Deployment Review if merge completed.'
            );
        }

        if (isSessionPublishConfirmed(statusPayload)) {
            const publish = statusPayload.publish || statusPayload;
            this._markSessionPublished(publish.publishedCommitSha);
            this._dispatchMergeSuccess(
                'Publish confirmed from merge session status.'
            );
            return true;
        }

        return false;
    }

    async _fetchMergeSessionStatus() {
        if (!this.mergeSessionId) {
            return null;
        }

        try {
            const raw = await getMergeSessionStatus({
                mergeSessionId: this.mergeSessionId
            });
            const parsed = this._parseJson(raw);

            if (!parsed) {
                return null;
            }

            if (parsed.success === false && !parsed.publish) {
                return null;
            }

            return parsed;
        } catch (e) {
            return null;
        }
    }

    _markSessionPublished(publishedCommitSha) {
        if (
            typeof publishedCommitSha !== 'string' ||
            !publishedCommitSha.trim()
        ) {
            return;
        }
        this.sessionPublishConfirmed = true;
        this.publishedCommitSha = publishedCommitSha.trim();
    }

    async _sealMergeSessionAndComplete() {
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
        } finally {
            this.isSealing = false;
        }
    }

    _setRowStatus(key, status, errorMessage, options = {}) {
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
        const nextMergeMode = options?.mergeMode;

        this.classRows = this.classRows.map((row) => {
            if (row.key !== key) {
                return row;
            }

            const mergeMode =
                nextMergeMode === METHOD_MERGE_MODE ||
                nextMergeMode === FULL_MERGE_MODE
                    ? nextMergeMode
                    : row.mergeMode;

            return {
                ...row,
                status,
                statusLabel: meta.label,
                badgeClass: `slds-badge ${meta.cls}`,
                errorMessage: errorMessage || null,
                mergeMode
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

    _dispatchMergeSuccess(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Apex Merge',
                message,
                variant: 'success',
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