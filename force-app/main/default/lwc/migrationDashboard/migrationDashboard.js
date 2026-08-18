import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import {
    buildCuratedSupportBundleValidationContext,
    measureSupportBundleRequestSize
} from './supportBundleContextCuration';

import {
    buildAiResolutionTransportContext,
    measureAiResolutionRequestSize
} from './aiResolutionTransportContext';

import { mapPhase2aExplanationDisplay } from './aiResolutionPhase2aDisplay';

import BACKEND_BASE_URL
from '@salesforce/label/c.Backend_Base_URL';

import updateIntent
from '@salesforce/apex/DeploymentController.updateIntent';

import checkBackendConnection
from '@salesforce/apex/BackendController.checkBackendConnection';

import getConnectedOrgs
from '@salesforce/apex/ConnectedOrgController.getConnectedOrgs';

import getOAuthUrl
from '@salesforce/apex/BackendController.getOAuthUrl';

import getLatestOAuthResult
from '@salesforce/apex/ConnectedOrgController.getLatestOAuthResult';

import saveConnectedOrg
from '@salesforce/apex/ConnectedOrgController.saveConnectedOrg';

import getOrgDetails
from '@salesforce/apex/ConnectedOrgController.getOrgDetails';

import startMigration 
from '@salesforce/apex/BackendController.startMigration';

import startComparisonMigration
from '@salesforce/apex/BackendController.startComparisonMigration';

import saveComparison
from '@salesforce/apex/MetadataComparisonController.saveComparison';

import getComparisons
from '@salesforce/apex/MetadataComparisonController.getComparisons';

import getComparisonDetails
from '@salesforce/apex/MetadataComparisonController.getComparisonDetails';

import updateMigrationStatus
from '@salesforce/apex/MetadataComparisonController.updateMigrationStatus';

import compareBranches
from '@salesforce/apex/BackendController.compareBranches';

import saveComparisonResults
from '@salesforce/apex/MetadataComparisonController.saveComparisonResults';

import getComparisonResults
from '@salesforce/apex/MetadataComparisonController.getComparisonResults';

import getDifferenceReport
from '@salesforce/apex/BackendController.getDifferenceReport';

import getMigrationStatus
from '@salesforce/apex/BackendController.getMigrationStatus';

import createDeploymentPlan
from '@salesforce/apex/DeploymentPlanController.createDeploymentPlan';

import getLatestDeploymentPlanId
from '@salesforce/apex/DeploymentPlanController.getLatestDeploymentPlanId';

import getLatestDeploymentPlanState
from '@salesforce/apex/DeploymentPlanController.getLatestDeploymentPlanState';

import saveLatestReviewSnapshot
from '@salesforce/apex/DeploymentPlanController.saveLatestReviewSnapshot';

import saveLatestSourceValidationSnapshot
from '@salesforce/apex/DeploymentPlanController.saveLatestSourceValidationSnapshot';

import saveLatestDeploymentValidationSnapshot
from '@salesforce/apex/DeploymentPlanController.saveLatestDeploymentValidationSnapshot';

import getDeploymentReview
from '@salesforce/apex/DeploymentReviewController.getDeploymentReview';

import GITHUB_REPO_URL
from '@salesforce/label/c.GitHub_Repo_URL';

import validateSource
from '@salesforce/apex/SourceValidationController.validateDeployment';

import validateDestinationDeployment
from '@salesforce/apex/DeploymentValidationController.validateDeployment';

import startDeploymentValidation
from '@salesforce/apex/DeploymentValidationController.startValidation';

import getValidationStatus
from '@salesforce/apex/DeploymentValidationController.getValidationStatus';

import saveDeploymentHistory
from '@salesforce/apex/DeploymentHistoryController.saveDeploymentHistory';

import getAiAdvisor
from '@salesforce/apex/AiAdvisorController.getAiAdvisor';

import resolveWithAi
from '@salesforce/apex/DeploymentAiResolutionController.resolveWithAi';

import createSupportBundle
from '@salesforce/apex/DeploymentSupportBundleController.createSupportBundle';

export default class MigrationDashboard extends LightningElement {

    // ─── PHASE 1: Navigation State ──────────────────────────────────────
    // Default changed from 'home' to 'comparison'.
    // Home view removed. Backup accessible via nav tab.
    currentView = 'comparison';

    get isBackupView() {
        return this.currentView === 'backup';
    }

    get isComparisonView() {
        return this.currentView === 'comparison';
    }

    // PHASE 1: Nav tab CSS classes
    get comparisonTabClass() {
        return this.currentView === 'comparison'
            ? 'ws-nav-tab ws-nav-tab--active'
            : 'ws-nav-tab';
    }

    get backupTabClass() {
        return this.currentView === 'backup'
            ? 'ws-nav-tab ws-nav-tab--active'
            : 'ws-nav-tab';
    }

    goToBackup() {
        this.currentView = 'backup';
    }

    goToComparison() {
        if (this.isRetrievalInProgress) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Metadata Retrieval in Progress',
                    message:
                        'Please wait until metadata retrieval finishes before changing workspace context.',
                    variant: 'info',
                    mode: 'dismissable'
                })
            );
            return;
        }
        this.currentView = 'comparison';
        this.selectedComparison = '';
        this.selectedComparisonRecord = null;
        this.savedComparisonResults = [];
        this.groupedComparisonResults = [];
        this.filterDeploymentIntent = 'ALL';
        this.filterChangeType = 'ALL';
        this.filterMetadataType = 'ALL';
    }

    // Thin wrapper — calls original handleComparisonChange (unchanged)
    handleComparisonSelect(event) {
        this.handleComparisonChange(event);
    }
    // ────────────────────────────────────────────────────────────────────


    // ─── PHASE 2: Stage Modal Flags ──────────────────────────────────────
    // Handlers unchanged (STEP 6). Stages 1–3 rail clicks still invoke these.
    isStage1ModalOpen = false;
    isStage2ModalOpen = false;
    isStage3ModalOpen = false;
    

    openStage1Modal()  { this.isStage1ModalOpen = true; }
    closeStage1Modal() { this.isStage1ModalOpen = false; }

    openStage2Modal()  { this.isStage2ModalOpen = true; }
    closeStage2Modal() {
        if (this.isRetrievalInProgress) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Metadata Retrieval in Progress',
                    message:
                        'The retrieval workspace stays open until metadata retrieval finishes.',
                    variant: 'info',
                    mode: 'dismissable'
                })
            );
            return;
        }
        this.isStage2ModalOpen = false;
    }

    openStage3Modal()  { this.isStage3ModalOpen = true; }
    closeStage3Modal() { this.isStage3ModalOpen = false; }

    
    // ────────────────────────────────────────────────────────────────────


    // ─── PHASE 1: Lifecycle Stage Navigation ─────────────────────────────
    // Navigation only — no backend calls, no validation.
    // Default 3 = Metadata Comparison (today's default workspace).
    activeLifecycleStage = 3;

    get isStage1Workspace() { return this.activeLifecycleStage === 1; }
    get isStage2Workspace() { return this.activeLifecycleStage === 2; }
    get isStage3Workspace() { return this.activeLifecycleStage === 3; }
    get isStage4Workspace() { return this.activeLifecycleStage === 4; }
    get isStage5Workspace() { return this.activeLifecycleStage === 5; }
    get isStage6Workspace() { return this.activeLifecycleStage === 6; }

    /**
     * Stage 4 unlock — requires an existing deployment plan Id.
     * Reuses currentDeploymentPlanId set by handleCreateDeploymentPlan.
     */
    get canOpenStage4() {
        return !!this.currentDeploymentPlanId;
    }

    /**
     * Stage 5 unlock — Source Validation Overall + Quality Gate both PASS.
     * Reuses overallSourceValidationStatus (derived from sourceValidationData).
     */
    get canOpenStage5() {
        return this.overallSourceValidationStatus === 'PASS';
    }

    /**
     * Rail click — guided lifecycle navigation.
     * Stages 1–3: open existing action modals (handlers unmodified).
     * Stage 4: blocked with toast until a deployment plan exists.
     * Stages 5–6: navigation only (unchanged).
     */
    handleLifecycleStageClick(event) {
        const stage = parseInt(event.currentTarget.dataset.stage, 10);
        if (!(stage >= 1 && stage <= 6)) {
            return;
        }

        // Temporary UI lock — do not leave Metadata Retrieval while a run is active.
        if (this.isRetrievalInProgress && stage !== 2) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Metadata Retrieval in Progress',
                    message:
                        'Please wait until metadata retrieval finishes before navigating to another stage.',
                    variant: 'info',
                    mode: 'dismissable'
                })
            );
            return;
        }

        if (stage === 4 && !this.canOpenStage4) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Deployment Plan Required',
                    message:
                        'Please create a Deployment Plan from the Metadata Comparison stage before continuing.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.activeLifecycleStage = stage;

        if (stage === 1) {
            this.openStage1Modal();
        } else if (stage === 2) {
            this.openStage2Modal();
        } else if (stage === 3) {
            this.openStage3Modal();
        }
    }
    // ────────────────────────────────────────────────────────────────────


    // ─── PHASE 2: Lifecycle Stage State Getters ──────────────────────────
    // All derived from existing state — no new Apex, no mutations.

    // Stage 1 active when a comparison is loaded
    get stage1Active() {
        return !!this.selectedComparisonDetails;
    }

    // Stage 1 complete when comparison details are loaded (orgs are identified)
    get stage1Complete() {
        return !!this.selectedComparisonDetails;
    }

    // Stage 2 active when stage 1 is complete
    get stage2Active() {
        return this.stage1Complete;
    }

    // Stage 2 complete when both orgs retrieved
    get stage2Complete() {
        return this.sourceMigrationCompleted && this.destinationMigrationCompleted;
    }

    // Stage 3 active when both orgs have been retrieved (stage 2 complete)
    get stage3Active() {
        return this.stage2Complete;
    }

    // Stage 3 complete when compare has been run
    get stage3Complete() {
        return this.compareCompleted;
    }

    // Stage 4: workflow progress from deployment plan existence (not active workspace)
    get stage4Active() {
        return this.canOpenStage4;
    }

    // Stage 4 COMPLETE when Source Validation Overall + Quality Gate PASS
    get stage4Complete() {
        return this.canOpenStage5;
    }

    // Stage 5 READY when Stage 4 source validation has passed
    get stage5Active() {
        return this.canOpenStage5;
    }

    get stage5Complete() {
        return false;
    }

    get stage6Active() {
        return this.activeLifecycleStage === 6;
    }

    get stage6Complete() {
        return false;
    }

   

    // Stage disabled flags (for button disabled attribute)
    // Stages 1–3 unchanged except temporary retrieval lock on non–Stage 2 nodes.
    get stage1Disabled() {
        return !this.stage1Active || this.isRetrievalInProgress;
    }
    get stage2Disabled() { return !this.stage2Active; }
    get stage3Disabled() {
        return !this.stage3Active || this.isRetrievalInProgress;
    }
    get stage4Disabled() { return this.isRetrievalInProgress; }
    get stage5Disabled() { return this.isRetrievalInProgress; }
    get stage6Disabled() { return this.isRetrievalInProgress; }
    

    // Stage CSS classes — drives active / complete / idle appearance
    get stage1Class() { return this._stageClass(this.stage1Active, this.stage1Complete); }
    get stage2Class() { return this._stageClass(this.stage2Active, this.stage2Complete); }
    get stage3Class() { return this._stageClass(this.stage3Active, this.stage3Complete); }
    get stage4Class() { return this._stageClass(this.stage4Active, this.stage4Complete); }
    get stage5Class() { return this._stageClass(this.stage5Active, this.stage5Complete); }
    get stage6Class() { return this._stageClass(this.stage6Active, this.stage6Complete); }
    

    _stageClass(active, complete) {
        if (complete) return 'lc-node lc-node--complete';
        if (active)   return 'lc-node lc-node--active';
        return 'lc-node lc-node--idle';
    }

    // Stage status label text
    get stage1StatusLabel() {
        if (this.stage1Complete) return 'Connected';
        if (this.stage1Active)   return 'Ready';
        return 'Pending';
    }

    get stage2StatusLabel() {
        if (this.stage2Complete) return 'Retrieved';
        if (this.stage2Active)   return 'In Progress';
        return 'Pending';
    }

    get stage3StatusLabel() {
        if (this.stage3Complete) return 'Complete';
        if (this.stage3Active)   return 'Ready';
        return 'Pending';
    }

    get stage4StatusLabel() {
        if (this.stage4Complete) return 'Complete';
        if (this.stage4Active)   return 'Ready';
        return 'Pending';
    }

    get stage5StatusLabel() {
        if (this.stage5Complete) return 'Complete';
        if (this.stage5Active)   return 'Ready';
        return 'Pending';
    }

    get stage6StatusLabel() {
        if (this.stage6Complete) return 'Complete';
        if (this.stage6Active)   return 'Ready';
        return 'Pending';
    }

    

    // Stage status pill CSS classes
    get stage1StatusClass() { return this._statusClass(this.stage1Active, this.stage1Complete); }
    get stage2StatusClass() { return this._statusClass(this.stage2Active, this.stage2Complete); }
    get stage3StatusClass() { return this._statusClass(this.stage3Active, this.stage3Complete); }
    get stage4StatusClass() { return this._statusClass(this.stage4Active, this.stage4Complete); }
    get stage5StatusClass() { return this._statusClass(this.stage5Active, this.stage5Complete); }
    get stage6StatusClass() { return this._statusClass(this.stage6Active, this.stage6Complete); }
    

    _statusClass(active, complete) {
        if (complete) return 'lc-node-status lc-status--complete';
        if (active)   return 'lc-node-status lc-status--active';
        return 'lc-node-status lc-status--idle';
    }

    // Connector CSS — lights up when the downstream stage is active
    get connector1Class() {
        return this.stage2Active
            ? 'lc-connector lc-connector--active'
            : 'lc-connector';
    }

    get connector2Class() {
        return this.stage3Active
            ? 'lc-connector lc-connector--active'
            : 'lc-connector';
    }

    get connector3Class() {
        return this.stage4Active
            ? 'lc-connector lc-connector--active'
            : 'lc-connector';
    }

    get connector4Class() {
        return this.stage5Active
            ? 'lc-connector lc-connector--active'
            : 'lc-connector';
    }

    get connector5Class() {
        return this.stage6Active
            ? 'lc-connector lc-connector--active'
            : 'lc-connector';
    }

    
    // ────────────────────────────────────────────────────────────────────


    // ─── UI-ONLY: Lifecycle header badges ─────────────────────────────────
    // Purely derived from the stage completion getters and activeLifecycleStage
    // already defined above. No new state, no backend calls, no business logic.
    get completedStageCount() {
        return [
            this.stage1Complete,
            this.stage2Complete,
            this.stage3Complete,
            this.stage4Complete,
            this.stage5Complete,
            this.stage6Complete
        ].filter(Boolean).length;
    }

    get lifecycleCompletionPercent() {
        return Math.round((this.completedStageCount / 6) * 100);
    }

    get lifecycleCompletionLabel() {
        return `${this.lifecycleCompletionPercent}% Complete`;
    }

    get lifecyclePhaseLabel() {
        return `Phase ${this.activeLifecycleStage} Active`;
    }
    // ────────────────────────────────────────────────────────────────────


    // ═══════════════════════════════════════════════════════════════════
    // ALL EXISTING PROPERTIES AND METHODS BELOW — UNCHANGED
    // ═══════════════════════════════════════════════════════════════════

    @track orgOptions = [];

    @track responseMessage;

    selectedOrg;

    githubUrl = '';

    githubToken = '';

    environment = 'Production';

    orgDisplayName = '';

    comparisonName = '';

    sourceOrgId;

    destinationOrgId;

    comparisonOptions = [];

    selectedComparison;

    wiredComparisonResult;

    selectedComparisonDetails;

    sourceOrgName = '';

    destinationOrgName = '';

    sourceBranch = '';

    destinationBranch = '';

    backendStatus = '';

    sourceMigrationCompleted = false;

    destinationMigrationCompleted = false;

    showCompareButton = false;

    sourceStatusMessage = '';

    destinationStatusMessage = '';

    differentFiles = [];

    isComparing = false;

    groupedComparisonResults = [];

    savedComparisonResults = [];

    /** Deploy / Ignore / Clear Selection (UI-only clear — not a persisted picklist value) */
    deploymentIntentOptions = [
        { label: 'Deploy', value: 'Deploy' },
        { label: 'Ignore', value: 'Ignore' },
        { label: 'Clear Selection', value: '__CLEAR__' }
    ];

    showFileDetailsModal = false;

    selectedFile = null;

    showDiffModal = false;

    diffContent = '';

    differenceReport = null;

    showRawDiff = false;

    formattedDiff = [];

    isLoadingDiff = false;

    searchKeyword = '';

    /** Presentation-only Comparison Summary filters (do not mutate working copy). */
    filterDeploymentIntent = 'ALL';
    filterChangeType = 'ALL';
    filterMetadataType = 'ALL';

    deploymentIntentFilterOptions = [
        { label: 'All', value: 'ALL' },
        { label: 'Deploy', value: 'Deploy' },
        { label: 'Ignore', value: 'Ignore' },
        { label: 'No Selection', value: 'No Selection' }
    ];

    changeTypeFilterOptions = [
        { label: 'All', value: 'ALL' },
        { label: 'New', value: 'NEW' },
        { label: 'Modified', value: 'MODIFIED' },
        { label: 'Deleted', value: 'DELETED' }
    ];

    /**
     * Presentation-only — Metadata Type options from current comparison data.
     * Labels include counts from savedComparisonResults.
     */
    get metadataTypeFilterOptions() {
        const counts = {};
        const records = this.savedComparisonResults || [];

        records.forEach((record) => {
            const type = this._resolveDisplayGroupType(record);
            if (!type) {
                return;
            }
            counts[type] = (counts[type] || 0) + 1;
        });

        const total = records.length;
        const typeOptions = Object.keys(counts)
            .sort((a, b) => a.localeCompare(b))
            .map((type) => ({
                label: `${type} (${counts[type]})`,
                value: type
            }));

        return [
            { label: `All (${total})`, value: 'ALL' },
            ...typeOptions
        ];
    }

    aiSummary;

    isGeneratingSummary = false;

    formattedAiSummary = '';

    aiExplanation = '';

    aiProviderName = '';

    /** Presentation-only — collapse state for AI executive report. */
    isAiSummaryReportExpanded = true;

    isGeneratingExplanation = false;

    selectedModel = 'gemini';

    compareCompleted = false;

    isNewComparisonModalOpen = false;

    isConnectOrgModalOpen = false;

    statusPollingInterval;

    activeMigrationType;

    isSourceRetrievalRunning = false;

    isDestinationRetrievalRunning = false;

    /** Bound reference for window beforeunload while retrieval is active. */
    _retrievalBeforeUnloadHandler;

    /**
     * Presentation lock — derived from existing retrieval running flags only.
     */
    get isRetrievalInProgress() {
        return (
            this.isSourceRetrievalRunning === true ||
            this.isDestinationRetrievalRunning === true
        );
    }

    get isComparisonSelectorDisabled() {
        return this.isRetrievalInProgress;
    }

    get isNewComparisonDisabled() {
        return this.isRetrievalInProgress;
    }

    get isConnectOrgDisabled() {
        return this.isRetrievalInProgress;
    }

    get isStage2CloseDisabled() {
        return this.isRetrievalInProgress;
    }


    @wire(getConnectedOrgs)
    wiredOrgs(result) {
        this.wiredOrgResult = result;
        const { data, error } = result;
        if (data) {
            this.orgOptions = data.map(org => {
                return {
                    label: org.Display_Name__c,
                    value: org.Id
                };
            });
        }
        if (error) {
            console.error(error);
        }
    }

    handleOrgChange(event) {
        this.selectedOrg = event.detail.value;
    }

    handleGithubRepoChange(event) {
        this.githubUrl = event.target.value;
    }

    handleGithubTokenChange(event) {
        this.githubToken = event.target.value;
    }

    handleOrgDisplayNameChange(event) {
        this.orgDisplayName = event.target.value;
    }

    handleComparisonNameChange(event) {
        this.comparisonName = event.target.value;
    }

    handleSourceOrgChange(event) {
        this.sourceOrgId = event.detail.value;
    }

    handleDestinationOrgChange(event) {
        this.destinationOrgId = event.detail.value;
    }

    handleStartMigration() {
        if (!this.selectedOrg) {
            alert('Please select an Org');
            return;
        }
        if (!this.githubUrl) {
            alert('Please enter GitHub Repository URL');
            return;
        }
        getOrgDetails({
            orgRecordId: this.selectedOrg
        })
        .then(orgDetails => {
            console.log('Org Details:', JSON.stringify(orgDetails));
            return startMigration({
                refreshToken: orgDetails.Refresh_Token__c,
                instanceUrl: orgDetails.Instance_URL__c,
                repoUrl: this.githubUrl
            });
        })
        .then(result => {
            console.log('Migration Response:', result);
            this.responseMessage = result;
        })
        .catch(error => {
            console.error(error);
            this.responseMessage = JSON.stringify(error);
        });
    }

    checkConnection() {
        checkBackendConnection()
            .then(result => {
                const response = JSON.parse(result);
                this.backendStatus = response.success ? 'Connected' : 'Disconnected';
            })
            .catch(() => {
                this.backendStatus = 'Disconnected';
            });
    }

    connectNewOrg() {
        if (!this.orgDisplayName) {
            alert('Please enter Connected Org Name');
            return;
        }
        localStorage.setItem('orgDisplayName', this.orgDisplayName);
        localStorage.setItem('orgEnvironment', this.environment);
        sessionStorage.removeItem('oauthSaved');
        getOAuthUrl({
            environment: this.environment
        })
        .then(result => {
            const response = JSON.parse(result);
            window.open(response.authUrl, '_self');
        })
        .catch(error => {
            console.error(error);
        });
    }

    saveLatestOAuthOrg() {
        getLatestOAuthResult()
            .then(result => {
                const response = JSON.parse(result);
                console.log('Display Name = ', this.orgDisplayName);
                return saveConnectedOrg({
                    orgId: response.data.orgId,
                    instanceUrl: response.data.instanceUrl,
                    refreshToken: response.data.refreshToken,
                    displayName: localStorage.getItem('orgDisplayName')
                });
            })
            .then(() => {
                alert('Connected Org Saved Successfully');
            })
            .catch(error => {
                console.error(error);
            });
    }

    get environmentOptions() {
        return [
            { label: 'Production', value: 'Production' },
            { label: 'Sandbox',    value: 'Sandbox' }
        ];
    }

    handleEnvironmentChange(event) {
        this.environment = event.detail.value;
    }

    connectedCallback() {
        const displayName = localStorage.getItem('orgDisplayName');
        if (displayName && !sessionStorage.getItem('oauthSaved')) {
            this.orgDisplayName = displayName;
            this.autoSaveOAuthOrg();
        }
    }

    disconnectedCallback() {
        this.stopValidationPolling();
        this._clearRetrievalBeforeUnloadGuard();
    }

    _boundRetrievalBeforeUnload(event) {
        if (!this.isRetrievalInProgress) {
            return;
        }
        event.preventDefault();
        // Modern browsers show a generic confirmation; returnValue is required.
        event.returnValue = '';
    }

    _ensureRetrievalBeforeUnloadGuard() {
        if (this._retrievalBeforeUnloadHandler) {
            return;
        }
        this._retrievalBeforeUnloadHandler =
            this._boundRetrievalBeforeUnload.bind(this);
        window.addEventListener(
            'beforeunload',
            this._retrievalBeforeUnloadHandler
        );
    }

    _clearRetrievalBeforeUnloadGuard() {
        if (!this._retrievalBeforeUnloadHandler) {
            return;
        }
        window.removeEventListener(
            'beforeunload',
            this._retrievalBeforeUnloadHandler
        );
        this._retrievalBeforeUnloadHandler = null;
    }

    _markRetrievalRunning(type) {
        if (type === 'Source') {
            this.isSourceRetrievalRunning = true;
        } else if (type === 'Destination') {
            this.isDestinationRetrievalRunning = true;
        }
        this._ensureRetrievalBeforeUnloadGuard();
    }

    _clearRetrievalRunningFlags() {
        this.isSourceRetrievalRunning = false;
        this.isDestinationRetrievalRunning = false;
        this._clearRetrievalBeforeUnloadGuard();
    }

    autoSaveOAuthOrg() {
        getLatestOAuthResult()
            .then(result => {
                const response = JSON.parse(result);
                return saveConnectedOrg({
                    orgId: response.data.orgId,
                    instanceUrl: response.data.instanceUrl,
                    refreshToken: response.data.refreshToken,
                    displayName: localStorage.getItem('orgDisplayName')
                });
            })
            .then(() => {
                sessionStorage.setItem('oauthSaved', 'true');
                refreshApex(this.wiredOrgResult);
                alert('Org Connected Successfully');
                localStorage.removeItem('orgDisplayName');
                localStorage.removeItem('orgEnvironment');
            })
            .catch(error => {
                console.error(error);
            });
    }

    // Metadata Comparison Methods

    @wire(getComparisons)
    wiredComparisons(result) {
        this.wiredComparisonResult = result;
        const { data, error } = result;
        if (data) {
            this.comparisonOptions = data.map(comp => {
                return {
                    label: comp.Name,
                    value: comp.Id
                };
            });
        }
        if (error) {
            console.error(error);
        }
    }

    handleComparisonChange(event) {
        if (this.isRetrievalInProgress) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Metadata Retrieval in Progress',
                    message:
                        'Please wait until metadata retrieval finishes before switching comparisons.',
                    variant: 'info',
                    mode: 'dismissable'
                })
            );
            return;
        }

        this.selectedComparison = event.detail.value;
        this.compareCompleted = false;

        // CHANGE 3 — Clear stale AI state when switching comparisons
        this.aiSummary = '';
        this.formattedAiSummary = '';
        this.aiExplanation = '';
        this.aiProviderName = '';
        this.isGeneratingSummary = false;
        this.isGeneratingExplanation = false;

        // Comparison-scoped lifecycle: clear Stage 4–6 session state from prior comparison
        this._resetStage4To6SessionState();

        getComparisonDetails({
            comparisonId: this.selectedComparison
        })
        .then(result => {
            this.selectedComparisonDetails = result;
            this.sourceOrgName = result.Source_Org__r.Name;
            this.destinationOrgName = result.Destination_Org__r.Name;
            this.sourceBranch = result.Source_Branch__c || '';
            this.destinationBranch = result.Destination_Branch__c || '';
            this.sourceMigrationCompleted = result.Source_Status__c === 'Metadata Pushed';
            this.destinationMigrationCompleted = result.Destination_Status__c === 'Metadata Pushed';
            this.sourceStatusMessage = result.Source_Status__c;
            this.destinationStatusMessage = result.Destination_Status__c;
            this.showCompareButton = result.Comparison_Status__c === 'Metadata Pushed';

            // CHANGE 4 — Restore compareCompleted from Salesforce data (survives refresh)
            // 'Comparison Complete' is written to Comparison_Status__c by saveComparisonResults
            // If results already exist on this record, the button must remain disabled.
            if (result.Comparison_Status__c === 'Comparison Complete') {
                this.compareCompleted = true;
                this.showCompareButton = true; // keep the action area visible
            }

            this.loadSavedComparisonResults();

            // Reload durable Deployment Plan for this comparison only (no create/update)
            return this._loadDeploymentPlanForComparison(this.selectedComparison);
        })
        .catch(error => {
            console.error(error);
        });
    }

    /**
     * Clears Stage 4–6 session-only workflow state so it cannot leak across comparisons.
     * Lands the rail on Stage 3 (Metadata Comparison) for the newly selected comparison.
     */
    _resetStage4To6SessionState() {
        this.currentDeploymentPlanId = null;
        this.showDeploymentReview = false;
        this.deploymentReviewData = null;
        this.deploymentReviewItems = [];
        this.selectedTestClasses = {};
        this.isLoadingDeploymentReview = false;

        this.sourceValidationData = null;
        this.sourceValidationDisplayItems = [];
        this.isLoadingSourceValidation = false;

        this.deploymentValidationData = null;
        this.deploymentValidationDisplay = null;
        this.deploymentEnterpriseReport = null;
        this.deploymentFailureClassification = null;
        this.deploymentResolutionReport = null;
        this.deploymentAutoFixReport = null;
        this.deploymentAutoValidationReport = null;
        this.deploymentAiResolutionReport = null;
        this.deploymentSafeSkipReport = null;
        this.deploymentOnDemandAiResolution = null;
        this.deploymentOnDemandAiDisplay = null;
        this.onDemandAiErrorMessage = null;
        this.isResolvingWithAi = false;
        this.backendValidationHistoryId = null;
        this.showSupportBundleModal = false;
        this.supportBundleGenerating = false;
        this.supportBundleReady = false;
        this.supportBundleError = null;
        this.supportBundle = null;
        this.supportBundleId = null;
        this.supportBundleFilename = null;
        this.deploymentIntelligenceDisplay = null;
        this.deploymentReadinessReport = null;
        this.deploymentPackageProvenance = null;
        this.ignoredAutoIncludedMetadata = [];
        this.showIgnoredAutoIncludedModal = false;
        this.stopValidationPolling();
        this.isLoadingDeploymentValidation = false;
        this.activeValidationId = null;
        this.validationStatusMessage = '';
        this._validationComparisonId = null;

        this.deploymentPlannerSelections = {};
        this.plannerRows = [];

        this.aiAdvisorData = null;
        this.aiAdvisorDisplay = null;
        this.aiAdvisorUnavailableMessage = null;
        this.isLoadingAiAdvisor = false;
        this.showAiAdvisorDiagnostics = false;

        this.deployCompleted = false;
        this.isDeploying = false;
        this.showDeployConfirmation = false;
        this.historyRecordId = null;

        this.ignoredConflicts = [];
        this.hasIgnoredDependencyConflict = false;
        this.showIgnoredDependencyModal = false;
        this.isIncludingRequiredMetadata = false;

        // Presentation-only Comparison Summary filters
        this.filterDeploymentIntent = 'ALL';
        this.filterChangeType = 'ALL';
        this.filterMetadataType = 'ALL';

        this.activeLifecycleStage = 3;
    }

    /**
     * Restores currentDeploymentPlanId and Stage 4/5 snapshots for the selected comparison.
     * Active plan rule: latest CreatedDate for that comparison only.
     * Hydration is read-only — no Review/Validate/Deploy callouts, no re-persist.
     */
    _loadDeploymentPlanForComparison(comparisonId) {
        if (!comparisonId) {
            this.currentDeploymentPlanId = null;
            this.showDeploymentReview = false;
            return Promise.resolve(null);
        }

        const loadComparisonId = comparisonId;

        return getLatestDeploymentPlanState({ comparisonId: loadComparisonId })
            .then(state => {
                // Discard stale plan-state if comparison changed mid-flight
                if (this.selectedComparison !== loadComparisonId) {
                    return null;
                }

                const planId = state?.deploymentPlanId || null;
                this.currentDeploymentPlanId = planId;
                this.showDeploymentReview = !!planId;

                if (!planId) {
                    this._deriveLifecycleStageFromPlanSnapshots();
                    return null;
                }

                this._hydrateDeploymentPlanSnapshots(state, loadComparisonId);
                return planId;
            })
            .catch(error => {
                console.error(error);
                if (this.selectedComparison !== loadComparisonId) {
                    return null;
                }
                // Fallback: restore plan Id only (pre-snapshot behavior)
                return getLatestDeploymentPlanId({
                    comparisonId: loadComparisonId
                })
                    .then(planId => {
                        if (this.selectedComparison !== loadComparisonId) {
                            return null;
                        }
                        this.currentDeploymentPlanId = planId || null;
                        this.showDeploymentReview = !!planId;
                        this._deriveLifecycleStageFromPlanSnapshots();
                        return planId;
                    })
                    .catch(fallbackError => {
                        console.error(fallbackError);
                        if (this.selectedComparison !== loadComparisonId) {
                            return null;
                        }
                        this.currentDeploymentPlanId = null;
                        this.showDeploymentReview = false;
                        return null;
                    });
            });
    }

    /**
     * Apply persisted Stage 4/5 snapshots for one comparison/plan state.
     * Independent hydration — missing snapshots stay empty.
     */
    _hydrateDeploymentPlanSnapshots(state, comparisonId) {
        if (!state || this.selectedComparison !== comparisonId) {
            return;
        }

        if (state.latestReviewJson) {
            try {
                const reviewData = JSON.parse(state.latestReviewJson);
                this.deploymentReviewData = reviewData;
                const items = this._buildDeploymentReviewItems(reviewData);
                this.deploymentReviewItems = items;
                this._initializeSelectedTestClasses(items);
                this._detectIgnoredDependencyConflicts();
                // Hydration must not reopen informational modals
                this.showIgnoredDependencyModal = false;
            } catch (error) {
                console.error('Failed to hydrate Review snapshot', error);
                this.deploymentReviewData = null;
                this.deploymentReviewItems = [];
                this.selectedTestClasses = {};
            }
        }

        if (state.latestSourceValidationJson) {
            try {
                this.sourceValidationData = JSON.parse(
                    state.latestSourceValidationJson
                );
                this.sourceValidationDisplayItems =
                    this._buildSourceValidationDisplayItems(
                        this.sourceValidationData
                    );
            } catch (error) {
                console.error(
                    'Failed to hydrate Source Validation snapshot',
                    error
                );
                this.sourceValidationData = null;
                this.sourceValidationDisplayItems = [];
            }
        }

        if (state.latestDeploymentValidationJson) {
            try {
                const validationData = JSON.parse(
                    state.latestDeploymentValidationJson
                );
                this._hydrateDeploymentValidationUiState(validationData);
            } catch (error) {
                console.error(
                    'Failed to hydrate Deployment Validation snapshot',
                    error
                );
            }
        }

        if (this.selectedComparison === comparisonId) {
            this._deriveLifecycleStageFromPlanSnapshots();
        }
    }

    /**
     * Derive active workspace from persisted business snapshots (not a stored stage number).
     */
    _deriveLifecycleStageFromPlanSnapshots() {
        if (!this.currentDeploymentPlanId) {
            this.activeLifecycleStage = 3;
            return;
        }

        // Deployment Validation present, or Source Validation PASS → Stage 5
        if (
            this.deploymentValidationData ||
            this.overallSourceValidationStatus === 'PASS'
        ) {
            this.activeLifecycleStage = 5;
            return;
        }

        // Plan exists (with or without Review) → Stage 4 shell/content
        this.activeLifecycleStage = 4;
    }

    /**
     * Clears Stage 4–5 snapshot UI for a newly created plan (same comparison).
     * Does not clear comparison results or change the latest-plan rule.
     */
    _clearStage4To5SnapshotSessionState() {
        this.deploymentReviewData = null;
        this.deploymentReviewItems = [];
        this.selectedTestClasses = {};
        this.ignoredConflicts = [];
        this.hasIgnoredDependencyConflict = false;
        this.showIgnoredDependencyModal = false;
        this.isLoadingDeploymentReview = false;

        this.sourceValidationData = null;
        this.sourceValidationDisplayItems = [];
        this.isLoadingSourceValidation = false;

        this._clearFailedValidationUiState();
        this.stopValidationPolling();
        this.isLoadingDeploymentValidation = false;
        this.activeValidationId = null;
        this.validationStatusMessage = '';
        this._validationComparisonId = null;
    }

    _persistPlanSnapshot(saveFn, payload, label) {
        if (!this.currentDeploymentPlanId) {
            return;
        }

        // Length only — never log snapshot body / secrets.
        const jsonValue =
            payload?.reviewJson ||
            payload?.sourceValidationJson ||
            payload?.deploymentValidationJson ||
            '';
        if (typeof jsonValue === 'string' && jsonValue.length > 0) {
            // eslint-disable-next-line no-console
            console.info(
                label + ' snapshot charLength=' + jsonValue.length
            );
        }

        saveFn(payload)
            .then(result => {
                if (result && result.success === true) {
                    return;
                }
                console.error(
                    label + ' snapshot save failed:',
                    result ? result.message : 'Unknown error'
                );
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Warning',
                        message:
                            label +
                            ' completed, but could not be saved for restore after refresh.',
                        variant: 'warning',
                        mode: 'dismissable'
                    })
                );
            })
            .catch(error => {
                console.error(label + ' snapshot save error:', error);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Warning',
                        message:
                            label +
                            ' completed, but could not be saved for restore after refresh.',
                        variant: 'warning',
                        mode: 'dismissable'
                    })
                );
            });
    }

    _resolveReviewSnapshotStatus(reviewData) {
        if (!reviewData || typeof reviewData !== 'object') {
            return 'COMPLETED';
        }
        if (reviewData.overallStatus) {
            return String(reviewData.overallStatus);
        }
        if (reviewData.status) {
            return String(reviewData.status);
        }
        const items = Array.isArray(reviewData.deploymentReview)
            ? reviewData.deploymentReview
            : [];
        if (items.length && items[0].status) {
            return String(items[0].status);
        }
        return 'COMPLETED';
    }

    _resolveDeploymentValidationSnapshotStatus(validationData) {
        const readiness =
            validationData?.deploymentReadiness ||
            validationData?.deploymentReadinessAnalysis ||
            {};
        return (
            readiness.overallStatus ||
            validationData?.overallStatus ||
            validationData?.status ||
            'COMPLETED'
        );
    }

    handleSourceBranchChange(event) {
        this.sourceBranch = event.target.value;
    }

    handleDestinationBranchChange(event) {
        this.destinationBranch = event.target.value;
    }

    handleSourceMigration() {
        if (!this.sourceBranch) {
            alert('Please enter Source Branch');
            return;
        }

        this._markRetrievalRunning('Source');


        startComparisonMigration({
            refreshToken: this.selectedComparisonDetails.Source_Org__r.Refresh_Token__c,
            instanceUrl: this.selectedComparisonDetails.Source_Org__r.Instance_URL__c,
            branchName: this.sourceBranch
        })
        .then(result => {
            //return updateMigrationStatus({
                //comparisonId: this.selectedComparison,
              //  branchName: this.sourceBranch,
               // migrationType: 'Source'
            //});
        })
        .then(() => {

    this.activeMigrationType = 'Source';
    

    this.sourceStatusMessage = 'Starting...';



    this.statusPollingInterval =
        setInterval(() => {

            this.checkMigrationStatus();

        }, 5000);

    console.log(
        'Source Updated',
        this.sourceMigrationCompleted,
        this.sourceStatusMessage
    );

})
        .catch(error => {
            console.error(error);
            this._clearRetrievalRunningFlags();
            alert(JSON.stringify(error));
        });
    }

    handleDestinationMigration() {
        if (!this.destinationBranch) {
            alert('Please enter Destination Branch');
            return;
        }
        this._markRetrievalRunning('Destination');
        startComparisonMigration({
            refreshToken: this.selectedComparisonDetails.Destination_Org__r.Refresh_Token__c,
            instanceUrl: this.selectedComparisonDetails.Destination_Org__r.Instance_URL__c,
            branchName: this.destinationBranch
        })
        .then(result => {
            //return updateMigrationStatus({
              //  comparisonId: this.selectedComparison,
                //branchName: this.destinationBranch,
                //migrationType: 'Destination'
            //});
        })
        .then(() => {
    this.activeMigrationType = 'Destination';

    this.destinationStatusMessage = 'Starting...';

    this.statusPollingInterval =
        setInterval(() => {

            this.checkMigrationStatus();

        }, 5000);

    console.log(
        'Destination Updated',
        this.destinationMigrationCompleted,
        this.destinationStatusMessage
    );

})
        .catch(error => {
            console.error(error);
            this._clearRetrievalRunningFlags();
            alert(JSON.stringify(error));
        });
    }

    refreshComparisonDetails() {
        getComparisonDetails({
            comparisonId: this.selectedComparison
        })
        .then(result => {

            console.log(
            'Source Status Before Refresh:',
            this.sourceStatusMessage
        );

        console.log(
            'Destination Status Before Refresh:',
            this.destinationStatusMessage
        );

            console.log('Source Status From SF:', result.Source_Status__c);
            console.log('Destination Status From SF:', result.Destination_Status__c);
            console.log('Comparison Status From SF:', result.Comparison_Status__c);
            this.selectedComparisonDetails = result;
            this.sourceBranch = result.Source_Branch__c || '';
            this.destinationBranch = result.Destination_Branch__c || '';
            this.sourceMigrationCompleted = result.Source_Status__c === 'Metadata Pushed';
            this.destinationMigrationCompleted = result.Destination_Status__c === 'Metadata Pushed';
            this.sourceStatusMessage = result.Source_Status__c || '';
            this.destinationStatusMessage = result.Destination_Status__c || '';
            this.showCompareButton = result.Comparison_Status__c === 'Metadata Pushed';
        })
        .catch(error => {
            console.error(error);
        });
    }

    handleCompare() {
        this.isComparing = true;
        compareBranches({
            sourceBranch: this.sourceBranch,
            destinationBranch: this.destinationBranch
        })
        .then(result => {
            const response = JSON.parse(result);
            console.log('Compare Result:', response);
            if (response.success) {
                this.differentFiles = response.files || [];
                console.log('Selected Comparison:', this.selectedComparison);
                saveComparisonResults({
                    comparisonId: this.selectedComparison,
                    files: this.differentFiles
                })
                .then(() => {
                    console.log('Comparison results saved');
                    this.loadSavedComparisonResults();
                    this.compareCompleted = true;
                    this.isComparing = false;
                })
                .catch(error => {
                    this.isComparing = false;
                    console.error('SAVE ERROR', JSON.stringify(error));
                    alert(JSON.stringify(error));
                });
            } else {
                alert(response.error);
            }
        })
        .catch(error => {
            this.isComparing = false;
            console.error(error);
            alert('Comparison Failed');
        });
    }

    loadSavedComparisonResults() {
        if (!this.selectedComparison) {
            return Promise.resolve();
        }
        return getComparisonResults({
            comparisonId: this.selectedComparison
        })
        .then(result => {
            this.savedComparisonResults = result;
            console.log('Saved Results:', result.length);
            this.buildGroupedResults();
            console.log('First Record:', JSON.stringify(result[0]));

            // Phase 4 — close ignored-dependency popup on comparison refresh
            // so it cannot linger from a prior Review / stale session.
            this.showIgnoredDependencyModal = false;
            // Stage 5 info popup — same refresh lifecycle
            this.showIgnoredAutoIncludedModal = false;

            // CHANGE 4 — If saved results exist, comparison already ran; keep button disabled
            if (result && result.length > 0) {
                this.compareCompleted = true;
            }
        })
        .catch(error => {
            console.error('Load Results Error', error);
            this.showIgnoredDependencyModal = false;
            this.showIgnoredAutoIncludedModal = false;
            throw error;
        });
    }

    buildGroupedResults() {

        const expandedStates = {};

this.groupedComparisonResults.forEach(group => {
    expandedStates[group.type] = group.expanded;
});


        const grouped = {};
        this.savedComparisonResults.forEach(record => {
            if (
                this.searchKeyword &&
                !record.File_Name__c.toLowerCase().includes(this.searchKeyword)
            ) {
                return;
            }

            // Presentation-only filters (AND with Search). Do not mutate savedComparisonResults.
            if (
                !this._recordMatchesComparisonSummaryFilters(record)
            ) {
                return;
            }

            const type = this._resolveDisplayGroupType(record);
            if (!grouped[type]) {
                grouped[type] = {
    type: type,
    count: 0,
    expanded: expandedStates[type] || false,
    files: []
};
            }
            grouped[type].count++;
            grouped[type].files.push({
    ...record,
    Deployment_Intent__c: this._resolveDeploymentIntent(record),
    Selected_For_Deployment__c:
        this._resolveDeploymentIntent(record) === 'Deploy',
    badgeClass: this.getBadgeClass(record.Change_Type__c),
    flowStatus: record.Flow_Status__c
});
        });
        
        const groupedResults =
        Object.values(grouped);

groupedResults.forEach(group => {

    if (group.type === 'CustomObject') {

        group.objectGroups =
            this.groupCustomObjectFiles(
                group.files
            );

    }

    if (group.type === 'Flow') {

        group.flowGroups =
            this.groupFlowFiles(
                group.files
            );

    }

    if (group.type === 'LWC') {

        group.lwcGroups =
            this.groupLwcFiles(
                group.files
            );

    }

});

this.groupedComparisonResults =
    groupedResults;

console.log(
    'Grouped Results:',
    this.groupedComparisonResults
);

console.log(
    JSON.stringify(
        this.groupedComparisonResults
    )
);

    }


    _resolveDisplayGroupType(record) {

        const storedType = record.Metadata_Type__c;

        if (storedType && storedType !== 'Other') {
            return storedType;
        }

        const filePath = record.File_Path__c || '';
        const fileName = record.File_Name__c || '';

        if (
            filePath.includes('/namedCredentials/') ||
            fileName.endsWith('.namedCredential-meta.xml')
        ) {
            return 'NamedCredential';
        }

        if (
            filePath.includes('/labels/') ||
            fileName.endsWith('.labels-meta.xml')
        ) {
            return 'CustomLabel';
        }

        if (
            filePath.includes('/customMetadata/') ||
            fileName.endsWith('.md-meta.xml')
        ) {
            return 'CustomMetadata';
        }

        return storedType || 'Other';

    }


    getBadgeClass(changeType) {
        switch (changeType) {
            case 'NEW':      return 'badge-new';
            case 'MODIFIED': return 'badge-modified';
            case 'DELETED':  return 'badge-deleted';
            default:         return 'badge-default';
        }
    }

    toggleGroup(event) {
        const selectedType = event.currentTarget.dataset.type;
        this.groupedComparisonResults = this.groupedComparisonResults.map(group => {
            if (group.type === selectedType) {
                return { ...group, expanded: !group.expanded };
            }
            return group;
        });
    }


    toggleObjectGroup(event) {

    const metadataType =
        event.currentTarget.dataset.type;

    const objectName =
        event.currentTarget.dataset.object;

    this.groupedComparisonResults =
        this.groupedComparisonResults.map(group => {

            if (
                group.type === metadataType &&
                group.objectGroups
            ) {

                group.objectGroups =
                    group.objectGroups.map(obj => {

                        if (
                            obj.objectName ===
                            objectName
                        ) {

                            return {
                                ...obj,
                                expanded:
                                    !obj.expanded
                            };

                        }

                        return obj;

                    });

            }

            return { ...group };

        });

}

toggleMetadataGroup(event) {

    const metadataType =
        event.currentTarget.dataset.type;

    const objectName =
        event.currentTarget.dataset.object;

    const categoryName =
        event.currentTarget.dataset.category;

    this.groupedComparisonResults =
        this.groupedComparisonResults.map(group => {

            if (
                group.type === metadataType &&
                group.objectGroups
            ) {

                group.objectGroups =
                    group.objectGroups.map(obj => {

                        if (
                            obj.objectName ===
                            objectName
                        ) {

                            obj.metadataGroups =
                                obj.metadataGroups.map(cat => {

                                    if (
                                        cat.categoryName ===
                                        categoryName
                                    ) {

                                        return {
                                            ...cat,
                                            expanded:
                                                !cat.expanded
                                        };

                                    }

                                    return cat;

                                });

                        }

                        return {
                            ...obj
                        };

                    });

            }

            return {
                ...group
            };

        });

}

    handleFileClick(event) {
        const fileId = event.currentTarget.dataset.id;
        this.selectedFile = this.savedComparisonResults.find(file => file.Id === fileId);
        this.differenceReport = null;
        this.showRawDiff = false;
        this.handleViewDifference();
    }

    closeFileDetailsModal() {
        this.showFileDetailsModal = false;
        this.selectedFile = null;
    }

    handleViewDifference() {
        this.aiExplanation = '';
        this.isLoadingDiff = true;
        getDifferenceReport({
            sourceBranch: this.sourceBranch,
            destinationBranch: this.destinationBranch,
            filePath: this.selectedFile.File_Path__c
        })
        .then(result => {
            const response = JSON.parse(result);
            this.isLoadingDiff = false;
            if (response.success) {
                this.differenceReport = response;
                this.formattedDiff = this.formatDiff(response.diff || '');
                // NEW / MODIFIED / DELETED default to Split View; Unified via tabs.
                this.diffViewMode = 'split';
                this.showRawDiff = false;
                this.showDiffModal = true;
            } else {
                alert(response.error);
            }
        })
        .catch(error => {
            this.isLoadingDiff = false;
            console.error(error);
        });
    }

    formatDiff(diffText) {
        return diffText.split('\n').map((line, index) => {
            let cssClass = 'normal-line';
            if (line.startsWith('+') && !line.startsWith('+++')) {
                cssClass = 'added-line';
            } else if (line.startsWith('-') && !line.startsWith('---')) {
                cssClass = 'removed-line';
            }
            return { id: index, text: line, className: cssClass };
        });
    }

    closeDiffModal() {
        this.showDiffModal = false;
        this.showRawDiff = false;
        this.diffViewMode = 'split';
        this.differenceReport = null;
        this.formattedDiff = [];
        this.aiExplanation = '';
    }

    get isDeleted() {
        return this.differenceReport && this.differenceReport.changeType === 'DELETED';
    }

    get isNew() {
        return this.differenceReport && this.differenceReport.changeType === 'NEW';
    }

    get isModified() {
        return this.differenceReport && this.differenceReport.changeType === 'MODIFIED';
    }

    /** Presentation-only — Split vs Unified toggle (NEW / MODIFIED / DELETED). */
    diffViewMode = 'split';

    get supportsDiffViewTabs() {
        return this.isNew || this.isModified || this.isDeleted;
    }

    get showSplitView() {
        return this.supportsDiffViewTabs && this.diffViewMode === 'split';
    }

    /** MODIFIED keeps paired side-by-side rows (unchanged). */
    get showSplitPairedRows() {
        return this.showSplitView && this.isModified;
    }

    /** NEW / DELETED: one content pane + one enterprise placeholder. */
    get showSplitAsymmetric() {
        return this.showSplitView && (this.isNew || this.isDeleted);
    }

    get showSplitSourcePlaceholder() {
        return this.showSplitAsymmetric && this.isNew;
    }

    get showSplitDestinationPlaceholder() {
        return this.showSplitAsymmetric && this.isDeleted;
    }

    get showUnifiedDiffPanel() {
        if (!this.differenceReport) {
            return false;
        }
        if (this.supportsDiffViewTabs) {
            return this.diffViewMode === 'unified';
        }
        return this.showRawDiff;
    }

    get isSplitViewMode() {
        return this.diffViewMode === 'split';
    }

    get isUnifiedViewMode() {
        return this.diffViewMode === 'unified';
    }

    get splitViewTabClass() {
        return this.isSplitViewMode
            ? 'diff-view-tab diff-view-tab_active'
            : 'diff-view-tab';
    }

    get unifiedViewTabClass() {
        return this.isUnifiedViewMode
            ? 'diff-view-tab diff-view-tab_active'
            : 'diff-view-tab';
    }

    /**
     * Presentation-only — GitHub-style rows from existing unified diff.
     */
    get splitDiffRows() {
        return this._buildSplitDiffRows(
            this.differenceReport?.diff || ''
        );
    }

    handleDiffViewModeSelect(event) {
        const mode = event.currentTarget.dataset.mode;
        if (mode !== 'split' && mode !== 'unified') {
            return;
        }
        this.diffViewMode = mode;
    }

    toggleRawDiff() {
        this.showRawDiff = !this.showRawDiff;
    }

    /**
     * Presentation-only — parse unified Git diff into left/right columns.
     * Left = Destination (old / -), Right = Source (new / +).
     */
    _buildSplitDiffRows(diffText) {
        const lines = String(diffText || '').split('\n');
        const rows = [];
        const pendingRemovals = [];
        let rowId = 0;

        const flushRemovals = () => {
            while (pendingRemovals.length) {
                const leftText = pendingRemovals.shift();
                rows.push({
                    id: `split-${rowId++}`,
                    leftText,
                    rightText: '',
                    leftClass: 'split-line split-line_removed',
                    rightClass: 'split-line split-line_empty',
                    isHeader: false
                });
            }
        };

        lines.forEach((line) => {
            if (line.startsWith('---') || line.startsWith('+++')) {
                return;
            }

            if (line.startsWith('@@')) {
                flushRemovals();
                rows.push({
                    id: `split-${rowId++}`,
                    leftText: line,
                    rightText: line,
                    leftClass: 'split-line split-line_header',
                    rightClass: 'split-line split-line_header',
                    isHeader: true
                });
                return;
            }

            if (line.startsWith('-')) {
                pendingRemovals.push(line.substring(1));
                return;
            }

            if (line.startsWith('+')) {
                const rightText = line.substring(1);
                if (pendingRemovals.length) {
                    const leftText = pendingRemovals.shift();
                    rows.push({
                        id: `split-${rowId++}`,
                        leftText,
                        rightText,
                        leftClass: 'split-line split-line_removed',
                        rightClass: 'split-line split-line_added',
                        isHeader: false
                    });
                } else {
                    rows.push({
                        id: `split-${rowId++}`,
                        leftText: '',
                        rightText,
                        leftClass: 'split-line split-line_empty',
                        rightClass: 'split-line split-line_added',
                        isHeader: false
                    });
                }
                return;
            }

            flushRemovals();
            const contextText = line.startsWith(' ')
                ? line.substring(1)
                : line;
            rows.push({
                id: `split-${rowId++}`,
                leftText: contextText,
                rightText: contextText,
                leftClass: 'split-line split-line_context',
                rightClass: 'split-line split-line_context',
                isHeader: false
            });
        });

        flushRemovals();
        return rows;
    }

    get formattedDiffLines() {
        if (!this.differenceReport || !this.differenceReport.diff) {
            return [];
        }
        return this.differenceReport.diff.split('\n').map((line, index) => {
            let cssClass = 'diff-normal';
            if (line.startsWith('+')) {
                cssClass = 'diff-added';
            } else if (line.startsWith('-')) {
                cssClass = 'diff-removed';
            } else if (line.startsWith('@@')) {
                cssClass = 'diff-header';
            }
            return { id: index, text: line, cssClass };
        });
    }

    get statusMessage() {
        if (!this.differenceReport) { return ''; }
        if (this.differenceReport.changeType === 'NEW') {
            return 'Exists in Destination Org • Missing in Source Org';
        }
        if (this.differenceReport.changeType === 'DELETED') {
            return 'Exists in Source Org • Missing in Destination Org';
        }
        return 'Exists in Both Orgs • Content is Different';
    }

    handleSearch(event) {
        this.searchKeyword = event.target.value.toLowerCase();
        this.buildGroupedResults();
    }

    /**
     * Presentation-only — Deployment Intent filter for Comparison Summary.
     */
    handleDeploymentIntentFilterChange(event) {
        const value = event?.detail?.value ?? event?.target?.value ?? 'ALL';
        this.filterDeploymentIntent = value || 'ALL';
        this.buildGroupedResults();
    }

    /**
     * Presentation-only — Metadata Type filter for Comparison Summary.
     */
    handleMetadataTypeFilterChange(event) {
        const value = event?.detail?.value ?? event?.target?.value ?? 'ALL';
        this.filterMetadataType = value || 'ALL';
        this.buildGroupedResults();
    }

    /**
     * Presentation-only — Change Type filter for Comparison Summary.
     */
    handleChangeTypeFilterChange(event) {
        const value = event?.detail?.value ?? event?.target?.value ?? 'ALL';
        this.filterChangeType = value || 'ALL';
        this.buildGroupedResults();
    }

    /**
     * Presentation-only — reset Search + filters and rebuild grouped UI.
     */
    handleClearComparisonSummaryFilters() {
        this.searchKeyword = '';
        this.filterMetadataType = 'ALL';
        this.filterDeploymentIntent = 'ALL';
        this.filterChangeType = 'ALL';
        this.buildGroupedResults();
    }

    /** Presentation-only — Clear Filters enabled when any criterion is active. */
    get isClearComparisonSummaryFiltersDisabled() {
        const searchEmpty = !this.searchKeyword;
        const metadataAll =
            !this.filterMetadataType ||
            this.filterMetadataType === 'ALL';
        const intentAll =
            !this.filterDeploymentIntent ||
            this.filterDeploymentIntent === 'ALL';
        const changeAll =
            !this.filterChangeType ||
            this.filterChangeType === 'ALL';
        return searchEmpty && metadataAll && intentAll && changeAll;
    }

    /** Presentation-only — visible file count from current grouped projection. */
    get comparisonSummaryVisibleCount() {
        return (this.groupedComparisonResults || []).reduce(
            (total, group) => total + (group.count || 0),
            0
        );
    }

    /** Presentation-only — complement to files/selected counters. */
    get comparisonSummaryShowingLabel() {
        const visible = this.comparisonSummaryVisibleCount;
        const total = (this.savedComparisonResults || []).length;
        const metadataFilter = this.filterMetadataType || 'ALL';

        if (metadataFilter !== 'ALL') {
            return `Showing ${visible} ${metadataFilter} Results`;
        }

        if (total > 0 && visible !== total) {
            return `Showing ${visible} of ${total} Results`;
        }
        return `Showing ${visible} Results`;
    }

    /**
     * Presentation-only — empty projection while working copy has data
     * (search/filters produced zero matches).
     */
    get showComparisonSummaryFilterEmptyState() {
        const total = (this.savedComparisonResults || []).length;
        return total > 0 && this.comparisonSummaryVisibleCount === 0;
    }

    /**
     * Presentation-only gate used by buildGroupedResults.
     * Does not mutate savedComparisonResults.
     */
    _recordMatchesComparisonSummaryFilters(record) {
        const metadataTypeFilter = this.filterMetadataType || 'ALL';
        if (metadataTypeFilter !== 'ALL') {
            if (this._resolveDisplayGroupType(record) !== metadataTypeFilter) {
                return false;
            }
        }

        const intentFilter = this.filterDeploymentIntent || 'ALL';
        if (intentFilter !== 'ALL') {
            const resolvedIntent = this._resolveDeploymentIntent(record);
            if (intentFilter === 'Deploy' && resolvedIntent !== 'Deploy') {
                return false;
            }
            if (intentFilter === 'Ignore' && resolvedIntent !== 'Ignore') {
                return false;
            }
            if (
                intentFilter === 'No Selection' &&
                resolvedIntent !== ''
            ) {
                return false;
            }
        }

        const changeTypeFilter = this.filterChangeType || 'ALL';
        if (changeTypeFilter !== 'ALL') {
            const changeType = record.Change_Type__c || '';
            if (changeType !== changeTypeFilter) {
                return false;
            }
        }

        return true;
    }

    // AI Summary Generation — business logic unchanged; success UX only appended after.
    async generateAISummary() {
        this.isGeneratingSummary = true;
        let generationSucceeded = false;
        try {
            const response = await fetch(
                `${BACKEND_BASE_URL}/api/ai/comparison-summary`,
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        model: this.selectedModel,
                        comparisonName: this.selectedComparisonLabel,
                        totalFiles: this.savedComparisonResults.length,
                        groupedResults: this.groupedComparisonResults.map(group => ({
                            type: group.type,
                            count: group.count
                        }))
                    })
                }
            );
            const result = await response.json();
            if (result.success) {
                this.aiProviderName = this.selectedModel === 'openai'
                    ? 'GPT-4o Mini'
                    : 'Gemini 2.5 Flash';
                this.aiSummary = result.summary
                    .replace('Executive Summary:', '📋 Executive Summary:\n')
                    .replace('Major Impact Areas:', '\n🎯 Major Impact Areas:\n')
                    .replace('Risk Level:', '\n⚠️ Risk Level:\n')
                    .replace('Recommended Testing:', '\n🧪 Recommended Testing:\n');
                this.formattedAiSummary = this.aiSummary
                    .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
                    .replace(/\n/g, '<br>');
                generationSucceeded = true;
            }
        } catch(error) {
            console.error(error);
        }
        this.isGeneratingSummary = false;

        // Presentation UX — only after successful generation.
        // Modal stays open during generation; failures keep modal open for retry.
        if (generationSucceeded) {
            this.closeStage3Modal();
            await new Promise((resolve) => {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(resolve, 200);
            });
            this._revealExistingAiSummaryCard();
        }
    }

    /**
     * Presentation-only — scroll to existing AI Summary and apply a brief highlight.
     * Reuses data-id="comparison-ai-summary"; does not create another summary.
     */
    _revealExistingAiSummaryCard() {
        const target = this.template.querySelector(
            '[data-id="comparison-ai-summary"]'
        );
        if (!target) {
            return;
        }
        if (typeof target.scrollIntoView === 'function') {
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
        target.classList.add('ai-summary-reveal-highlight');
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            target.classList.remove('ai-summary-reveal-highlight');
        }, 1000);
    }

    async handleExplainWithAI() {
        this.isGeneratingExplanation = true;
        try {
            const response = await fetch(
                `${BACKEND_BASE_URL}/api/ai/explain-diff`,
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        model: this.selectedModel,
                        fileName: this.selectedFile.File_Name__c,
                        metadataType: this.selectedFile.Metadata_Type__c,
                        diff: this.differenceReport.diff
                    })
                }
            );
            const result = await response.json();
            if (result.success) {
                this.aiProviderName = this.selectedModel === 'openai'
                    ? 'GPT-4o Mini'
                    : 'Gemini 2.5 Flash';
                this.aiExplanation = result.explanation;
            } else {
                alert(result.error);
            }
        } catch(error) {
            console.error(error);
        }
        this.isGeneratingExplanation = false;
    }

    get modelOptions() {
        return [
            { label: 'Gemini 2.5 Flash', value: 'gemini' },
            { label: 'GPT-4o Mini',      value: 'openai' }
        ];
    }

    handleModelChange(event) {
        this.selectedModel = event.detail.value;
    }

    openNewComparisonModal() {
        if (this.isRetrievalInProgress) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Metadata Retrieval in Progress',
                    message:
                        'Please wait until metadata retrieval finishes before creating a new comparison.',
                    variant: 'info',
                    mode: 'dismissable'
                })
            );
            return;
        }
        this.isNewComparisonModalOpen = true;
    }

    closeNewComparisonModal() {
        this.isNewComparisonModalOpen = false;
    }

    openConnectOrgModal() {
        if (this.isRetrievalInProgress) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Metadata Retrieval in Progress',
                    message:
                        'Please wait until metadata retrieval finishes before connecting a new org.',
                    variant: 'info',
                    mode: 'dismissable'
                })
            );
            return;
        }
        this.isConnectOrgModalOpen = true;
    }

    closeConnectOrgModal() {
        this.isConnectOrgModalOpen = false;
    }

    handleSaveComparisonFromModal() {
        if (!this.comparisonName) {
            alert('Please enter Comparison Name');
            return;
        }
        if (!this.sourceOrgId) {
            alert('Please select Source Org');
            return;
        }
        if (!this.destinationOrgId) {
            alert('Please select Destination Org');
            return;
        }
        saveComparison({
            comparisonName:   this.comparisonName,
            sourceOrgId:      this.sourceOrgId,
            destinationOrgId: this.destinationOrgId
        })
        .then(() => {
            refreshApex(this.wiredComparisonResult);
            this.closeNewComparisonModal();
            alert('Comparison Saved Successfully');
        })
        .catch(error => {
            console.error(error);
        });
    }

    get totalDiffCount() {
        return this.savedComparisonResults ? this.savedComparisonResults.length : 0;
    }

    get kpiAdded() {
        if (!this.savedComparisonResults) return 0;
        return this.savedComparisonResults.filter(r => r.Change_Type__c === 'NEW').length;
    }

    get kpiModified() {
        if (!this.savedComparisonResults) return 0;
        return this.savedComparisonResults.filter(r => r.Change_Type__c === 'MODIFIED').length;
    }

    get kpiDeleted() {
        if (!this.savedComparisonResults) return 0;
        return this.savedComparisonResults.filter(r => r.Change_Type__c === 'DELETED').length;
    }

    /**
     * Presentation-only — largest metadata type from savedComparisonResults.
     * Uses existing _resolveDisplayGroupType; no backend.
     */
    get largestMetadataTypeLabel() {
        const top = this.topMetadataTypeBreakdown;
        if (!top.length) {
            return '—';
        }
        return `${top[0].type} (${top[0].count})`;
    }

    /**
     * Presentation-only — Top 5 metadata types by count from working copy.
     * Same display-group typing as Metadata Type filter.
     */
    get topMetadataTypeBreakdown() {
        const counts = {};
        (this.savedComparisonResults || []).forEach((record) => {
            const type = this._resolveDisplayGroupType(record);
            if (!type) {
                return;
            }
            counts[type] = (counts[type] || 0) + 1;
        });

        return Object.keys(counts)
            .sort((a, b) => {
                const diff = counts[b] - counts[a];
                return diff !== 0 ? diff : a.localeCompare(b);
            })
            .slice(0, 5)
            .map((type) => ({
                key: type,
                type,
                count: counts[type]
            }));
    }

    get hasTopMetadataTypeBreakdown() {
        return this.topMetadataTypeBreakdown.length > 0;
    }

    /**
     * Presentation-only — SVG donut segments from existing KPI getters.
     * Percentages are for chart rendering only.
     */
    get changeDistributionChart() {
        const added = this.kpiAdded || 0;
        const modified = this.kpiModified || 0;
        const deleted = this.kpiDeleted || 0;
        const total = added + modified + deleted;
        const radius = 42;
        const circumference = 2 * Math.PI * radius;

        if (total === 0) {
            return {
                total: 0,
                addedDash: `0 ${circumference}`,
                addedOffset: '0',
                modifiedDash: `0 ${circumference}`,
                modifiedOffset: '0',
                deletedDash: `0 ${circumference}`,
                deletedOffset: '0',
                addedPct: 0,
                modifiedPct: 0,
                deletedPct: 0
            };
        }

        const addedLen = (added / total) * circumference;
        const modifiedLen = (modified / total) * circumference;
        const deletedLen = (deleted / total) * circumference;

        return {
            total,
            addedDash: `${addedLen} ${circumference}`,
            addedOffset: '0',
            modifiedDash: `${modifiedLen} ${circumference}`,
            modifiedOffset: `${-addedLen}`,
            deletedDash: `${deletedLen} ${circumference}`,
            deletedOffset: `${-(addedLen + modifiedLen)}`,
            addedPct: Math.round((added / total) * 100),
            modifiedPct: Math.round((modified / total) * 100),
            deletedPct: Math.round((deleted / total) * 100)
        };
    }

    get hasChangeDistributionData() {
        return (this.changeDistributionChart.total || 0) > 0;
    }

    get changeDistributionAriaLabel() {
        const chart = this.changeDistributionChart;
        return `Change distribution: ${this.kpiAdded} new (${chart.addedPct}%), ${this.kpiModified} modified (${chart.modifiedPct}%), ${this.kpiDeleted} deleted (${chart.deletedPct}%)`;
    }

    /**
     * Presentation-only — readiness from selectedFileCount only.
     */
    get deploymentReadinessLabel() {
        return this.selectedFileCount > 0
            ? 'Ready'
            : 'Select metadata to continue';
    }

    get deploymentReadinessValueClass() {
        return this.selectedFileCount > 0
            ? 'cmp-insight-value cmp-insight-value_ready'
            : 'cmp-insight-value cmp-insight-value_pending';
    }

    /** Presentation-only — empty-state toggle for Deployment Readiness. */
    get hasSelectedMetadataForPlan() {
        return this.selectedFileCount > 0;
    }

    /** Presentation-only — whether existing AI summary state is populated. */
    get hasAiSummary() {
        return !!this.aiSummary;
    }

    get aiAnalysisStatusLabel() {
        if (this.isGeneratingSummary) {
            return 'Generating';
        }
        return this.aiSummary ? 'Ready' : 'Not Generated';
    }

    get aiAnalysisModelLabel() {
        if (this.selectedModel === 'openai') {
            return 'GPT-4o Mini';
        }
        if (this.selectedModel === 'gemini') {
            return 'Gemini 2.5 Flash';
        }
        return this.selectedModel || '—';
    }

    get aiSummaryAvailabilityLabel() {
        return this.aiSummary ? 'Available' : 'Not Available';
    }

    get aiSummaryReportToggleLabel() {
        return this.isAiSummaryReportExpanded ? 'Collapse' : 'Expand';
    }

    /**
     * Presentation-only — parse existing aiSummary text into report sections.
     * Does not mutate aiSummary / formattedAiSummary or call generation.
     */
    get aiSummaryReport() {
        return this._buildAiSummaryReport(this.aiSummary);
    }

    get hasAiSummaryExecutive() {
        return !!(this.aiSummaryReport?.executiveSummary);
    }

    get hasAiSummaryImpactItems() {
        return (this.aiSummaryReport?.impactItems || []).length > 0;
    }

    get hasAiSummaryRisk() {
        return !!(
            this.aiSummaryReport?.riskLevel ||
            this.aiSummaryReport?.riskExplanation
        );
    }

    get hasAiSummaryTestingItems() {
        return (this.aiSummaryReport?.testingItems || []).length > 0;
    }

    get hasAiSummaryRecommendations() {
        return (this.aiSummaryReport?.recommendationItems || []).length > 0;
    }

    get showAiSummaryRawFallback() {
        return (
            !!this.aiSummary &&
            !this.hasAiSummaryExecutive &&
            !this.hasAiSummaryImpactItems &&
            !this.hasAiSummaryRisk &&
            !this.hasAiSummaryTestingItems &&
            !this.hasAiSummaryRecommendations
        );
    }

    get aiSummaryRiskBadgeClass() {
        const level = (this.aiSummaryReport?.riskLevel || '').toLowerCase();
        if (level === 'high') {
            return 'slds-badge slds-theme_error ai-report-risk-badge';
        }
        if (level === 'medium') {
            return 'slds-badge slds-theme_warning ai-report-risk-badge';
        }
        if (level === 'low') {
            return 'slds-badge slds-theme_success ai-report-risk-badge';
        }
        return 'slds-badge slds-theme_info ai-report-risk-badge';
    }

    handleToggleAiSummaryReport() {
        this.isAiSummaryReportExpanded = !this.isAiSummaryReportExpanded;
    }

    handleCopyAiSummary() {
        const text = this.aiSummary || '';
        if (!text) {
            return;
        }
        if (navigator?.clipboard?.writeText) {
            navigator.clipboard.writeText(text).catch(() => {
                /* presentation-only; ignore clipboard failures */
            });
        }
    }

    _buildAiSummaryReport(summaryText) {
        if (!summaryText) {
            return {
                executiveSummary: '',
                impactItems: [],
                riskLevel: '',
                riskExplanation: '',
                testingItems: [],
                recommendationItems: [],
                fallbackHtml: ''
            };
        }

        const normalized = String(summaryText)
            .replace(/📋\s*/g, '')
            .replace(/🎯\s*/g, '')
            .replace(/⚠️\s*/g, '')
            .replace(/🧪\s*/g, '')
            .replace(/\r\n/g, '\n');

        const sections = this._extractAiSummarySections(normalized);
        const executiveSummary = (sections.executive || '').trim();
        const impactItems = this._parseAiImpactItems(sections.impact || '');
        const risk = this._parseAiRiskSection(sections.risk || '');
        const testingItems = this._parseAiBulletItems(sections.testing || '');
        const recommendationItems = this._parseAiBulletItems(
            sections.recommendations || ''
        );

        return {
            executiveSummary,
            impactItems,
            riskLevel: risk.level,
            riskExplanation: risk.explanation,
            testingItems,
            recommendationItems,
            fallbackHtml: this.formattedAiSummary || ''
        };
    }

    _extractAiSummarySections(text) {
        const markers = [
            { key: 'executive', label: 'Executive Summary' },
            { key: 'impact', label: 'Major Impact Areas' },
            { key: 'risk', label: 'Risk Level' },
            { key: 'testing', label: 'Recommended Testing' },
            { key: 'recommendations', label: 'Recommendations' }
        ];

        const found = markers
            .map((marker) => {
                const re = new RegExp(
                    `(?:^|\\n)\\s*${marker.label}\\s*:?\\s*`,
                    'i'
                );
                const match = re.exec(text);
                if (!match) {
                    return null;
                }
                return {
                    key: marker.key,
                    start: match.index,
                    contentStart: match.index + match[0].length
                };
            })
            .filter(Boolean)
            .sort((a, b) => a.start - b.start);

        const sections = {
            executive: '',
            impact: '',
            risk: '',
            testing: '',
            recommendations: ''
        };

        if (!found.length) {
            sections.executive = text.trim();
            return sections;
        }

        found.forEach((entry, index) => {
            const end =
                index + 1 < found.length ? found[index + 1].start : text.length;
            sections[entry.key] = text.slice(entry.contentStart, end).trim();
        });

        return sections;
    }

    _parseAiImpactItems(sectionText) {
        const lines = this._splitAiContentLines(sectionText);
        const icons = [
            'utility:database',
            'utility:apex',
            'utility:desktop',
            'utility:flow',
            'utility:settings',
            'utility:layers',
            'utility:world'
        ];

        return lines
            .map((line, index) => {
                const cleaned = line
                    .replace(/^[-•*]\s*/, '')
                    .replace(/^\d+[\).\]]\s*/, '')
                    .replace(/\*\*/g, '')
                    .trim();
                if (!cleaned) {
                    return null;
                }

                let label = cleaned;
                let detail = '';

                const countMatch = cleaned.match(
                    /^(.+?)\s*[-–—:|]\s*(\d[\d,]*)\s*(Components?|Files?|Items?)?\s*$/i
                );
                if (countMatch) {
                    label = countMatch[1].trim();
                    const unit = countMatch[3] ? ` ${countMatch[3]}` : ' Components';
                    detail = `${countMatch[2]}${unit}`;
                } else {
                    const parenMatch = cleaned.match(
                        /^(.+?)\s*\((\d[\d,]*.*?)\)\s*$/
                    );
                    if (parenMatch) {
                        label = parenMatch[1].trim();
                        detail = parenMatch[2].trim();
                    }
                }

                return {
                    key: `impact-${index}`,
                    label,
                    detail,
                    iconName: icons[index % icons.length]
                };
            })
            .filter(Boolean);
    }

    _parseAiRiskSection(sectionText) {
        const text = (sectionText || '').trim();
        if (!text) {
            return { level: '', explanation: '' };
        }

        const levelMatch = text.match(/\b(High|Medium|Low)\b/i);
        const level = levelMatch ? levelMatch[1] : '';
        let explanation = text;
        if (level) {
            explanation = text
                .replace(new RegExp(`^\\s*${level}\\s*[-–—:]?\\s*`, 'i'), '')
                .trim();
        }
        return { level, explanation };
    }

    _parseAiBulletItems(sectionText) {
        return this._splitAiContentLines(sectionText)
            .map((line, index) => {
                const text = line
                    .replace(/^[-•*]\s*/, '')
                    .replace(/^\d+[\).\]]\s*/, '')
                    .replace(/^✓\s*/, '')
                    .replace(/\*\*/g, '')
                    .trim();
                if (!text) {
                    return null;
                }
                return {
                    key: `item-${index}`,
                    text
                };
            })
            .filter(Boolean);
    }

    _splitAiContentLines(sectionText) {
        return String(sectionText || '')
            .split('\n')
            .map((line) => line.trim())
            .filter((line) => line.length > 0);
    }

    /**
     * Presentation-only — navigate to existing AI Summary card, or open
     * Stage 3 modal so the user can use the single Generate AI Summary path.
     * Does not generate AI and does not create a new summary surface.
     */
    handleViewAiAnalysis() {
        if (this.aiSummary) {
            const target = this.template.querySelector(
                '[data-id="comparison-ai-summary"]'
            );
            if (target && typeof target.scrollIntoView === 'function') {
                target.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
            return;
        }
        this.openStage3Modal();
    }

    checkMigrationStatus() {

    getMigrationStatus()
        .then(result => {

            const response =
                JSON.parse(result);

            console.log(
                'Migration Status:',
                response.status
            );

            if (this.activeMigrationType === 'Source') {

                this.sourceStatusMessage =
                    response.status;

            }

            if (this.activeMigrationType === 'Destination') {

                this.destinationStatusMessage =
                    response.status;

            }

            if (response.status === 'Push completed') {

    clearInterval(
        this.statusPollingInterval
    );

    this._clearRetrievalRunningFlags();

    if (this.activeMigrationType === 'Source') {

        updateMigrationStatus({
            comparisonId: this.selectedComparison,
            branchName: this.sourceBranch,
            migrationType: 'Source'
        })
        .then(() => {
            this.refreshComparisonDetails();
        });

    }

    if (this.activeMigrationType === 'Destination') {

        updateMigrationStatus({
            comparisonId: this.selectedComparison,
            branchName: this.destinationBranch,
            migrationType: 'Destination'
        })
        .then(() => {
            this.refreshComparisonDetails();
        });

    }

}

            if (response.status === 'Migration failed') {

                clearInterval(
                    this.statusPollingInterval
                );

                this._clearRetrievalRunningFlags();

            }

        })
        .catch(error => {

            console.error(
                'Status Check Error',
                error
            );

        });

}

get disableSourceButton() {

    return this.sourceMigrationCompleted ||
           this.isSourceRetrievalRunning;

}

get disableDestinationButton() {

    return this.destinationMigrationCompleted ||
           this.isSourceRetrievalRunning ||
           this.isDestinationRetrievalRunning;

}


groupCustomObjectFiles(files) {
    const grouped = {};

    files.forEach(file => {

        const path = file.File_Path__c || '';

        const match =
            path.match(/objects\/([^\/]+)\//);

        const objectName =
            match ? match[1] : 'Other';

        if (!grouped[objectName]) {
            grouped[objectName] = [];
        }

        grouped[objectName].push(file);
    });

    return Object.keys(grouped).map(name => {

    return {

        objectName: name,

        expanded: false,

        files:
            grouped[name],

        metadataGroups:
            this.groupMetadataCategories(
                grouped[name]
            )

    };

});
}

groupMetadataCategories(files) {

    const categories = {};

    files.forEach(file => {

        const fileName =
            file.File_Name__c || '';

        let category =
            'Other';

        if (
            fileName.includes(
                '.field-meta.xml'
            )
        ) {
            category = 'Fields';
        }
        else if (
            fileName.includes(
                '.validationRule-meta.xml'
            )
        ) {
            category =
                'Validation Rules';
        }
        else if (
            fileName.includes(
                '.recordType-meta.xml'
            )
        ) {
            category =
                'Record Types';
        }
        else if (
            fileName.includes(
                '.listView-meta.xml'
            )
        ) {
            category =
                'List Views';
        }
        else if (
            fileName.includes(
                '.object-meta.xml'
            )
        ) {
            category =
                'Object Definition';
        }

        if (
            !categories[category]
        ) {

            categories[category] = {
                categoryName:
                    category,
                expanded: false,
                files: []
            };

        }

        categories[category]
            .files
            .push(file);

    });

    return Object.values(
        categories
    );

}

groupFlowFiles(files) {

    const groups = {
        Active: [],
        Inactive: [],
        Other: []
    };

    files.forEach(file => {

        const status =
            file.Flow_Status__c;

        if (status === 'Active') {

            groups.Active.push(file);

        }
        else if (status === 'Obsolete') {

            groups.Inactive.push(file);

        }
        else {

            groups.Other.push(file);

        }

    });

    return [

        {
            groupName: 'Active Flows',
            expanded: false,
            files: groups.Active
        },

        {
            groupName: 'Inactive Flows',
            expanded: false,
            files: groups.Inactive
        },

        {
            groupName: 'Other Flows',
            expanded: false,
            files: groups.Other
        }

    ].filter(group => group.files.length > 0);

}

/**
 * Presentation-only — group LWC files by bundle name.
 * Same nested UI pattern as Flow/CustomObject; does not mutate savedComparisonResults.
 * Bundle intent is always derived from child files — never persisted.
 */
groupLwcFiles(files) {
    const previousExpanded = {};
    const existingLwcGroup = (this.groupedComparisonResults || []).find(
        (group) => group.type === 'LWC' && group.lwcGroups
    );
    (existingLwcGroup?.lwcGroups || []).forEach((bundle) => {
        previousExpanded[bundle.bundleName] = bundle.expanded;
    });

    const grouped = {};

    (files || []).forEach((file) => {
        const bundleName = this._extractLwcBundleName(file);
        if (!grouped[bundleName]) {
            grouped[bundleName] = [];
        }
        grouped[bundleName].push(file);
    });

    return Object.keys(grouped)
        .sort((a, b) => a.localeCompare(b))
        .map((name) => {
            const bundleFiles = grouped[name];
            const derived = this._deriveLwcBundleIntent(bundleFiles);
            return {
                bundleName: name,
                expanded: previousExpanded[name] === true,
                files: bundleFiles,
                bundleIntent: derived.value,
                bundleIntentPlaceholder: derived.placeholder,
                isMixed: derived.isMixed
            };
        });
}

/**
 * Derive bundle deployment-intent display from child records.
 * All Deploy → Deploy; All Ignore → Ignore; All Clear → Select (blank);
 * Mixed → placeholder Mixed (not stored).
 */
_deriveLwcBundleIntent(files) {
    const intents = (files || []).map((file) =>
        this._resolveDeploymentIntent(file)
    );

    if (!intents.length) {
        return {
            value: '',
            placeholder: 'Select',
            isMixed: false
        };
    }

    const first = intents[0];
    const allSame = intents.every((intent) => intent === first);

    if (!allSame) {
        return {
            value: '',
            placeholder: 'Mixed',
            isMixed: true
        };
    }

    if (first === 'Deploy' || first === 'Ignore') {
        return {
            value: first,
            placeholder: 'Select',
            isMixed: false
        };
    }

    return {
        value: '',
        placeholder: 'Select',
        isMixed: false
    };
}

/**
 * Derive LWC bundle name from path (/lwc/{bundle}/) or file name suffixes.
 */
_extractLwcBundleName(file) {
    const path = file?.File_Path__c || '';
    const pathMatch = path.match(/(?:^|\/)lwc\/([^/]+)\//i);
    if (pathMatch && pathMatch[1]) {
        return pathMatch[1];
    }

    const fileName = file?.File_Name__c || '';
    if (!fileName) {
        return 'Other';
    }

    const stripped = fileName
        .replace(/\.js-meta\.xml$/i, '')
        .replace(/\.html$/i, '')
        .replace(/\.css$/i, '')
        .replace(/\.svg$/i, '')
        .replace(/\.js$/i, '')
        .replace(/\.xml$/i, '');

    return stripped || 'Other';
}

toggleFlowGroup(event) {

    const metadataType =
        event.currentTarget.dataset.type;

    const groupName =
        event.currentTarget.dataset.group;

    this.groupedComparisonResults =
        this.groupedComparisonResults.map(group => {

            if (
                group.type === metadataType &&
                group.flowGroups
            ) {

                group.flowGroups =
                    group.flowGroups.map(flowGroup => {

                        if (
                            flowGroup.groupName ===
                            groupName
                        ) {

                            return {
                                ...flowGroup,
                                expanded:
                                    !flowGroup.expanded
                            };

                        }

                        return flowGroup;

                    });

            }

            return { ...group };

        });

}

toggleLwcBundle(event) {

    const metadataType =
        event.currentTarget.dataset.type;

    const bundleName =
        event.currentTarget.dataset.bundle;

    this.groupedComparisonResults =
        this.groupedComparisonResults.map(group => {

            if (
                group.type === metadataType &&
                group.lwcGroups
            ) {

                group.lwcGroups =
                    group.lwcGroups.map(lwcGroup => {

                        if (
                            lwcGroup.bundleName ===
                            bundleName
                        ) {

                            return {
                                ...lwcGroup,
                                expanded:
                                    !lwcGroup.expanded
                            };

                        }

                        return lwcGroup;

                    });

            }

            return { ...group };

        });

}

handleDeploymentIntentChange(event) {

    const recordId = event.target.dataset.id;
    const rawValue = event.detail.value;

    this._applyDeploymentIntentToRecords([recordId], rawValue);

}

/**
 * Prevent bundle-header expand/collapse when interacting with the intent combobox.
 */
stopLwcBundleIntentClick(event) {
    event.stopPropagation();
}

/**
 * Bundle-row Deploy / Ignore / Clear Selection — applies the same intent workflow
 * to every child Comparison_Result in the bundle. No bundle persistence.
 */
handleLwcBundleIntentChange(event) {
    event.stopPropagation();

    const bundleName = event.target.dataset.bundle;
    const rawValue = event.detail.value;

    if (!bundleName) {
        return;
    }

    // Mixed is display-only — never persist or apply.
    if (rawValue === '__MIXED__') {
        return;
    }

    const childIds = (this.savedComparisonResults || [])
        .filter((file) => this._extractLwcBundleName(file) === bundleName)
        .filter((file) => this._resolveDisplayGroupType(file) === 'LWC')
        .map((file) => file.Id)
        .filter(Boolean);

    this._applyDeploymentIntentToRecords(childIds, rawValue);
}

/**
 * Shared deployment-intent update for one or many Comparison_Result Ids.
 * Reuses Apex updateIntent. The working copy is the single source of truth for
 * the UI; a cacheable reload must never re-assert a stale intent over it.
 * Does not introduce a parallel business path.
 */
_applyDeploymentIntentToRecords(recordIds, rawValue) {
    const ids = [
        ...new Set((recordIds || []).filter(Boolean))
    ];

    if (!ids.length) {
        return Promise.resolve();
    }

    // Phase 5 — Clear Selection is UI-only; persist blank so Apex clears Intent
    const isClear =
        rawValue === '__CLEAR__' ||
        rawValue === '' ||
        rawValue == null;

    if (!isClear && rawValue !== 'Deploy' && rawValue !== 'Ignore') {
        return Promise.resolve();
    }

    const intentForApex = isClear ? '' : rawValue;
    const syncedIntent = isClear ? null : intentForApex;
    const syncedSelected = intentForApex === 'Deploy';
    const idSet = new Set(ids);

    // Per-row snapshot so a failed persist reverts only the affected rows.
    const previousByRecordId = new Map();
    (this.savedComparisonResults || []).forEach((file) => {
        if (idSet.has(file.Id)) {
            previousByRecordId.set(file.Id, {
                Deployment_Intent__c: file.Deployment_Intent__c,
                Selected_For_Deployment__c: file.Selected_For_Deployment__c
            });
        }
    });

    this.savedComparisonResults =
        (this.savedComparisonResults || []).map((file) => {
            if (!idSet.has(file.Id)) {
                return file;
            }
            return {
                ...file,
                Deployment_Intent__c: syncedIntent,
                Selected_For_Deployment__c: syncedSelected
            };
        });
    this.buildGroupedResults();

    return Promise.all(
        ids.map((resultId) =>
            updateIntent({
                resultId,
                intent: intentForApex
            })
        )
    )
        .catch((error) => {
            console.error(error);

            this.savedComparisonResults =
                (this.savedComparisonResults || []).map((file) => {
                    const previous = previousByRecordId.get(file.Id);
                    if (!previous) {
                        return file;
                    }
                    return { ...file, ...previous };
                });
            this.buildGroupedResults();

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message:
                        error?.body?.message ||
                        error?.message ||
                        'Unable to save Deployment Intent.',
                    variant: 'error',
                    mode: 'dismissable'
                })
            );
        });
}

/**
 * Resolve display/persist intent from durable fields.
 * Prefer Deployment_Intent__c; fall back to legacy Selected_For_Deployment__c.
 */
_resolveDeploymentIntent(record) {
    if (!record) {
        return '';
    }
    if (
        record.Deployment_Intent__c === 'Deploy' ||
        record.Deployment_Intent__c === 'Ignore'
    ) {
        return record.Deployment_Intent__c;
    }
    return record.Selected_For_Deployment__c === true ? 'Deploy' : '';
}

get selectedFileCount() {

    return this.savedComparisonResults.filter(
        file => file.Selected_For_Deployment__c === true
    ).length;

}

handleCreateDeploymentPlan() {

    createDeploymentPlan({
        comparisonId: this.selectedComparison
    })
    .then(planId => {

        // New plan must start empty — do not keep prior plan's Stage 4/5 session UI
        this._clearStage4To5SnapshotSessionState();

        this.currentDeploymentPlanId = planId;
        this.showDeploymentReview = true;

        // Guided navigation — open Stage 4 after successful plan creation.
        if (this.canOpenStage4) {
            this.activeLifecycleStage = 4;
        }

        alert(
            'Deployment Plan Created\n' +
            planId
        );

    })
    .catch(error => {

        console.error(error);

    });

}

get isCreateDeploymentDisabled() {
    return this.selectedFileCount === 0;
}

deploymentReviewData = null;

deploymentReviewItems = [];

/**
 * Phase 2A — Ignored vs required-dependency conflicts (internal only).
 * Populated after Review mapping; cleared on Stage 4–6 reset.
 * No UI / popup / workflow gating in this phase.
 */
ignoredConflicts = [];

hasIgnoredDependencyConflict = false;

/** Phase 2B — informational ignored-dependency modal (UI only). */
showIgnoredDependencyModal = false;

/** Phase 3 — Include Required Metadata in progress. */
isIncludingRequiredMetadata = false;

selectedTestClasses = {};

showDeploymentReview = false;

currentDeploymentPlanId = null;

isLoadingDeploymentReview = false;

sourceValidationData = null;

sourceValidationDisplayItems = [];

isLoadingSourceValidation = false;

deploymentValidationData = null;

deploymentValidationDisplay = null;

/**
 * Phase 17.6.1 — presentation-only deployment intelligence (raw backend reports).
 * Populated from deploymentValidationData; never recalculates backend decisions.
 */
deploymentEnterpriseReport = null;
deploymentFailureClassification = null;
deploymentResolutionReport = null;
deploymentAutoFixReport = null;
deploymentAutoValidationReport = null;
deploymentAiResolutionReport = null;

/** Phase 18.1 — presentation-only SAFE_SKIP report from validation response. */
deploymentSafeSkipReport = null;

/**
 * Phase 18.2 — on-demand AI Resolution result (distinct from validate-path stub).
 */
deploymentOnDemandAiResolution = null;
deploymentOnDemandAiDisplay = null;
onDemandAiProvider = 'gemini';
isResolvingWithAi = false;
onDemandAiErrorMessage = null;

onDemandAiProviderOptions = [
    { label: 'Gemini', value: 'gemini' },
    { label: 'GPT / OpenAI', value: 'openai' }
];

/**
 * Phase 18.3 — Support Bundle (download-only diagnostic).
 * Uses backend validation historyId — not Salesforce record Id.
 */
backendValidationHistoryId = null;
showSupportBundleModal = false;
supportBundleGenerating = false;
supportBundleReady = false;
supportBundleError = null;
supportBundle = null;
supportBundleId = null;
supportBundleFilename = null;

/** Phase 17.6.1 — safe row/KPI view model for Stage 5 HTML. */
deploymentIntelligenceDisplay = null;

/**
 * Phase 11.5 — presentation-only Enterprise Deployment Readiness Report.
 * Built from existing validation response fields. Does not affect deploy logic.
 */
deploymentReadinessReport = null;

/** Collapsible Compatibility Warnings section open state. */
readinessWarningsOpen = false;

/**
 * Stage 5 — presentation-only expand/collapse for intelligence sections.
 * Does not affect validation, SAFE_SKIP, AI APIs, planner, or readiness.
 */
isFailureAnalysisExpanded = true;
isResolutionNextActionsExpanded = true;
isSafeSkipAnalysisExpanded = false;
isAiResolutionExpanded = false;

/**
 * Optional root-level Validation response field from backend.
 * Stored only — not displayed or acted on in this phase.
 */
deploymentPackageProvenance = null;

/**
 * Processing-layer view model: AUTO_INCLUDED provenance members that the user
 * marked Ignore. Consumed by informational popup only.
 */
ignoredAutoIncludedMetadata = [];

/** Informational popup — Ignored metadata auto-included in package. */
showIgnoredAutoIncludedModal = false;

isLoadingDeploymentValidation = false;

/** Async deployment validation transport — dedicated; not retrieval polling. */
validationPollingInterval;
activeValidationId = null;
validationStatusMessage = '';
_validationComparisonId = null;

showDeployConfirmation = false;
isDeploying = false;
deployCompleted = false;

historyRecordId = null;

/**
 * Reserved for Deployment Planner.
 * Local UI selection map only — not sent to Apex/backend and unused by package build.
 * Keys: primary:<filePath> | dependency:<type>:<name>
 * Values: 'Deploy' | 'Skip'
 */
deploymentPlannerSelections = {};

/**
 * Cached planner table rows. Rebuilt only when validation data or selections change.
 * Must not be produced by a render-time getter — a new array each render causes
 * for:each to rebind lightning-button-menu and collapse an open menu.
 */
plannerRows = [];

/** Phase 10F — AI Deployment Advisor (advisory only; never authoritative). */
aiAdvisorData = null;
aiAdvisorDisplay = null;
isLoadingAiAdvisor = false;
showAiAdvisorDiagnostics = false;
aiAdvisorUnavailableMessage = null;

testExecutionColumns = [
    { label: 'Test Class', fieldName: 'testClass', type: 'text' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Methods Run', fieldName: 'methodsRun', type: 'number' },
    { label: 'Methods Passed', fieldName: 'methodsPassed', type: 'number' },
    { label: 'Methods Failed', fieldName: 'methodsFailed', type: 'number' },
    { label: 'Failed Methods', fieldName: 'failedMethods', type: 'text' }
];

coverageColumns = [
    { label: 'Apex Class', fieldName: 'apexClass', type: 'text' },
    { label: 'Coverage %', fieldName: 'coverage', type: 'number' },
    { label: 'Minimum Required', fieldName: 'minimumRequired', type: 'number' },
    { label: 'Difference', fieldName: 'difference', type: 'number' },
    { label: 'Status', fieldName: 'status', type: 'text' }
];

get showSourceValidationCard() {
    return this.sourceValidationDisplayItems.length > 0;
}

get overallSourceValidationStatus() {

    if (!this.sourceValidationData) {
        return '—';
    }

    const testStatus =
        this.sourceValidationData?.sourceValidation?.overallStatus;

    const coverageStatus =
        this.sourceValidationData?.coverageValidation?.overallStatus;

    if (testStatus === 'PASS' && coverageStatus === 'PASS') {
        return 'PASS';
    }

    if (testStatus === 'FAIL' || coverageStatus === 'FAIL') {
        return 'FAIL';
    }

    return testStatus || coverageStatus || '—';

}

get overallSourceValidationBadgeClass() {
    return this._getPassFailBadgeClass(
        this.overallSourceValidationStatus
    );
}

get sourceValidationQualityGate() {
    return this.overallSourceValidationStatus;
}

get sourceValidationQualityGateBadgeClass() {
    return this.overallSourceValidationBadgeClass;
}

get sourceValidationExecutionTime() {
    return this.sourceValidationData?.sourceValidation?.executionTime || '—';
}

get showDeploymentValidationCard() {
    return !!this.deploymentValidationDisplay;
}

get showDeploymentPlanner() {
    return this.showDeploymentValidationCard &&
        this.plannerRows.length > 0;
}

get showPlannerMenuScrollPad() {
    return this.plannerRows.length >= 9;
}

get deploymentPlannerRows() {
    return this.plannerRows;
}

metadataValidationColumns = [
    { label: 'Metadata', fieldName: 'displayMetadataName', type: 'text' },
    { label: 'Ready', fieldName: 'readyLabel', type: 'text' },
    { label: 'Missing', fieldName: 'missingLabel', type: 'text' },
    { label: 'Invalid', fieldName: 'invalidLabel', type: 'text' }
];

dependencyValidationColumns = [
    { label: 'Dependency', fieldName: 'name', type: 'text' },
    { label: 'Exists', fieldName: 'existsLabel', type: 'text' },
    { label: 'Included in Deployment', fieldName: 'includedLabel', type: 'text' },
    { label: 'Status', fieldName: 'status', type: 'text' }
];

_resolveDependencyExistsDisplay(row) {
    if (row.existsInDestination === true) {
        return {
            existsLabel: 'Already Exists',
            existsBadgeClass: 'slds-badge slds-theme_success'
        };
    }

    if (row.includedInDeploymentPackage === true) {
        return {
            existsLabel: 'Included for Deployment',
            existsBadgeClass: 'slds-badge dependency-exists-badge_included'
        };
    }

    return {
        existsLabel: 'Not Included',
        existsBadgeClass: 'slds-badge slds-theme_error'
    };
}

_initializeDeploymentPlannerSelections(validationData) {
    const rows = this._buildDeploymentPlannerRowDefinitions(validationData);
    const selections = {};

    rows.forEach((row) => {
        selections[row.key] = 'Deploy';
    });

    this.deploymentPlannerSelections = selections;
    this._refreshPlannerRows();
}

_refreshPlannerRows() {
    this.plannerRows = this._buildDeploymentPlannerRows();
}

_buildDeploymentPlannerRows() {
    const definitions = this._buildDeploymentPlannerRowDefinitions(
        this.deploymentValidationData
    );

    return definitions.map((row) => {
        const selection =
            this.deploymentPlannerSelections[row.key] || 'Deploy';

        return {
            ...row,
            selection,
            isDeploySelected: selection === 'Deploy',
            isSkipSelected: selection === 'Skip',
            selectionDisabled: row.isMandatory === true,
            categoryBadgeClass: row.isMandatory
                ? 'slds-badge slds-theme_warning'
                : 'slds-badge slds-theme_success',
            categoryLabel: row.isMandatory ? 'Mandatory' : 'Optional',
            statusBadgeClass: row.isMandatory
                ? 'slds-badge dependency-exists-badge_included'
                : 'slds-badge slds-theme_success',
            menuIdentities: [
                {
                    id: `${row.key}::${selection}`,
                    selection
                }
            ]
        };
    });
}

_buildDeploymentPlannerRowDefinitions(validationData) {
    if (!validationData) {
        return [];
    }

    const rows = [];
    const seen = new Set();

    const selectedPrimary = (this.savedComparisonResults || []).filter(
        (file) => file.Selected_For_Deployment__c === true
    );

    selectedPrimary.forEach((file, index) => {
        const filePath = file.File_Path__c || '';
        const key = `primary:${filePath || file.Id || index}`;
        if (seen.has(key)) {
            return;
        }
        seen.add(key);

        const changeType = file.Change_Type__c || '';
        const alreadyExists = changeType === 'MODIFIED';
        const isMandatory = !alreadyExists;

        rows.push({
            key,
            kind: 'Primary',
            metadataType: file.Metadata_Type__c || '—',
            metadataName: this._getDisplayMetadataName(
                this._extractMetadataName(file) || file.File_Name__c,
                file.Metadata_Type__c
            ),
            deploymentStatus: alreadyExists
                ? 'Already Exists'
                : 'Will Be Created',
            isMandatory,
            reason: isMandatory
                ? 'Required — not in destination (or new component)'
                : 'Optional — already exists in destination'
        });
    });

    const dependencyResults =
        validationData?.dependencyValidation?.results || [];

    dependencyResults.forEach((dep, index) => {
        const type = dep.type || 'Dependency';
        const name = dep.name || `dependency-${index}`;
        const key = `dependency:${type}:${name}`;
        if (seen.has(key)) {
            return;
        }
        seen.add(key);

        const alreadyExists = dep.existsInDestination === true;
        const isMandatory = !alreadyExists;

        rows.push({
            key,
            kind: 'Dependency',
            metadataType: type,
            metadataName: name,
            deploymentStatus: alreadyExists
                ? 'Already Exists'
                : dep.includedInDeploymentPackage
                    ? 'Included for Deployment'
                    : 'Not Included',
            isMandatory,
            reason: isMandatory
                ? 'Required — not in destination'
                : 'Optional — already exists in destination'
        });
    });

    return rows;
}

handlePlannerSelectionChange(event) {
    const key = event.currentTarget.dataset.key;
    if (!key) {
        return;
    }

    const value = event.detail.value;
    if (value !== 'Deploy' && value !== 'Skip') {
        return;
    }

    const current = this.deploymentPlannerSelections[key];
    const row = this.plannerRows.find((item) => item.key === key);
    if (row && row.isMandatory && value === 'Skip') {
        return;
    }

    if (current === value) {
        return;
    }

    this.deploymentPlannerSelections = {
        ...this.deploymentPlannerSelections,
        [key]: value
    };

    // Update only the changed row. Rebuilding every row remounts sibling
    // lightning-button-menu instances incorrectly or leaves stale labels.
    this.plannerRows = this.plannerRows.map((item) => {
        if (item.key !== key) {
            return item;
        }
        return {
            ...item,
            selection: value,
            isDeploySelected: value === 'Deploy',
            isSkipSelected: value === 'Skip',
            menuIdentities: [
                {
                    id: `${item.key}::${value}`,
                    selection: value
                }
            ]
        };
    });
}

/**
 * Keep the open Deploy/Skip menu inside the planner scrollport.
 * Presentation only — does not change selection or deployment logic.
 */
handlePlannerMenuOpen(event) {
    const scroller = this.template.querySelector('.deployment-planner-scroll');
    const trigger = event.currentTarget;
    if (
        !scroller ||
        !trigger ||
        typeof trigger.getBoundingClientRect !== 'function'
    ) {
        return;
    }

    const menuReservePx = 132;
    const triggerRect = trigger.getBoundingClientRect();
    const scrollerRect = scroller.getBoundingClientRect();
    const spaceBelow = scrollerRect.bottom - triggerRect.bottom;
    if (spaceBelow < menuReservePx) {
        scroller.scrollTop += menuReservePx - spaceBelow;
    }
}

requiredDependencyColumns = [
    { label: 'Name', fieldName: 'name', type: 'text' },
    { label: 'Type', fieldName: 'type', type: 'text' },
    {
        label: '',
        fieldName: 'iconName',
        type: 'button-icon',
        typeAttributes: {
            iconName: { fieldName: 'iconName' },
            alternativeText: 'Required',
            disabled: true,
            variant: 'bare'
        },
        fixedWidth: 48
    }
];

optionalDependencyColumns = [
    { label: 'Name', fieldName: 'name', type: 'text' },
    { label: 'Type', fieldName: 'type', type: 'text' }
];

get showDeploymentReviewCard() {
    return this.showDeploymentReview;
}

get showDeploymentReviewContent() {
    return this.deploymentReviewItems.length > 0;
}

get isReviewDeploymentDisabled() {
    return !this.selectedComparison ||
        this.selectedFileCount === 0 ||
        !this.showDeploymentReview;
}

get isValidateSourceDisabled() {
    return !this.showDeploymentReviewContent ||
        this.isLoadingSourceValidation;
}

get isValidateDeploymentDisabled() {
    return !this.showSourceValidationCard ||
        this.isLoadingDeploymentValidation ||
        this.isDeploying;
}

get showDeployButton() {
    return this._isReadyForDeployment() && this.deployCompleted !== true;
}

get showDeploymentReadinessReport() {
    return !!this.deploymentReadinessReport;
}

get showDeploymentIntelligence() {
    return !!this.deploymentIntelligenceDisplay?.hasAnySection;
}

get showOnDemandAiResolve() {
    return !!this.deploymentIntelligenceDisplay?.hasFailures;
}

get isResolveWithAiDisabled() {
    return (
        this.isResolvingWithAi ||
        !this.showOnDemandAiResolve ||
        !this.onDemandAiProvider
    );
}

get resolveWithAiButtonLabel() {
    return this.isResolvingWithAi ? 'Analyzing deployment…' : 'Resolve with AI';
}

get showOnDemandAiResult() {
    return !!this.deploymentOnDemandAiDisplay;
}

get showReportIssueButton() {
    return !!this.deploymentIntelligenceDisplay?.hasFailures;
}

get failureAnalysisBodyClass() {
    return this.isFailureAnalysisExpanded
        ? 'stage5-collapse-body'
        : 'stage5-collapse-body stage5-collapse-body_collapsed';
}

get resolutionNextActionsBodyClass() {
    return this.isResolutionNextActionsExpanded
        ? 'stage5-collapse-body'
        : 'stage5-collapse-body stage5-collapse-body_collapsed';
}

get safeSkipAnalysisBodyClass() {
    return this.isSafeSkipAnalysisExpanded
        ? 'stage5-collapse-body'
        : 'stage5-collapse-body stage5-collapse-body_collapsed';
}

get aiResolutionBodyClass() {
    return this.isAiResolutionExpanded
        ? 'stage5-collapse-body'
        : 'stage5-collapse-body stage5-collapse-body_collapsed';
}

get failureAnalysisChevron() {
    return this.isFailureAnalysisExpanded
        ? 'utility:chevrondown'
        : 'utility:chevronright';
}

get resolutionNextActionsChevron() {
    return this.isResolutionNextActionsExpanded
        ? 'utility:chevrondown'
        : 'utility:chevronright';
}

get safeSkipAnalysisChevron() {
    return this.isSafeSkipAnalysisExpanded
        ? 'utility:chevrondown'
        : 'utility:chevronright';
}

get aiResolutionChevron() {
    return this.isAiResolutionExpanded
        ? 'utility:chevrondown'
        : 'utility:chevronright';
}

get isGenerateSupportBundleDisabled() {
    return this.supportBundleGenerating === true;
}

get generateSupportBundleButtonLabel() {
    return this.supportBundleGenerating
        ? 'Generating support bundle…'
        : 'Generate Support Bundle';
}

get readinessWarningsActiveSection() {
    return this.readinessWarningsOpen ? ['compatibility-warnings'] : [];
}

get isDeployDisabled() {
    return this.isDeploying || this.isLoadingDeploymentValidation;
}

get deployButtonLabel() {
    return this.isDeploying ? 'Deploying...' : 'Deploy';
}

get deployConfirmMetadataCount() {
    return this.deploymentValidationData?.generatedDeploymentPackage?.summary?.metadataCount ?? 0;
}

get deployConfirmDependencyCount() {
    return this.deploymentValidationData?.generatedDeploymentPackage?.summary?.dependencyCount ?? 0;
}

get showAiAdvisorCard() {
    return this.aiAdvisorDisplay != null ||
        !!this.aiAdvisorUnavailableMessage;
}

get showAiAdvisorContent() {
    return !!this.aiAdvisorDisplay?.showSemanticContent;
}

get showAiAdvisorStatusOnly() {
    return !!this.aiAdvisorDisplay &&
        !this.aiAdvisorDisplay.showSemanticContent &&
        !this.aiAdvisorUnavailableMessage;
}

get aiAdvisorStatusBadgeClass() {
    return this.aiAdvisorDisplay?.statusBadgeClass ||
        'slds-badge ai-advisor-badge_neutral';
}

get aiAdvisorGroundingBadgeClass() {
    return this.aiAdvisorDisplay?.groundingBadgeClass ||
        'slds-badge ai-advisor-badge_neutral';
}

get aiAdvisorValidationWarnings() {
    return this.aiAdvisorDisplay?.validationWarnings || [];
}

get hasAiAdvisorValidationWarnings() {
    return this.aiAdvisorValidationWarnings.length > 0;
}

get aiAdvisorRiskItems() {
    return this.aiAdvisorDisplay?.riskItems || [];
}

get hasAiAdvisorRiskItems() {
    return this.aiAdvisorRiskItems.length > 0;
}

get aiAdvisorRecommendations() {
    return this.aiAdvisorDisplay?.recommendations || [];
}

get hasAiAdvisorRecommendations() {
    return this.aiAdvisorRecommendations.length > 0;
}

get aiAdvisorDiagnosticsJson() {
    return this.aiAdvisorDisplay?.diagnosticsJson || '';
}

handleAiAdvisorDiagnosticsToggle(event) {
    this.showAiAdvisorDiagnostics = event.target.checked === true;
}

_buildDeploymentReviewItems(data) {

    const items = data.deploymentReview || [];

    return items.map((item, index) => {

        const metadataKey =
            item.metadataName || `review-item-${index}`;

        const dependencyAnalysis =
            item.dependencyAnalysis || {};

        const requiredDependencies = (
            dependencyAnalysis.requiredDependencies || []
        ).map((dep, depIndex) => ({
            id: `${metadataKey}-req-${depIndex}`,
            name: dep.name || dep.metadataName || '',
            type: dep.type || dep.metadataType || '',
            iconName: 'utility:lock'
        }));

        const optionalDependencies = (
            dependencyAnalysis.optionalDependencies || []
        ).map((dep, depIndex) => ({
            id: `${metadataKey}-opt-${depIndex}`,
            name: dep.name || dep.metadataName || '',
            type: dep.type || dep.metadataType || ''
        }));

        const recommendedTestClasses = (
            dependencyAnalysis.recommendedTestClasses || []
        ).map((testClass, testIndex) => {

            const name = typeof testClass === 'string'
                ? testClass
                : (testClass.name || testClass.className || '');

            return {
                id: `${metadataKey}-test-${testIndex}`,
                name,
                selected: true
            };

        });

        const apiValidation = item.apiValidation || {};

        const apiVersion =
            apiValidation.apiVersion ||
            apiValidation.sourceApiVersion ||
            apiValidation.version ||
            '—';

        return {
            key: metadataKey,
            accordionLabel:
                `${this._getDisplayMetadataName(
                    item.metadataName,
                    item.metadataType
                )} (${item.metadataType})`,
            metadataName: item.metadataName,
            displayMetadataName: this._getDisplayMetadataName(
                item.metadataName,
                item.metadataType
            ),
            metadataType: item.metadataType,
            status: item.status || '—',
            statusBadgeClass: this._getReviewStatusBadgeClass(item.status),
            apiVersion,
            requiredDependencies,
            optionalDependencies,
            recommendedTestClasses,
            hasOptionalDependencies: optionalDependencies.length > 0,
            hasRecommendedTestClasses: recommendedTestClasses.length > 0
        };

    });

}

_initializeSelectedTestClasses(items) {

    const selectedMap = {};

    items.forEach(item => {

        selectedMap[item.key] = item.recommendedTestClasses
            .filter(testClass => testClass.selected)
            .map(testClass => testClass.name);

    });

    this.selectedTestClasses = selectedMap;

}

/**
 * Phase 2A — Detect Ignored comparison metadata that appears as a
 * required dependency in mapped Review items.
 * Uses Metadata Type + normalized Metadata Name only.
 * Does not alter intent, package, validation, or UI.
 */
_detectIgnoredDependencyConflicts() {

    // Phase 4 — always rebuild from scratch (never append across Reviews)
    this.ignoredConflicts = [];
    this.hasIgnoredDependencyConflict = false;

    const ignoredMetadata = (this.savedComparisonResults || [])
        .filter(
            (file) =>
                this._resolveDeploymentIntent(file) === 'Ignore'
        )
        .map((file) => {
            const type = file.Metadata_Type__c || '';
            const rawName =
                this._extractMetadataName(file) ||
                file.File_Name__c ||
                '';
            const name = this._getDisplayMetadataName(rawName, type) || '';
            return { name, type, matchKey: `${type}::${name}` };
        })
        .filter((entry) => entry.name && entry.type);

    // Phase 4 — unique ignored entries by Type+Name (multiple Ignore rows)
    const uniqueIgnoredByKey = new Map();
    ignoredMetadata.forEach((entry) => {
        if (!uniqueIgnoredByKey.has(entry.matchKey)) {
            uniqueIgnoredByKey.set(entry.matchKey, entry);
        }
    });
    const uniqueIgnoredMetadata = Array.from(uniqueIgnoredByKey.values());

    const conflicts = [];
    const seenConflictKeys = new Set();

    (this.deploymentReviewItems || []).forEach((item) => {
        const requiredByType = item.metadataType || '';
        const requiredByName =
            this._getDisplayMetadataName(
                item.metadataName,
                requiredByType
            ) || '';

        (item.requiredDependencies || []).forEach((dep) => {
            const depType = dep.type || '';
            const depName =
                this._getDisplayMetadataName(dep.name, depType) || '';

            if (!depName || !depType) {
                return;
            }

            const matchKey = `${depType}::${depName}`;
            const ignoredMatch = uniqueIgnoredMetadata.find(
                (ignored) => ignored.matchKey === matchKey
            );

            if (!ignoredMatch) {
                return;
            }

            const conflictKey =
                `${matchKey}<<${requiredByType}::${requiredByName}`;

            if (seenConflictKeys.has(conflictKey)) {
                return;
            }
            seenConflictKeys.add(conflictKey);

            conflicts.push({
                ignoredMetadata: {
                    name: ignoredMatch.name,
                    type: ignoredMatch.type
                },
                requiredBy: {
                    name: requiredByName,
                    type: requiredByType
                },
                reason: 'Required Dependency',
                resolution: 'Pending'
            });
        });
    });

    this.ignoredConflicts = conflicts;
    this.hasIgnoredDependencyConflict = conflicts.length > 0;
}

/**
 * Phase 2B — Flatten ignoredConflicts for lightning-datatable display.
 * Phase 4 — deduplicate display rows (Ignored + Type + Required By).
 */
get ignoredConflictTableRows() {
    const seen = new Set();
    const rows = [];

    (this.ignoredConflicts || []).forEach((conflict, index) => {
        const ignoredMetadata = conflict.ignoredMetadata?.name || '';
        const type = conflict.ignoredMetadata?.type || '';
        const requiredBy = conflict.requiredBy?.name || '';
        const reason = conflict.reason || '';
        const rowKey = `${type}::${ignoredMetadata}<<${requiredBy}`;

        if (seen.has(rowKey)) {
            return;
        }
        seen.add(rowKey);

        rows.push({
            id: `ignored-conflict-${index}`,
            ignoredMetadata,
            type,
            requiredBy,
            reason
        });
    });

    return rows;
}

ignoredConflictColumns = [
    { label: 'Ignored Metadata', fieldName: 'ignoredMetadata', type: 'text' },
    { label: 'Type', fieldName: 'type', type: 'text' },
    { label: 'Required By', fieldName: 'requiredBy', type: 'text' },
    { label: 'Reason', fieldName: 'reason', type: 'text' }
];

/** Phase 4 — disable Include/Cancel while Include or Review is in flight. */
get isIgnoredDependencyActionDisabled() {
    return this.isIncludingRequiredMetadata || this.isLoadingDeploymentReview;
}

closeIgnoredDependencyModal() {
    // Phase 4 — do not dismiss while Include/Review is running
    if (this.isIgnoredDependencyActionDisabled) {
        return;
    }
    this.showIgnoredDependencyModal = false;
}

/**
 * Phase 3 — Resolve Comparison_Result Id for an ignored conflict row.
 * Matches Type + normalized Name only (same helpers as detection).
 * Does not modify conflict detection.
 */
_findIgnoredComparisonResultId(conflict) {
    const ignoredType = conflict?.ignoredMetadata?.type || '';
    const ignoredName = conflict?.ignoredMetadata?.name || '';

    if (!ignoredType || !ignoredName) {
        return null;
    }

    const match = (this.savedComparisonResults || []).find((file) => {
        if (this._resolveDeploymentIntent(file) !== 'Ignore') {
            return false;
        }

        const type = file.Metadata_Type__c || '';
        const rawName =
            this._extractMetadataName(file) ||
            file.File_Name__c ||
            '';
        const name = this._getDisplayMetadataName(rawName, type) || '';

        return type === ignoredType && name === ignoredName;
    });

    return match?.Id || null;
}

/**
 * Phase 3 — Include all ignored conflict metadata as Deploy, refresh
 * comparison from Salesforce, then re-run existing Review Deployment.
 */
handleIncludeRequiredMetadata() {
    if (this.isIncludingRequiredMetadata || this.isLoadingDeploymentReview) {
        return;
    }

    const conflicts = this.ignoredConflicts || [];
    if (!conflicts.length) {
        this.showIgnoredDependencyModal = false;
        return;
    }

    const resultIds = [];
    const seenIds = new Set();

    conflicts.forEach((conflict) => {
        const resultId = this._findIgnoredComparisonResultId(conflict);
        if (resultId && !seenIds.has(resultId)) {
            seenIds.add(resultId);
            resultIds.push(resultId);
        }
    });

    if (!resultIds.length) {
        console.error(
            'Include Required Metadata: no Comparison_Result Ids matched'
        );
        return;
    }

    const includeComparisonId = this.selectedComparison;
    this.isIncludingRequiredMetadata = true;

    Promise.all(
        resultIds.map((resultId) =>
            updateIntent({
                resultId,
                intent: 'Deploy'
            })
        )
    )
        .then(() => {
            if (this.selectedComparison !== includeComparisonId) {
                return null;
            }
            // State always rebuilt from Salesforce after updateIntent
            return this.loadSavedComparisonResults();
        })
        .then(() => {
            if (this.selectedComparison !== includeComparisonId) {
                return null;
            }
            return this.handleReviewDeployment();
        })
        .catch((error) => {
            console.error(error);
        })
        .finally(() => {
            this.isIncludingRequiredMetadata = false;
        });
}

_getReviewStatusBadgeClass(status) {

    const normalized = (status || '').toLowerCase();

    if (normalized === 'ready' || normalized === 'passed') {
        return 'slds-badge slds-theme_success';
    }

    if (normalized === 'blocked' || normalized === 'failed') {
        return 'slds-badge slds-theme_error';
    }

    if (normalized === 'warning') {
        return 'slds-badge slds-theme_warning';
    }

    return 'slds-badge slds-theme_info';

}

handleReviewDeployment() {

    if (!this.selectedComparison) {
        alert('Please select a comparison');
        return Promise.resolve();
    }

    const reviewComparisonId = this.selectedComparison;

    const selectedMetadata =
        this.savedComparisonResults
            .filter(
                file =>
                    file.Selected_For_Deployment__c === true
            )
            .map(file => ({
                metadataType: file.Metadata_Type__c,
                filePath: file.File_Path__c
            }));

    this.isLoadingDeploymentReview = true;

    // Phase 4 — clear prior conflict set before rebuild (no accumulation)
    this.ignoredConflicts = [];
    this.hasIgnoredDependencyConflict = false;

    return getDeploymentReview({
        comparisonId: reviewComparisonId,
        selectedMetadataJson: JSON.stringify(selectedMetadata)
    })
    .then(result => {

        // Phase 4 — ignore stale Review if comparison changed mid-flight
        if (this.selectedComparison !== reviewComparisonId) {
            this.isLoadingDeploymentReview = false;
            this.showIgnoredDependencyModal = false;
            this.ignoredConflicts = [];
            this.hasIgnoredDependencyConflict = false;
            return;
        }

        this.deploymentReviewData = JSON.parse(result);

        const items =
            this._buildDeploymentReviewItems(
                this.deploymentReviewData
            );

        this.deploymentReviewItems = items;

        this._detectIgnoredDependencyConflicts();

        if (this.hasIgnoredDependencyConflict) {
            this.showIgnoredDependencyModal = true;
        } else {
            this.showIgnoredDependencyModal = false;
        }

        this._initializeSelectedTestClasses(items);

        this.isLoadingDeploymentReview = false;

        // Persist latest Review snapshot for this plan (non-blocking).
        // Preserves existing session semantics: does not clear Source/Deploy Validation.
        this._persistPlanSnapshot(
            saveLatestReviewSnapshot,
            {
                deploymentPlanId: this.currentDeploymentPlanId,
                reviewJson: result,
                status: this._resolveReviewSnapshotStatus(
                    this.deploymentReviewData
                )
            },
            'Deployment Review'
        );

    })
    .catch(error => {

        console.error(error);

        this.deploymentReviewItems = [];
        this.ignoredConflicts = [];
        this.hasIgnoredDependencyConflict = false;
        this.showIgnoredDependencyModal = false;

        this.isLoadingDeploymentReview = false;

    });

}

handleTestClassSelection(event) {

    const metadataKey = event.target.dataset.metadata;
    const testClassName = event.target.dataset.testclass;
    const checked = event.target.checked;

    this.deploymentReviewItems = this.deploymentReviewItems.map(item => {

        if (item.key !== metadataKey) {
            return item;
        }

        const recommendedTestClasses =
            item.recommendedTestClasses.map(testClass => {

                if (testClass.name === testClassName) {
                    return { ...testClass, selected: checked };
                }

                return testClass;

            });

        return { ...item, recommendedTestClasses };

    });

    const currentSelection =
        this.selectedTestClasses[metadataKey] || [];

    if (checked) {

        this.selectedTestClasses = {
            ...this.selectedTestClasses,
            [metadataKey]: [...currentSelection, testClassName]
        };

    } else {

        this.selectedTestClasses = {
            ...this.selectedTestClasses,
            [metadataKey]: currentSelection.filter(
                name => name !== testClassName
            )
        };

    }

}

handleValidateSource() {

    if (!this.deploymentReviewItems.length) {
        alert('Please run Deployment Review first');
        return;
    }

    if (!this.selectedComparisonDetails?.Source_Org__r) {
        alert('Source org details not available');
        return;
    }

    const sourceOrg =
        this.selectedComparisonDetails.Source_Org__r;

    const deploymentPackage = this._buildDeploymentPackage();

    this.isLoadingSourceValidation = true;

    validateSource({
        refreshToken: sourceOrg.Refresh_Token__c,
        instanceUrl: sourceOrg.Instance_URL__c,
        orgId: sourceOrg.Org_ID__c,
        deploymentPackage: JSON.stringify(deploymentPackage)
    })
    .then(result => {

        this.sourceValidationData = JSON.parse(result);

        this.sourceValidationDisplayItems =
            this._buildSourceValidationDisplayItems(
                this.sourceValidationData
            );

        this.isLoadingSourceValidation = false;

        // Guided navigation — Stage 4 COMPLETE / Stage 5 READY on PASS only.
        // Reuses overallSourceValidationStatus (Overall Validation + Quality Gate).
        if (this.canOpenStage5) {
            this.activeLifecycleStage = 5;
        }

        // Persist latest Source Validation snapshot (non-blocking).
        this._persistPlanSnapshot(
            saveLatestSourceValidationSnapshot,
            {
                deploymentPlanId: this.currentDeploymentPlanId,
                sourceValidationJson: result,
                status: this.overallSourceValidationStatus || 'COMPLETED'
            },
            'Source Validation'
        );

    })
    .catch(error => {

        console.error(error);

        this.sourceValidationData = null;

        this.sourceValidationDisplayItems = [];

        this.isLoadingSourceValidation = false;

    });

}

handleValidateDeployment() {

    if (!this.deploymentReviewItems.length) {
        alert('Please run Deployment Review first');
        return;
    }

    if (!this.selectedComparisonDetails?.Destination_Org__r) {
        alert('Destination org details not available');
        return;
    }

    // Harden: prevent overlapping validation cycles / duplicate popup opens
    if (this.isLoadingDeploymentValidation) {
        return;
    }

    const destinationOrg =
        this.selectedComparisonDetails.Destination_Org__r;

    const deploymentPackage = this._buildDeploymentPackage();

    const validationComparisonId = this.selectedComparison;

    // Harden: start each validation run with a clean Stage 5 info-popup cycle
    // (closes any prior popup; prevents reopen from stale view-model mid-flight).
    this.showIgnoredAutoIncludedModal = false;
    this.ignoredAutoIncludedMetadata = [];
    this.deploymentPackageProvenance = null;

    this.stopValidationPolling();
    this.activeValidationId = null;
    this.validationStatusMessage = 'Starting validation…';
    this._validationComparisonId = validationComparisonId;

    this.isLoadingDeploymentValidation = true;
    this._clearAiAdvisor();

    startDeploymentValidation({
        refreshToken: destinationOrg.Refresh_Token__c,
        instanceUrl: destinationOrg.Instance_URL__c,
        orgId: destinationOrg.Org_ID__c,
        deploymentPackage: JSON.stringify(deploymentPackage)
    })
    .then(result => {

        // Discard stale Validation if comparison changed mid-flight
        if (this.selectedComparison !== validationComparisonId) {
            this.stopValidationPolling();
            this.isLoadingDeploymentValidation = false;
            this.activeValidationId = null;
            this.validationStatusMessage = '';
            this.showIgnoredAutoIncludedModal = false;
            this.ignoredAutoIncludedMetadata = [];
            this.deploymentPackageProvenance = null;
            return;
        }

        const startResponse = JSON.parse(result);
        const validationId = startResponse?.validationId;
        const startStatus = startResponse?.status;

        if (
            !validationId ||
            startResponse?.success === false ||
            (startStatus && startStatus !== 'RUNNING')
        ) {
            this._handleValidationTransportFailure(
                startResponse?.error ||
                    'Unable to start deployment validation.'
            );
            return;
        }

        // Job accepted — keep spinner ON; do not treat as validation success.
        this.activeValidationId = validationId;
        this.validationStatusMessage = 'Validation running…';
        this._startValidationPolling();

    })
    .catch(error => {

        console.error(error);

        this._handleValidationTransportFailure(
            error?.body?.message ||
                error?.message ||
                'Unable to start deployment validation.'
        );

    });

}

/**
 * Dedicated validation poll cleanup — does not touch retrieval statusPollingInterval.
 */
stopValidationPolling() {
    if (this.validationPollingInterval) {
        clearInterval(this.validationPollingInterval);
        this.validationPollingInterval = null;
    }
}

_startValidationPolling() {
    this.stopValidationPolling();

    // Immediate first status check, then every 5s (same interval as retrieval).
    this.checkValidationStatus();

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.validationPollingInterval = setInterval(() => {
        this.checkValidationStatus();
    }, 5000);
}

checkValidationStatus() {
    const validationId = this.activeValidationId;
    if (!validationId || !this.isLoadingDeploymentValidation) {
        return;
    }

    const validationComparisonId = this._validationComparisonId;

    getValidationStatus({ validationId })
        .then(result => {
            if (
                this.selectedComparison !== validationComparisonId ||
                this.activeValidationId !== validationId
            ) {
                return;
            }

            const response = JSON.parse(result);
            const status = response?.status;

            if (status === 'RUNNING') {
                // Keep spinner ON. RUNNING ≠ SUCCESS / canDeploy.
                this.validationStatusMessage = 'Validation running…';
                this.isLoadingDeploymentValidation = true;
                return;
            }

            if (status === 'COMPLETED') {
                this.stopValidationPolling();
                this.validationStatusMessage = '';
                this.activeValidationId = null;

                const validationResult = response?.result;
                if (!validationResult || typeof validationResult !== 'object') {
                    this._handleValidationTransportFailure(
                        'Validation completed but returned no result.'
                    );
                    return;
                }

                // Pass response.result through the exact existing success path.
                this._applyDeploymentValidationSuccessResponse(
                    validationResult,
                    validationComparisonId
                );
                return;
            }

            if (status === 'FAILED') {
                this.stopValidationPolling();
                this.activeValidationId = null;
                this.validationStatusMessage = '';

                const errorMessage =
                    response?.error ||
                    'Deployment validation failed.';

                // If backend included a partial/full result, surface it via
                // the same processing path without inventing readiness.
                if (
                    response?.result &&
                    typeof response.result === 'object'
                ) {
                    this._applyDeploymentValidationSuccessResponse(
                        response.result,
                        validationComparisonId
                    );
                } else {
                    this._clearFailedValidationUiState();
                }

                this.isLoadingDeploymentValidation = false;

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Validation Failed',
                        message: errorMessage,
                        variant: 'error',
                        mode: 'sticky'
                    })
                );
                return;
            }

            // 404 / unknown job / unexpected payload — stop; do not retry forever.
            const notFound =
                response?.success === false ||
                String(response?.error || '')
                    .toLowerCase()
                    .includes('not found') ||
                response?.statusCode === 404;

            if (notFound || !status) {
                this.stopValidationPolling();
                this._handleValidationTransportFailure(
                    response?.error ||
                        'Validation job not found.'
                );
            }
        })
        .catch(error => {
            console.error('Validation status check error', error);

            if (
                this.selectedComparison !== validationComparisonId ||
                this.activeValidationId !== validationId
            ) {
                return;
            }

            this.stopValidationPolling();
            this._handleValidationTransportFailure(
                error?.body?.message ||
                    error?.message ||
                    'Validation status check failed.'
            );
        });
}

/**
 * Existing successful-validation processing path.
 * Async COMPLETED must pass response.result into this exact logic.
 */
_applyDeploymentValidationSuccessResponse(
    response,
    validationComparisonId
) {
    // Discard stale Validation if comparison changed mid-flight
    if (this.selectedComparison !== validationComparisonId) {
        this.stopValidationPolling();
        this.isLoadingDeploymentValidation = false;
        this.showIgnoredAutoIncludedModal = false;
        this.ignoredAutoIncludedMetadata = [];
        this.deploymentPackageProvenance = null;
        return;
    }

    this._applyDeploymentValidationUiState(response, {
        openIgnoredAutoIncludedModal: true,
        persistHistory: true,
        requestAi: true,
        persistSnapshot: true
    });
}

/**
 * Side-effect-free UI rebuild used by hydration.
 * Does not persist History, request AI, open modals, or save snapshots.
 */
_hydrateDeploymentValidationUiState(response) {
    this._applyDeploymentValidationUiState(response, {
        openIgnoredAutoIncludedModal: false,
        persistHistory: false,
        requestAi: false,
        persistSnapshot: false
    });
}

/**
 * Shared Deployment Validation presentation builder.
 * Live path enables side effects; hydration path keeps them off.
 */
_applyDeploymentValidationUiState(response, options = {}) {
    const openIgnoredAutoIncludedModal =
        options.openIgnoredAutoIncludedModal === true;
    const persistHistory = options.persistHistory === true;
    const requestAi = options.requestAi === true;
    const persistSnapshot = options.persistSnapshot === true;

    this.deploymentValidationData = response;

    // Store optional provenance only — no UI / planner / package action.
    this.deploymentPackageProvenance =
        response &&
        Object.prototype.hasOwnProperty.call(
            response,
            'deploymentPackageProvenance'
        ) &&
        response.deploymentPackageProvenance != null
            ? response.deploymentPackageProvenance
            : null;

    // Processing layer only — builds ignoredAutoIncludedMetadata view model.
    this._processDeploymentPackageProvenance();

    this.deploymentValidationDisplay =
        this._buildDeploymentValidationDisplay(
            this.deploymentValidationData
        );

    this._applyDeploymentIntelligenceReports(
        this.deploymentValidationData
    );

    this.deploymentReadinessReport =
        this._buildDeploymentReadinessReport(
            this.deploymentValidationData
        );
    this.readinessWarningsOpen = false;

    this._initializeDeploymentPlannerSelections(
        this.deploymentValidationData
    );

    this.isLoadingDeploymentValidation = false;

    // Fresh validation unlocks Deploy again after a prior successful deploy.
    this.deployCompleted = false;

    // Capture backend in-memory historyId for Support Bundle correlation.
    this.backendValidationHistoryId =
        response?.deploymentHistory?.historyId ||
        response?.deploymentHistory?.id ||
        null;
    this._clearSupportBundleState();

    // Presentation only — open once after live processing; never during hydrate.
    this.showIgnoredAutoIncludedModal = false;
    if (
        openIgnoredAutoIncludedModal &&
        this.hasIgnoredAutoIncludedMetadata
    ) {
        this.showIgnoredAutoIncludedModal = true;
    }

    // Persist deployment history independently — live path only.
    if (persistHistory && response && response.deploymentHistory) {
        this._persistDeploymentHistory(response.deploymentHistory);
    }

    // Phase 10F — advisory only; never on hydrate.
    if (requestAi) {
        this._requestAiAdvisor();
    }

    // Persist latest Deployment Validation snapshot — live path only.
    if (persistSnapshot && response) {
        this._persistPlanSnapshot(
            saveLatestDeploymentValidationSnapshot,
            {
                deploymentPlanId: this.currentDeploymentPlanId,
                deploymentValidationJson: JSON.stringify(response),
                status: this._resolveDeploymentValidationSnapshotStatus(
                    response
                )
            },
            'Deployment Validation'
        );
    }
}

_clearFailedValidationUiState() {
    this.deploymentValidationData = null;
    this.deploymentValidationDisplay = null;
    this._clearDeploymentIntelligenceReports();
    this.deploymentReadinessReport = null;
    this.readinessWarningsOpen = false;
    this.backendValidationHistoryId = null;
    this._clearSupportBundleState();
    this.deploymentPackageProvenance = null;
    this.ignoredAutoIncludedMetadata = [];
    this.showIgnoredAutoIncludedModal = false;
    this.deploymentPlannerSelections = {};
    this.plannerRows = [];
    this._clearAiAdvisor();
}

_handleValidationTransportFailure(message) {
    this.stopValidationPolling();
    this.activeValidationId = null;
    this.validationStatusMessage = '';
    this._validationComparisonId = null;
    this._clearFailedValidationUiState();
    this.isLoadingDeploymentValidation = false;

    this.dispatchEvent(
        new ShowToastEvent({
            title: 'Validation Error',
            message: message || 'Deployment validation failed.',
            variant: 'error',
            mode: 'sticky'
        })
    );
}

/**
 * True when processing found Ignored + AUTO_INCLUDED members.
 * Used by informational popup only.
 */
get hasIgnoredAutoIncludedMetadata() {
    return (this.ignoredAutoIncludedMetadata || []).length > 0;
}

/**
 * Presentation — flatten ignoredAutoIncludedMetadata for lightning-datatable.
 * Reads view model only; never reads deploymentPackageProvenance.
 */
get ignoredAutoIncludedTableRows() {
    return (this.ignoredAutoIncludedMetadata || []).map((item, index) => ({
        id: `ignored-auto-included-${index}`,
        metadataName: item.metadataName || '',
        metadataType: item.metadataType || '',
        packageRole: item.packageRole || '',
        origins: this._formatIgnoredAutoIncludedOrigins(item.origins)
    }));
}

ignoredAutoIncludedColumns = [
    { label: 'Metadata Name', fieldName: 'metadataName', type: 'text' },
    { label: 'Metadata Type', fieldName: 'metadataType', type: 'text' },
    { label: 'Package Role', fieldName: 'packageRole', type: 'text' },
    { label: 'Origins', fieldName: 'origins', type: 'text', wrapText: true }
];

_formatIgnoredAutoIncludedOrigins(origins) {
    if (!Array.isArray(origins) || !origins.length) {
        return '—';
    }

    const labels = origins
        .map((origin) => {
            if (origin == null) {
                return '';
            }
            if (typeof origin === 'string') {
                return origin;
            }
            if (typeof origin !== 'object') {
                return String(origin);
            }
            return [origin.type, origin.name, origin.reason, origin.source]
                .filter((part) => part != null && String(part).trim() !== '')
                .join(' / ');
        })
        .filter((label) => label);

    return labels.length ? labels.join('; ') : '—';
}

closeIgnoredAutoIncludedModal() {
    this.showIgnoredAutoIncludedModal = false;
}

/**
 * Close info popup and show Stage 5 workspace (Deployment Planner).
 * Does not change planner selections, intent, or validation.
 */
handleOpenDeploymentPlannerFromAutoIncluded() {
    this.showIgnoredAutoIncludedModal = false;
    this.activeLifecycleStage = 5;
}

/**
 * Processing layer: convert deploymentPackageProvenance into a UI view model of
 * members that are AUTO_INCLUDED and Ignore-intent on the current comparison.
 * Does not mutate provenance, package, planner, or deployment decisions.
 */
_processDeploymentPackageProvenance() {
    this.ignoredAutoIncludedMetadata = [];

    const provenance = this.deploymentPackageProvenance;
    if (!provenance || typeof provenance !== 'object') {
        return;
    }

    const members = Array.isArray(provenance.members)
        ? provenance.members
        : [];

    if (!members.length) {
        return;
    }

    const ignoredByKey = new Map();

    (this.savedComparisonResults || []).forEach((file) => {
        if (this._resolveDeploymentIntent(file) !== 'Ignore') {
            return;
        }

        const type = file.Metadata_Type__c || '';
        const rawName =
            this._extractMetadataName(file) ||
            file.File_Name__c ||
            '';
        const name = this._getDisplayMetadataName(rawName, type) || '';

        if (!type || !name) {
            return;
        }

        const key = `${type}::${name}`;
        if (!ignoredByKey.has(key)) {
            ignoredByKey.set(key, { type, name });
        }
    });

    if (!ignoredByKey.size) {
        return;
    }

    const seenKeys = new Set();
    const viewModel = [];

    members.forEach((member) => {
        if (!member || typeof member !== 'object') {
            return;
        }

        if (member.packageRole !== 'AUTO_INCLUDED') {
            return;
        }

        const type = member.metadataType || member.type || '';
        const rawName = member.metadataName || member.name || '';
        const name = this._getDisplayMetadataName(rawName, type) || '';

        if (!type || !name) {
            return;
        }

        const key = `${type}::${name}`;
        if (!ignoredByKey.has(key) || seenKeys.has(key)) {
            return;
        }
        seenKeys.add(key);

        let origins = [];
        if (Array.isArray(member.origins)) {
            origins = member.origins.map((origin) => {
                if (origin == null || typeof origin !== 'object') {
                    return origin;
                }
                return {
                    type: origin.type,
                    name: origin.name,
                    reason: origin.reason,
                    source: origin.source
                };
            });
        }

        viewModel.push({
            metadataType: type,
            metadataName: name,
            packageRole: 'AUTO_INCLUDED',
            origins
        });
    });

    this.ignoredAutoIncludedMetadata = viewModel;
}

_persistDeploymentHistory(deploymentHistory) {

    saveDeploymentHistory({
        deploymentHistoryJson: JSON.stringify(deploymentHistory)
    })
    .then(result => {

        if (result && result.success === true) {
            this.historyRecordId = result.recordId;
            console.log(
                'Deployment history saved:',
                this.historyRecordId
            );
            return;
        }

        console.error(
            'Deployment history save failed:',
            result ? result.message : 'Unknown error'
        );

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Warning',
                message: 'Deployment history could not be saved.',
                variant: 'warning',
                mode: 'dismissable'
            })
        );

    })
    .catch(error => {

        console.error('Deployment history save error:', error);

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Warning',
                message: 'Deployment history could not be saved.',
                variant: 'warning',
                mode: 'dismissable'
            })
        );

    });

}

handleDeploy() {

    if (this.isDeploying || this.deployCompleted) {
        return;
    }

    if (!this.showDeployButton) {
        return;
    }

    this.showDeployConfirmation = true;

}

/**
 * Stage 5 readiness checkpoint — navigate to Stage 6 only.
 * Does not open confirmation or start deployment.
 */
handleReadinessReportDeploy() {
    this.activeLifecycleStage = 6;
}

/**
 * Phase 11.5 — Cancel when ready (no deploy started).
 */
handleReadinessReportCancel() {
    // Presentation only — no workflow mutation.
}

/**
 * Phase 11.5 — Close when blocked (no deploy started).
 */
handleReadinessReportClose() {
    // Presentation only — no workflow mutation.
}

/**
 * Phase 11.5 — Expand compatibility warnings for blocked reviews.
 */
handleReviewCompatibility() {
    this.readinessWarningsOpen = true;

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.setTimeout(() => {
        const el = this.template.querySelector(
            '[data-id="readiness-compatibility-warnings"]'
        );
        if (el && typeof el.scrollIntoView === 'function') {
            el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }, 50);
}

handleReadinessWarningsSectionToggle(event) {
    const openSections = event.detail?.openSections;
    if (Array.isArray(openSections)) {
        this.readinessWarningsOpen =
            openSections.includes('compatibility-warnings');
        return;
    }
    this.readinessWarningsOpen =
        openSections === 'compatibility-warnings';
}

handleOnDemandAiProviderChange(event) {
    const value = event?.detail?.value || event?.target?.value || 'gemini';
    this.onDemandAiProvider =
        value === 'openai' || value === 'gpt' ? value : 'gemini';
}

handleResolveWithAi() {
    if (this.isResolveWithAiDisabled) {
        return;
    }

    const context = this._buildOnDemandAiResolutionContext();
    if (!context) {
        this.onDemandAiErrorMessage =
            'AI Resolution requires a completed deployment validation with failure context.';
        return;
    }

    this.isResolvingWithAi = true;
    this.onDemandAiErrorMessage = null;

    resolveWithAi({
        provider: this.onDemandAiProvider || 'gemini',
        contextJson: JSON.stringify(context)
    })
        .then((result) => {
            let response;
            try {
                response = JSON.parse(result);
            } catch (parseError) {
                console.error(parseError);
                this.onDemandAiErrorMessage =
                    'AI Resolution returned an invalid response.';
                return;
            }

            const report = response?.aiResolutionReport || null;

            if (
                response?.success === false &&
                (!report || report.available !== true)
            ) {
                this.onDemandAiErrorMessage =
                    response?.error ||
                    'AI Resolution is currently unavailable.';
                if (report) {
                    this.deploymentOnDemandAiResolution = report;
                    this.deploymentOnDemandAiDisplay =
                        this._buildOnDemandAiResolutionDisplay(report);
                }
                return;
            }

            if (!report) {
                this.onDemandAiErrorMessage =
                    'AI Resolution is currently unavailable.';
                return;
            }

            this.deploymentOnDemandAiResolution = report;
            this.deploymentOnDemandAiDisplay =
                this._buildOnDemandAiResolutionDisplay(report);

            if (report.available !== true) {
                this.onDemandAiErrorMessage =
                    report.disclaimer ||
                    'AI Resolution is currently unavailable.';
            }
        })
        .catch((error) => {
            console.error(error);
            this.onDemandAiErrorMessage =
                'AI Resolution is currently unavailable. Validation results remain valid.';
        })
        .finally(() => {
            this.isResolvingWithAi = false;
        });
}

/**
 * Build allowed on-demand AI context from stored validation reports only.
 * Uses a slim transport projection — does not mutate deploymentValidationData.
 */
_buildOnDemandAiResolutionContext() {
    return this._buildAiResolutionTransportContext(
        this.deploymentValidationData
    );
}

/**
 * Dedicated slim AI Resolution transport builder.
 * Mirrors backend buildStructuredContext / collectKnownItems consumption.
 */
_buildAiResolutionTransportContext(data) {
    const context = buildAiResolutionTransportContext(data);
    if (!context) {
        return null;
    }

    // DEBUG-ONLY size diagnostic — no tokens / full payload logged.
    try {
        const size = measureAiResolutionRequestSize(
            this.onDemandAiProvider || 'gemini',
            context
        );
        // eslint-disable-next-line no-console
        console.debug(
            '[AI Resolution transport] payloadBytes=' +
                size.payloadBytes +
                ' contextBytes=' +
                size.contextBytes +
                ' factPackComponents=' +
                size.factPackComponentCount +
                ' failures=' +
                size.failureCount
        );
    } catch (_ignore) {
        // Diagnostic only — never block Resolve with AI.
    }

    return context;
}

/**
 * Presentation-only on-demand AI result. Backend SAFE_SKIP / Phase 2A fields
 * remain authoritative — this method only maps them for display.
 */
_buildOnDemandAiResolutionDisplay(report) {
    if (!report || typeof report !== 'object') {
        return null;
    }

    const available = report.available === true;
    const explanations = Array.isArray(report.explanations)
        ? report.explanations
        : [];

    const explanationRows = explanations.map((item, index) => {
        const rowId = `ondemand-ai-${index}`;
        const backendSkip = this._findBackendSafeSkipDecision(
            item.metadataType,
            item.metadataName
        );
        const backendMapped = backendSkip
            ? this._mapSafeSkipDecisionDisplay(backendSkip)
            : null;
        const phase2a = mapPhase2aExplanationDisplay(item, rowId);

        return {
            id: rowId,
            detailId: `stage5-ai-card-detail-${index}`,
            isExpanded: false,
            chevronIcon: 'utility:chevronright',
            detailClass:
                'stage5-ai-card-detail stage5-ai-card-detail_collapsed',
            metadataType: item.metadataType || '—',
            metadataName: item.metadataName || '—',
            severity: item.severity || '—',
            title: item.title || 'Guidance',
            why: item.why || '',
            impact: item.impact || '',
            recommendedAction: item.recommendedAction || '',
            bestPractice: item.bestPractice || '',
            confidence:
                item.confidence != null ? String(item.confidence) : '',
            resolutionCategory: item.resolutionCategory || '—',
            // Phase 2A — backend-authoritative display fields
            fixOwnerLabel: phase2a.fixOwnerLabel,
            showBackendResolution: phase2a.showBackendResolution,
            backendResolution: phase2a.backendResolution,
            sourceFacts: phase2a.sourceFacts,
            destinationFacts: phase2a.destinationFacts,
            conflictDisplay: phase2a.conflictDisplay,
            resolutionDisplay: phase2a.resolutionDisplay,
            showBackendCanAutoFixStatus: phase2a.showBackendCanAutoFixStatus,
            backendCanAutoFixStatus: phase2a.backendCanAutoFixStatus,
            showUserActionRequired: phase2a.showUserActionRequired,
            userActionRequiredBanner: phase2a.userActionRequiredBanner,
            showAiSafeToSkip: phase2a.showAiSafeToSkip,
            aiSafeToSkipLabel: phase2a.aiSafeToSkipLabel,
            // Legacy Yes/No labels retained for older templates/tests
            backendCanAutoFixLabel:
                item.backendCanAutoFix === true
                    ? 'Yes'
                    : item.backendCanAutoFix === false
                      ? 'No'
                      : '—',
            userActionRequiredLabel:
                item.userActionRequired === true
                    ? 'Yes'
                    : item.userActionRequired === false
                      ? 'No'
                      : '—',
            skipGuidance: item.skipGuidance || '',
            authoritativeSafeSkipLabel: backendMapped
                ? backendMapped.decisionLabel
                : 'No backend SAFE_SKIP decision',
            authoritativeSafeSkipBadgeClass: backendMapped
                ? backendMapped.badgeClass
                : 'slds-badge',
            authoritativeSafeSkipGuidance: backendMapped
                ? backendMapped.guidance
                : 'Authoritative SAFE_SKIP status comes from the backend SAFE_SKIP report only.'
        };
    });

    const providerLabel =
        report.provider === 'openai' || report.provider === 'gpt'
            ? 'GPT / OpenAI'
            : report.provider === 'gemini'
              ? 'Gemini'
              : report.provider || this.onDemandAiProvider;

    return {
        available,
        unavailable: !available,
        providerLabel,
        summary: report.summary || null,
        disclaimer: report.disclaimer || null,
        generated: report.generated === true,
        explanationRows,
        hasExplanations: explanationRows.length > 0
    };
}

_findBackendSafeSkipDecision(metadataType, metadataName) {
    const type = String(metadataType || '').toLowerCase();
    const name = String(metadataName || '').toLowerCase();
    if (!type && !name) {
        return null;
    }

    const enterpriseDecisions =
        this.deploymentEnterpriseReport?.safeSkips?.decisions;
    const reportDecisions = this.deploymentSafeSkipReport?.decisions;
    const decisions = Array.isArray(enterpriseDecisions) && enterpriseDecisions.length
        ? enterpriseDecisions
        : Array.isArray(reportDecisions)
          ? reportDecisions
          : [];

    return (
        decisions.find((item) => {
            return (
                String(item.metadataType || '').toLowerCase() === type &&
                String(item.metadataName || '').toLowerCase() === name
            );
        }) || null
    );
}

_clearSupportBundleState() {
    this.showSupportBundleModal = false;
    this.supportBundleGenerating = false;
    this.supportBundleReady = false;
    this.supportBundleError = null;
    this.supportBundle = null;
    this.supportBundleId = null;
    this.supportBundleFilename = null;
}

handleReportIssue() {
    if (!this.showReportIssueButton) {
        return;
    }
    this.supportBundleError = null;
    this.supportBundleReady = false;
    this.supportBundle = null;
    this.supportBundleId = null;
    this.supportBundleFilename = null;
    this.showSupportBundleModal = true;
}

/** Stage 5 — presentation-only section expand/collapse (no data/API side effects). */
toggleFailureAnalysis() {
    this.isFailureAnalysisExpanded = !this.isFailureAnalysisExpanded;
}

toggleResolutionNextActions() {
    this.isResolutionNextActionsExpanded = !this.isResolutionNextActionsExpanded;
}

toggleSafeSkipAnalysis() {
    this.isSafeSkipAnalysisExpanded = !this.isSafeSkipAnalysisExpanded;
}

toggleAiResolution() {
    this.isAiResolutionExpanded = !this.isAiResolutionExpanded;
}

/**
 * Stage 5 — per-card AI Resolution expand/collapse (presentation only).
 * Does not call AI, mutate backend report, or change SAFE_SKIP / planner.
 */
toggleAiResolutionCard(event) {
    const cardId = event?.currentTarget?.dataset?.id;
    const display = this.deploymentOnDemandAiDisplay;
    if (!cardId || !display || !Array.isArray(display.explanationRows)) {
        return;
    }

    this.deploymentOnDemandAiDisplay = {
        ...display,
        explanationRows: display.explanationRows.map((row) => {
            if (row.id !== cardId) {
                return row;
            }
            const isExpanded = row.isExpanded !== true;
            return {
                ...row,
                isExpanded,
                chevronIcon: isExpanded
                    ? 'utility:chevrondown'
                    : 'utility:chevronright',
                detailClass: isExpanded
                    ? 'stage5-ai-card-detail'
                    : 'stage5-ai-card-detail stage5-ai-card-detail_collapsed'
            };
        })
    };
}

closeSupportBundleModal() {
    if (this.supportBundleGenerating) {
        return;
    }
    this.showSupportBundleModal = false;
}

handleGenerateSupportBundle() {
    if (this.supportBundleGenerating) {
        return;
    }

    const validationId = this.backendValidationHistoryId;
    if (!validationId) {
        this.supportBundleError =
            'Your validation result is no longer available. Run validation again and retry.';
        this.supportBundleReady = false;
        return;
    }

    if (!this.deploymentValidationData) {
        this.supportBundleError =
            'Unable to generate the Support Bundle. Validation context is incomplete.';
        this.supportBundleReady = false;
        return;
    }

    const validationContext = this._buildSupportBundleValidationContext();
    if (!validationContext) {
        this.supportBundleError =
            'Unable to generate the Support Bundle. Validation context is incomplete.';
        this.supportBundleReady = false;
        return;
    }

    const requestPayload = {
        validationId,
        validationContext,
        issueSelection: {
            scope: 'ENTIRE_DEPLOYMENT',
            failures: []
        }
    };

    // Include on-demand AI report only if already generated (no AI call here).
    if (
        this.deploymentOnDemandAiResolution &&
        this.deploymentOnDemandAiResolution.generated === true
    ) {
        requestPayload.aiResolutionReport =
            this.deploymentOnDemandAiResolution;
    }

    // Dev/test-only size check — never logs request bodies or secrets.
    try {
        const measureFlag =
            typeof globalThis !== 'undefined' &&
            globalThis.__SUPPORT_BUNDLE_MEASURE_REQUEST_SIZE__ === true;
        if (measureFlag) {
            const size = measureSupportBundleRequestSize(requestPayload);
            // eslint-disable-next-line no-console
            console.info(
                '[SupportBundle] serialized request size (bytes):',
                size.byteLength
            );
        }
    } catch (measureError) {
        // Ignore measurement failures; generation must proceed.
    }

    this.supportBundleGenerating = true;
    this.supportBundleError = null;
    this.supportBundleReady = false;

    createSupportBundle({
        requestJson: JSON.stringify(requestPayload)
    })
        .then((result) => {
            let response;
            try {
                response = JSON.parse(result);
            } catch (parseError) {
                console.error(parseError);
                this.supportBundleError =
                    'Unable to generate the Support Bundle.';
                return;
            }

            if (response?.success !== true || !response?.supportBundle) {
                const msg = String(response?.error || '');
                if (
                    msg.toLowerCase().includes('not found') ||
                    response?.statusCode === 404
                ) {
                    this.supportBundleError =
                        'Your validation result is no longer available. Run validation again and retry.';
                } else {
                    this.supportBundleError =
                        'Support Bundle generation failed. No deployment was changed.';
                }
                return;
            }

            this.supportBundle = response.supportBundle;
            this.supportBundleId =
                response.supportBundle.bundleId || null;
            this.supportBundleFilename =
                response.delivery?.filename ||
                (this.supportBundleId
                    ? `${this.supportBundleId}.json`
                    : 'support-bundle.json');
            this.supportBundleReady = true;
        })
        .catch((error) => {
            console.error(error);
            this.supportBundleError =
                'Unable to generate the Support Bundle.';
        })
        .finally(() => {
            this.supportBundleGenerating = false;
        });
}

/**
 * Curated diagnostic validationContext for Support Bundle (Phase 18.3.2).
 * Preserves Phase 17 reports + slim diagnostics; excludes large arrays/XML/CLI.
 * Does not invent decisions; uses stored backend reports only. No AI call.
 */
_buildSupportBundleValidationContext() {
    return buildCuratedSupportBundleValidationContext(
        this.deploymentValidationData,
        {
            backendValidationHistoryId: this.backendValidationHistoryId,
            onDemandAiResolution: this.deploymentOnDemandAiResolution
        }
    );
}

handleDownloadSupportBundle() {
    if (!this.supportBundle || !this.supportBundleFilename) {
        return;
    }

    try {
        const json = JSON.stringify(this.supportBundle, null, 2);
        const blob = new Blob([json], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = this.supportBundleFilename;
        anchor.style.display = 'none';
        document.body.appendChild(anchor);
        anchor.click();
        document.body.removeChild(anchor);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (error) {
        console.error(error);
        this.supportBundleError =
            'Unable to download the Support Bundle.';
    }
}

closeDeployConfirmation() {

    if (this.isDeploying) {
        return;
    }

    this.showDeployConfirmation = false;

}

handleConfirmDeploy() {

    if (this.isDeploying) {
        return;
    }

    if (!this.deploymentReviewItems.length) {
        alert('Please run Deployment Review first');
        return;
    }

    if (!this.selectedComparisonDetails?.Destination_Org__r) {
        alert('Destination org details not available');
        return;
    }

    this.showDeployConfirmation = false;

    const destinationOrg =
        this.selectedComparisonDetails.Destination_Org__r;

    const deploymentPackage =
        this._buildDeploymentPackage('DEPLOY');

    this.isDeploying = true;

    validateDestinationDeployment({
        refreshToken: destinationOrg.Refresh_Token__c,
        instanceUrl: destinationOrg.Instance_URL__c,
        orgId: destinationOrg.Org_ID__c,
        deploymentPackage: JSON.stringify(deploymentPackage)
    })
    .then(result => {

        const response = JSON.parse(result);

        this.isDeploying = false;

        if (response && response.deploymentHistory) {
            this._persistDeploymentHistory(response.deploymentHistory);
        }

        const deploymentResult =
            response?.deploymentExecution ||
            response?.checkOnlyDeployment;

        const isSuccess =
            deploymentResult?.success === true ||
            response?.deploymentHistory?.status === 'SUCCESS';

        if (isSuccess) {
            this.deployCompleted = true;
            // Harden: dismiss Stage 5 info popup after successful deployment
            this.showIgnoredAutoIncludedModal = false;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Deployment completed successfully.',
                    variant: 'success',
                    mode: 'dismissable'
                })
            );
            return;
        }

        console.error(response);

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message:
                    deploymentResult?.message ||
                    response?.message ||
                    'Deployment failed.',
                variant: 'error',
                mode: 'dismissable'
            })
        );

    })
    .catch(error => {

        console.error(error);

        this.isDeploying = false;

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message:
                    error?.body?.message ||
                    error?.message ||
                    'Deployment failed.',
                variant: 'error',
                mode: 'dismissable'
            })
        );

    });

}

_extractMetadataName(file) {

    const fileName = file.File_Name__c || '';
    const filePath = file.File_Path__c || '';

    if (fileName.endsWith('.cls')) {
        return fileName.replace('.cls', '');
    }

    if (fileName.endsWith('.trigger')) {
        return fileName.replace('.trigger', '');
    }

    if (filePath.includes('/')) {
        const parts = filePath.split('/');
        const base = parts[parts.length - 1];
        return base.split('.')[0];
    }

    return fileName.split('.')[0] || fileName;

}

_buildDeploymentPackage(deploymentMode) {

    const deploymentPackage = {
        repoUrl: GITHUB_REPO_URL,
        sourceBranch: this.sourceBranch,
        destinationBranch: this.destinationBranch,
        selectedMetadata:
            this._buildDeploymentPackageSelectedMetadata(),
        requiredDependencies:
            this._buildDeploymentPackageRequiredDependencies(),
        selectedTestClasses:
            this._buildDeploymentPackageSelectedTestClasses(),
        // Phase 4.4A transport only — not used by package/deploy logic yet.
        deploymentSelections:
            this._buildDeploymentSelectionsTransport()
    };

    if (deploymentMode) {
        deploymentPackage.deploymentMode = deploymentMode;
    }

    return deploymentPackage;

}

/**
 * Convert local planner state into the backend transport model.
 * Does not alter selectedMetadata or requiredDependencies.
 */
_buildDeploymentSelectionsTransport() {
    const rows = this._buildDeploymentPlannerRowDefinitions(
        this.deploymentValidationData
    );

    if (!rows.length) {
        return [];
    }

    return rows
        .map((row) => {
            const metadataType = row.metadataType;
            const metadataName = row.metadataName;
            const choice =
                this.deploymentPlannerSelections[row.key] || 'Deploy';

            if (
                !metadataType ||
                metadataType === '—' ||
                !metadataName
            ) {
                return null;
            }

            return {
                metadataType,
                metadataName,
                choice
            };
        })
        .filter((item) => item !== null);

}

_buildDeploymentPackageSelectedMetadata() {

    return this.savedComparisonResults
        .filter(
            file => file.Selected_For_Deployment__c === true
        )
        .map(file => ({
            metadataType: file.Metadata_Type__c,
            metadataName: this._extractMetadataName(file),
            filePath: file.File_Path__c,
            name: file.File_Name__c,
            type: file.Metadata_Type__c,
            path: file.File_Path__c
        }));

}

_buildDeploymentPackageRequiredDependencies() {

    return this.deploymentReviewItems.flatMap(item =>
        item.requiredDependencies.map(dep => ({
            name: dep.name,
            type: dep.type,
            required: true,
            selected: true,
            editable: false
        }))
    );

}

_buildDeploymentPackageSelectedTestClasses() {

    return Object.values(this.selectedTestClasses).flat();

}

/**
 * Phase 10F — Build AI Advisor request from existing deployment review /
 * planner state. Does not reconstruct planner decisions; only forwards
 * objects already present in the UI (or selection transport).
 */
_buildAiAdvisorRequestPayload() {
    const validation = this.deploymentValidationData || {};
    const generatedPackage =
        validation.generatedDeploymentPackage || null;
    const packageSummary = generatedPackage?.summary || null;

    const existingDecisions = Array.isArray(validation.plannerDecisions)
        ? validation.plannerDecisions
        : null;

    const plannerDecisions = existingDecisions ||
        this._buildDeploymentSelectionsTransport().map((selection) => ({
            metadataType: selection.metadataType,
            metadataName: selection.metadataName,
            choice:
                String(selection.choice || 'Deploy').toUpperCase() === 'SKIP'
                    ? 'SKIP'
                    : 'DEPLOY'
        }));

    const plannerCompatibility =
        validation.plannerCompatibilityReport ||
        validation.plannerCompatibility ||
        null;

    const readiness = validation.deploymentReadiness || {};
    const deploymentSummary = {
        overallStatus: readiness.overallStatus || null,
        canDeploy: readiness.canDeploy === true,
        blockingIssueCount: Array.isArray(readiness.blockingIssues)
            ? readiness.blockingIssues.length
            : 0,
        warningCount: Array.isArray(readiness.warnings)
            ? readiness.warnings.length
            : 0
    };

    return {
        plannerDecisions,
        plannerCompatibility,
        generatedDeploymentPackage: generatedPackage,
        packageSummary,
        deploymentSummary,
        request: {
            validationId:
                this.historyRecordId ||
                this.currentDeploymentPlanId ||
                null,
            mode: 'validate'
        },
        options: {
            generatedAt: new Date().toISOString()
        }
    };
}

_requestAiAdvisor() {
    this.isLoadingAiAdvisor = true;
    this.aiAdvisorUnavailableMessage = null;
    this.aiAdvisorData = null;
    this.aiAdvisorDisplay = null;

    const payload = this._buildAiAdvisorRequestPayload();

    getAiAdvisor({
        requestJson: JSON.stringify(payload)
    })
        .then((result) => {
            let response;

            try {
                response = JSON.parse(result);
            } catch (parseError) {
                console.error(parseError);
                this._setAiAdvisorUnavailable();
                return;
            }

            this.aiAdvisorData = response;
            this._applyAiAdvisorResponse(response);
        })
        .catch((error) => {
            console.error(error);
            this._setAiAdvisorUnavailable();
        });
}

_clearAiAdvisor() {
    this.isLoadingAiAdvisor = false;
    this.aiAdvisorData = null;
    this.aiAdvisorDisplay = null;
    this.aiAdvisorUnavailableMessage = null;
}

_setAiAdvisorUnavailable() {
    this.isLoadingAiAdvisor = false;
    this.aiAdvisorData = null;
    this.aiAdvisorDisplay = null;
    this.aiAdvisorUnavailableMessage = 'AI Advisor unavailable.';
}

_applyAiAdvisorResponse(response) {
    this.isLoadingAiAdvisor = false;

    if (!response || typeof response !== 'object') {
        this._setAiAdvisorUnavailable();
        return;
    }

    const status = String(response.advisorStatus || '').toUpperCase();
    const unavailableStatuses = new Set([
        'UNAVAILABLE',
        'AUTH_FAILURE',
        'RATE_LIMITED',
        'TIMEOUT',
        'INVALID_RESPONSE'
    ]);

    if (!status || unavailableStatuses.has(status)) {
        this.aiAdvisorUnavailableMessage = 'AI Advisor unavailable.';
        this.aiAdvisorDisplay = this._buildAiAdvisorDisplay(response, status);
        return;
    }

    this.aiAdvisorUnavailableMessage = null;
    this.aiAdvisorDisplay = this._buildAiAdvisorDisplay(response, status);
}

_buildAiAdvisorDisplay(response, status) {
    const semantic = response?.semanticResponse || null;
    const showSemanticContent =
        (status === 'OK' || status === 'PARTIAL') &&
        semantic != null;

    const groundingScore =
        typeof response?.groundingScore === 'number'
            ? response.groundingScore
            : null;

    const validationWarnings = (
        Array.isArray(response?.validationWarnings)
            ? response.validationWarnings
            : []
    ).map((warning, index) => ({
        id: `ai-warn-${index}`,
        text: String(warning)
    }));

    const riskItems = (
        Array.isArray(semantic?.riskSummary) ? semantic.riskSummary : []
    ).map((item, index) => ({
        id: `ai-risk-${index}`,
        text: String(item)
    }));

    const recommendations = (
        Array.isArray(semantic?.recommendations)
            ? semantic.recommendations
            : []
    ).map((item, index) => ({
        id: `ai-rec-${index}`,
        text: String(item)
    }));

    let diagnosticsJson = '';

    try {
        diagnosticsJson = response?.diagnostics
            ? JSON.stringify(response.diagnostics, null, 2)
            : '';
    } catch (_error) {
        diagnosticsJson = '';
    }

    return {
        advisorStatus: status || '—',
        groundingScore:
            groundingScore == null ? '—' : String(groundingScore),
        statusBadgeClass: this._getAiAdvisorStatusBadgeClass(status),
        groundingBadgeClass: this._getAiAdvisorGroundingBadgeClass(
            groundingScore
        ),
        showSemanticContent,
        executiveSummary: semantic?.executiveSummary || '',
        developerSummary: semantic?.developerSummary || '',
        riskItems,
        recommendations,
        validationWarnings,
        statusMessage: this._getAiAdvisorStatusMessage(status),
        diagnosticsJson
    };
}

_getAiAdvisorStatusBadgeClass(status) {
    switch (status) {
        case 'OK':
            return 'slds-badge slds-theme_success';
        case 'PARTIAL':
            return 'slds-badge slds-theme_warning';
        case 'DISABLED':
            return 'slds-badge ai-advisor-badge_neutral';
        case 'AUTH_FAILURE':
        case 'RATE_LIMITED':
        case 'TIMEOUT':
        case 'UNAVAILABLE':
        case 'INVALID_RESPONSE':
            return 'slds-badge slds-theme_error';
        default:
            return 'slds-badge ai-advisor-badge_neutral';
    }
}

_getAiAdvisorGroundingBadgeClass(score) {
    if (typeof score !== 'number') {
        return 'slds-badge ai-advisor-badge_neutral';
    }

    if (score >= 80) {
        return 'slds-badge slds-theme_success';
    }

    if (score >= 50) {
        return 'slds-badge slds-theme_warning';
    }

    return 'slds-badge slds-theme_error';
}

_getAiAdvisorStatusMessage(status) {
    switch (status) {
        case 'DISABLED':
            return 'AI Advisor is disabled for this environment.';
        case 'PARTIAL':
            return 'AI advisory is partial — some sections were filtered during grounding.';
        case 'OK':
            return 'AI advisory grounded successfully. This is advisory only and does not override the planner.';
        case 'AUTH_FAILURE':
            return 'AI Advisor authentication failed.';
        case 'RATE_LIMITED':
            return 'AI Advisor rate limit reached.';
        case 'TIMEOUT':
            return 'AI Advisor request timed out.';
        case 'INVALID_RESPONSE':
            return 'AI Advisor returned an invalid response.';
        case 'UNAVAILABLE':
            return 'AI Advisor unavailable.';
        default:
            return 'AI Advisor status unknown.';
    }
}

_buildSourceValidationDisplayItems(data) {

    const sourceValidation = data?.sourceValidation || {};
    const coverageValidation = data?.coverageValidation || {};
    const testResults = sourceValidation.results || [];
    const coverageResults = coverageValidation.results || [];

    return this.deploymentReviewItems.map(item => {

        const testClassesForItem =
            this.selectedTestClasses[item.key] || [];

        const testExecutionRows = testClassesForItem.map(testClass => {

            const result = testResults.find(
                row => row.testClass === testClass
            ) || {};

            const status = result.status || '—';

            return {
                id: `${item.key}-${testClass}`,
                testClass,
                status,
                statusBadgeClass:
                    this._getPassFailBadgeClass(status),
                methodsRun: result.methodsRun ?? '—',
                methodsPassed: result.methodsPassed ?? '—',
                methodsFailed: result.methodsFailed ?? '—',
                failedMethods:
                    (result.failedMethods || []).join(', ') || '—'
            };

        });

        const apexClassName =
            item.metadataName?.endsWith('.cls')
                ? item.metadataName.replace('.cls', '')
                : item.metadataName;

        const coverageResult = coverageResults.find(
            row => row.apexClass === apexClassName
        );

        let coverage = null;

        if (coverageResult) {

            const coverageStatus =
                coverageResult.passed ? 'PASS' : 'FAIL';

            coverage = {
                apexClass: coverageResult.apexClass,
                coverage: coverageResult.coverage,
                minimumRequired: coverageResult.minimumRequired,
                difference: coverageResult.difference,
                status: coverageStatus,
                statusBadgeClass:
                    this._getPassFailBadgeClass(coverageStatus)
            };

        }

        const testsPass =
            testExecutionRows.length === 0 ||
            testExecutionRows.every(
                row => row.status === 'PASS'
            );

        const coveragePass =
            !coverage || coverage.status === 'PASS';

        const overallStatus =
            testsPass && coveragePass ? 'PASS' : 'FAIL';

        return {
            key: item.key,
            accordionLabel:
                `${this._getDisplayMetadataName(
                    item.metadataName,
                    item.metadataType
                )} — ${overallStatus}`,
            metadataName: item.metadataName,
            displayMetadataName: this._getDisplayMetadataName(
                item.metadataName,
                item.metadataType
            ),
            overallStatus,
            overallStatusBadgeClass:
                this._getPassFailBadgeClass(overallStatus),
            testExecutionRows,
            hasTestExecution: testExecutionRows.length > 0,
            coverage,
            hasCoverage: !!coverage,
            coverageTableData: coverage ? [coverage] : []
        };

    });

}

_buildDeploymentValidationDisplay(data) {

    const deploymentValidation =
        data?.deploymentValidation || {};

    const metadataValidation =
        data?.metadataValidation || {};

    const dependencyValidation =
        data?.dependencyValidation || {};

    const deploymentReadiness =
        data?.deploymentReadiness || {};

    const connectivityStatus =
        deploymentValidation.status ||
        (deploymentValidation.destinationConnected ? 'PASS' : 'BLOCKED');

    const metadataRows = (metadataValidation.results || []).map(
        (row, index) => {

            const isPass = row.status === 'PASS';
            const isMissing = !row.existsInSource;
            const isInvalid =
                row.existsInSource && !isPass;

            return {
                id: `metadata-${index}`,
                metadataName:
                    row.metadataName || row.metadataType || '—',
                displayMetadataName: this._getDisplayMetadataName(
                    row.metadataName || row.metadataType || '—',
                    row.metadataType
                ),
                readyLabel: isPass ? 'Yes' : 'No',
                missingLabel: isMissing ? 'Yes' : 'No',
                invalidLabel: isInvalid ? 'Yes' : 'No'
            };

        }
    );

    const dependencyRows = (dependencyValidation.results || []).map(
        (row, index) => {
            const existsDisplay =
                this._resolveDependencyExistsDisplay(row);

            return {
                id: `dependency-${index}`,
                name: row.name,
                existsLabel: existsDisplay.existsLabel,
                existsBadgeClass: existsDisplay.existsBadgeClass,
                includedLabel:
                    row.includedInDeploymentPackage ? 'Yes' : 'No',
                status: row.status || '—'
            };
        }
    );

    const readinessStatus =
        deploymentReadiness.overallStatus || 'BLOCKED';

    return {
        destinationConnectivity: {
            status: connectivityStatus,
            statusBadgeClass:
                this._getConnectivityBadgeClass(connectivityStatus),
            message:
                deploymentValidation.message ||
                'Destination connectivity check'
        },
        metadataValidation: {
            overallStatus:
                metadataValidation.overallStatus || '—',
            statusBadgeClass: this._getPassFailBadgeClass(
                metadataValidation.overallStatus
            ),
            rows: metadataRows,
            hasRows: metadataRows.length > 0
        },
        dependencyValidation: {
            overallStatus:
                dependencyValidation.overallStatus || '—',
            statusBadgeClass: this._getPassFailBadgeClass(
                dependencyValidation.overallStatus === 'PASS'
                    ? 'PASS'
                    : 'FAIL'
            ),
            rows: dependencyRows,
            hasRows: dependencyRows.length > 0
        },
        deploymentReadiness: {
            overallStatus: readinessStatus,
            statusBadgeClass:
                this._getReadinessBadgeClass(readinessStatus),
            canDeploy: deploymentReadiness.canDeploy === true,
            readyForDeployment:
                deploymentReadiness.readyForDeployment === true,
            blockingIssuesList:
                deploymentReadiness.blockingIssues || [],
            warnings: deploymentReadiness.warnings || [],
            hasBlockingIssues:
                (deploymentReadiness.blockingIssues || []).length > 0,
            hasWarnings:
                (deploymentReadiness.warnings || []).length > 0
        }
    };

}

/**
 * Phase 17.6.1 — store raw backend intelligence reports (presentation only).
 */
_applyDeploymentIntelligenceReports(data) {
    if (!data || typeof data !== 'object') {
        this._clearDeploymentIntelligenceReports();
        return;
    }

    // Fresh validation clears prior on-demand AI results (stub is not live AI).
    this.deploymentOnDemandAiResolution = null;
    this.deploymentOnDemandAiDisplay = null;
    this.onDemandAiErrorMessage = null;
    this.isResolvingWithAi = false;

    this.deploymentEnterpriseReport =
        data.enterpriseDeploymentReport || null;
    this.deploymentFailureClassification =
        data.failureClassification || null;
    this.deploymentResolutionReport =
        data.resolutionReport || null;
    this.deploymentAutoFixReport =
        data.autoFixReport || null;
    this.deploymentAutoValidationReport =
        data.autoValidationReport || null;
    this.deploymentAiResolutionReport =
        data.aiResolutionReport || null;
    this.deploymentSafeSkipReport =
        data.safeSkipReport ||
        data.enterpriseDeploymentReport?.safeSkips ||
        null;

    this.deploymentIntelligenceDisplay =
        this._buildDeploymentIntelligenceDisplay(data);
}

_clearDeploymentIntelligenceReports() {
    this.deploymentEnterpriseReport = null;
    this.deploymentFailureClassification = null;
    this.deploymentResolutionReport = null;
    this.deploymentAutoFixReport = null;
    this.deploymentAutoValidationReport = null;
    this.deploymentAiResolutionReport = null;
    this.deploymentSafeSkipReport = null;
    this.deploymentOnDemandAiResolution = null;
    this.deploymentOnDemandAiDisplay = null;
    this.onDemandAiErrorMessage = null;
    this.isResolvingWithAi = false;
    this.deploymentIntelligenceDisplay = null;
}

/**
 * Phase 17.6.1 — presentation rows from backend reports. No decision logic.
 */
_buildDeploymentIntelligenceDisplay(data) {
    if (!data || typeof data !== 'object') {
        return null;
    }

    const enterprise = data.enterpriseDeploymentReport || null;
    const failureClassification = data.failureClassification || null;
    const autoFixReport = data.autoFixReport || null;
    const autoValidationReport = data.autoValidationReport || null;
    const aiResolutionReport = data.aiResolutionReport || null;

    const hasEnterprise = !!enterprise;
    const summary = enterprise?.summary || {};
    const statistics = enterprise?.statistics || {};

    const summaryMetrics = this._buildPresentMetrics([
        { key: 'validationAttempts', label: 'Validation Attempts', value: summary.validationAttempts },
        { key: 'totalMetadata', label: 'Total Metadata', value: summary.totalMetadata },
        { key: 'successfulMetadata', label: 'Successful Metadata', value: summary.successfulMetadata },
        { key: 'failedMetadata', label: 'Failed Metadata', value: summary.failedMetadata },
        { key: 'autoFixesApplied', label: 'Auto Fixes Applied', value: summary.autoFixesApplied },
        { key: 'dependencyFailures', label: 'Dependency Failures', value: statistics.dependencyFailures },
        { key: 'compatibilityFailures', label: 'Compatibility Failures', value: statistics.compatibilityFailures },
        { key: 'manualActions', label: 'Manual Actions', value: statistics.manualActions },
        { key: 'autoResolved', label: 'Auto Resolved', value: statistics.autoResolved },
        { key: 'warnings', label: 'Warnings', value: statistics.warnings }
    ]);

    const safeSkipPresentation = this._buildSafeSkipPresentation(data);
    // Surface SAFE_SKIP summary counts in the shared Enterprise KPI strip when backend provides them.
    const combinedSummaryMetrics = summaryMetrics.concat(
        safeSkipPresentation.summaryMetrics
    );

    const overallStatus = enterprise?.overallStatus || null;
    const overallStatusBadgeClass = overallStatus
        ? this._getIntelligenceStatusBadgeClass(overallStatus)
        : 'slds-badge';

    const failureSource = Array.isArray(enterprise?.failures) && enterprise.failures.length
        ? enterprise.failures
        : Array.isArray(failureClassification?.failures)
          ? failureClassification.failures
          : [];

    const failureRows = failureSource.map((item, index) => ({
        id: `intel-failure-${index}`,
        metadataType: item.metadataType || '—',
        metadataName: item.metadataName || '—',
        category: item.category || item.severity || '—',
        reason: item.reason || item.message || '—'
    }));

    const nextActionSource = Array.isArray(enterprise?.nextActions)
        ? enterprise.nextActions
        : [];

    const nextActionRows = nextActionSource.map((item, index) => {
        const completed = item.completed === true;
        const type = String(item.type || '').toUpperCase();
        let statusLabel = completed
            ? 'Completed automatically'
            : 'User action required';
        let statusBadgeClass = completed
            ? 'slds-badge slds-theme_success'
            : 'slds-badge slds-theme_warning';

        // Presentation labels for backend nextActions SAFE_SKIP types only.
        if (type === 'SAFE_SKIP_APPLIED') {
            statusLabel = 'Completed automatically';
            statusBadgeClass = 'slds-badge slds-theme_success';
        } else if (type === 'SAFE_SKIP_AVAILABLE') {
            statusLabel = 'Safe to skip — available';
            statusBadgeClass = 'slds-badge slds-theme_info';
        }

        return {
            id: `intel-action-${index}`,
            priority: item.priority != null ? String(item.priority) : '—',
            type: item.type || '—',
            metadataType: item.metadataType || '—',
            metadataName: item.metadataName || '—',
            message: item.message || '—',
            completed,
            statusLabel,
            statusBadgeClass
        };
    });

    const autoFixSource = Array.isArray(enterprise?.autoFixes) && enterprise.autoFixes.length
        ? enterprise.autoFixes
        : Array.isArray(autoFixReport?.fixes)
          ? autoFixReport.fixes
          : [];

    const autoFixRows = autoFixSource.map((item, index) => {
        const successful = item.successful === true;
        const executed = item.executed === true;
        let outcomeLabel = 'Could not be automatically resolved';
        let outcomeClass = 'slds-badge slds-theme_warning';
        if (successful) {
            outcomeLabel = 'Automatically resolved';
            outcomeClass = 'slds-badge slds-theme_success';
        } else if (executed) {
            outcomeLabel = 'Executed — not successful';
            outcomeClass = 'slds-badge slds-theme_error';
        }

        return {
            id: `intel-autofix-${index}`,
            metadataType: item.metadataType || '—',
            metadataName: item.metadataName || '—',
            fixType: item.fixType || '—',
            action: item.action || item.reason || '—',
            outcomeLabel,
            outcomeClass
        };
    });

    const autoFixAvailable =
        autoFixReport &&
        Object.prototype.hasOwnProperty.call(autoFixReport, 'autoFixAvailable')
            ? autoFixReport.autoFixAvailable === true
            : null;
    const autoFixApplied =
        autoFixReport &&
        Object.prototype.hasOwnProperty.call(autoFixReport, 'autoFixApplied')
            ? autoFixReport.autoFixApplied === true
            : null;

    const remainingFailures = Array.isArray(autoValidationReport?.remainingFailures)
        ? autoValidationReport.remainingFailures
        : [];

    const remainingFailureRows = remainingFailures.map((item, index) => ({
        id: `intel-reval-fail-${index}`,
        metadataType: item.metadataType || item.type || '—',
        metadataName: item.metadataName || item.name || '—',
        reason: item.reason || item.message || '—'
    }));

    const autoValidationMetrics = this._buildPresentMetrics([
        { key: 'attempts', label: 'Attempts', value: autoValidationReport?.attempts },
        { key: 'initialStatus', label: 'Initial Status', value: autoValidationReport?.initialStatus },
        { key: 'finalStatus', label: 'Final Status', value: autoValidationReport?.finalStatus }
    ]);

    const autoValidationFlags = [];
    if (autoValidationReport?.autoValidationExecuted === true) {
        autoValidationFlags.push({
            id: 'av-executed',
            text: 'Automatically revalidated after applying fixes.'
        });
    }
    if (autoValidationReport?.autoFixesApplied === true) {
        autoValidationFlags.push({
            id: 'av-fixes',
            text: 'Auto fixes were applied before revalidation.'
        });
    }
    if (autoValidationReport?.revalidated === true) {
        autoValidationFlags.push({
            id: 'av-revalidated',
            text: 'Revalidation completed.'
        });
    }

    const aiAvailable = aiResolutionReport?.available === true;
    const aiUnavailable =
        !aiResolutionReport ||
        aiResolutionReport.available === false;
    const aiExplanations = Array.isArray(aiResolutionReport?.explanations)
        ? aiResolutionReport.explanations
        : [];

    const aiExplanationRows = aiExplanations.map((item, index) => ({
        id: `intel-ai-${index}`,
        metadataType: item.metadataType || '—',
        metadataName: item.metadataName || '—',
        severity: item.severity || '—',
        title: item.title || 'Guidance',
        why: item.why || '',
        impact: item.impact || '',
        recommendedAction: item.recommendedAction || '',
        bestPractice: item.bestPractice || '',
        confidence: item.confidence != null ? String(item.confidence) : ''
    }));

    const hasAutoValidationSection = !!autoValidationReport;
    const hasAutoFixSection =
        !!autoFixReport || autoFixRows.length > 0;

    // Show AI Resolution controls when enterprise/stub exists or failures are present.
    const showAiSection =
        aiResolutionReport != null ||
        hasEnterprise ||
        failureRows.length > 0;

    return {
        hasAnySection:
            hasEnterprise ||
            failureRows.length > 0 ||
            nextActionRows.length > 0 ||
            hasAutoFixSection ||
            hasAutoValidationSection ||
            aiResolutionReport != null ||
            safeSkipPresentation.hasSafeSkipSection,
        hasEnterprise,
        overallStatus,
        overallStatusBadgeClass,
        generatedAt: enterprise?.generatedAt || null,
        version: enterprise?.version != null ? String(enterprise.version) : null,
        executionMode: summary.executionMode || null,
        summaryMetrics: combinedSummaryMetrics,
        hasSummaryMetrics: combinedSummaryMetrics.length > 0,
        failureRows,
        hasFailures: failureRows.length > 0,
        nextActionRows,
        hasNextActions: nextActionRows.length > 0,
        autoFixAvailable,
        autoFixApplied,
        autoFixAvailableLabel:
            autoFixAvailable === true
                ? 'Yes'
                : autoFixAvailable === false
                  ? 'No'
                  : null,
        autoFixAppliedLabel:
            autoFixApplied === true
                ? 'Yes'
                : autoFixApplied === false
                  ? 'No'
                  : null,
        autoFixRows,
        hasAutoFixRows: autoFixRows.length > 0,
        hasAutoFixSection,
        hasAutoValidationSection,
        autoValidationMetrics,
        hasAutoValidationMetrics: autoValidationMetrics.length > 0,
        autoValidationFlags,
        hasAutoValidationFlags: autoValidationFlags.length > 0,
        remainingFailureRows,
        hasRemainingFailures: remainingFailureRows.length > 0,
        showAiSection,
        aiAvailable,
        aiUnavailable,
        aiSummary: aiResolutionReport?.summary || null,
        aiDisclaimer: aiResolutionReport?.disclaimer || null,
        aiProvider: aiResolutionReport?.provider || null,
        aiExplanationRows,
        hasAiExplanations: aiExplanationRows.length > 0,
        hasSafeSkipSection: safeSkipPresentation.hasSafeSkipSection,
        safeSkipRows: safeSkipPresentation.rows,
        hasSafeSkipRows: safeSkipPresentation.rows.length > 0,
        safeSkipSummaryMetrics: safeSkipPresentation.summaryMetrics,
        hasSafeSkipSummaryMetrics:
            safeSkipPresentation.summaryMetrics.length > 0
    };
}

_buildPresentMetrics(definitions) {
    const rows = [];
    definitions.forEach((def) => {
        if (def.value === null || def.value === undefined || def.value === '') {
            return;
        }
        rows.push({
            id: `metric-${def.key}`,
            label: def.label,
            value: String(def.value)
        });
    });
    return rows;
}

/**
 * Phase 18.1 — presentation-only SAFE_SKIP rows/KPIs from backend reports.
 * Does not invent safeToSkip / decision values.
 */
_buildSafeSkipPresentation(data) {
    const enterpriseSafeSkips =
        data?.enterpriseDeploymentReport?.safeSkips || null;
    const safeSkipReport = data?.safeSkipReport || null;

    // Prefer detailed decisions: enterprise.safeSkips.decisions, else top-level report.
    const enterpriseDecisions = Array.isArray(enterpriseSafeSkips?.decisions)
        ? enterpriseSafeSkips.decisions
        : [];
    const reportDecisions = Array.isArray(safeSkipReport?.decisions)
        ? safeSkipReport.decisions
        : [];
    const decisions =
        enterpriseDecisions.length > 0
            ? enterpriseDecisions
            : reportDecisions;

    const summarySource =
        enterpriseSafeSkips ||
        (safeSkipReport?.summary
            ? {
                  available: safeSkipReport.summary.available,
                  applied: safeSkipReport.summary.applied,
                  blocked: safeSkipReport.summary.blocked,
                  unknown: safeSkipReport.summary.unknown
              }
            : null);

    const summaryMetrics = [];
    if (summarySource && typeof summarySource === 'object') {
        const metricDefs = [
            { key: 'safeSkipAvailable', label: 'SAFE_SKIP Available', prop: 'available' },
            { key: 'safeSkipApplied', label: 'SAFE_SKIP Applied', prop: 'applied' },
            { key: 'safeSkipBlocked', label: 'SAFE_SKIP Blocked', prop: 'blocked' },
            { key: 'safeSkipUnknown', label: 'SAFE_SKIP Unknown', prop: 'unknown' }
        ];
        metricDefs.forEach((def) => {
            if (
                !Object.prototype.hasOwnProperty.call(summarySource, def.prop)
            ) {
                return;
            }
            const value = summarySource[def.prop];
            if (value === null || value === undefined || value === '') {
                return;
            }
            summaryMetrics.push({
                id: `metric-${def.key}`,
                label: def.label,
                value: String(value)
            });
        });
    }

    const rows = decisions.map((item, index) => {
        const mapped = this._mapSafeSkipDecisionDisplay(item);
        return {
            id: `intel-safeskip-${index}`,
            metadataType: item.metadataType || '—',
            metadataName: item.metadataName || '—',
            decision: mapped.decisionLabel,
            decisionBadgeClass: mapped.badgeClass,
            safeToSkipLabel: mapped.safeToSkipLabel,
            appliedLabel: item.applied === true ? 'Yes' : 'No',
            reason: item.reason || '—',
            impact: item.impact || '—',
            guidance: mapped.guidance,
            uiState: mapped.uiState
        };
    });

    const hasSafeSkipSection =
        rows.length > 0 ||
        summaryMetrics.length > 0 ||
        !!safeSkipReport ||
        !!enterpriseSafeSkips;

    return {
        hasSafeSkipSection,
        rows,
        summaryMetrics
    };
}

/**
 * Map backend SAFE_SKIP fields to display labels only.
 * Authority remains on safeToSkip / decision / applied from backend.
 */
_mapSafeSkipDecisionDisplay(item = {}) {
    const applied = item.applied === true;
    const safeToSkip = item.safeToSkip;
    const rawDecision = String(item.decision || '').toUpperCase();

    if (applied || rawDecision === 'SAFE_SKIP_APPLIED') {
        return {
            uiState: 'SAFE_SKIP_APPLIED',
            decisionLabel: 'Skipped automatically',
            safeToSkipLabel: 'Yes',
            badgeClass: 'slds-badge slds-theme_success safe-skip-badge_applied',
            guidance:
                'Component was excluded by the backend and the deployment was revalidated.'
        };
    }

    if (
        safeToSkip === true ||
        rawDecision === 'SAFE_SKIP' ||
        rawDecision === 'SAFE_SKIP_AVAILABLE'
    ) {
        return {
            uiState: 'SAFE_SKIP_AVAILABLE',
            decisionLabel: 'Safe to skip',
            safeToSkipLabel: 'Yes',
            badgeClass: 'slds-badge slds-theme_info safe-skip-badge_available',
            guidance:
                'Backend can safely exclude this component from the deployment package.'
        };
    }

    if (
        safeToSkip === false ||
        rawDecision === 'NOT_SAFE_TO_SKIP'
    ) {
        return {
            uiState: 'NOT_SAFE_TO_SKIP',
            decisionLabel: 'Cannot skip',
            safeToSkipLabel: 'No',
            badgeClass: 'slds-badge slds-theme_error safe-skip-badge_blocked',
            guidance:
                item.reason ||
                'Backend determined that skipping this component is not safe.'
        };
    }

    return {
        uiState: 'UNKNOWN',
        decisionLabel: 'Manual resolution required',
        safeToSkipLabel: 'Unknown',
        badgeClass: 'slds-badge slds-theme_warning safe-skip-badge_unknown',
        guidance:
            'Backend cannot safely determine whether this component can be excluded.'
    };
}

_getIntelligenceStatusBadgeClass(status) {
    const normalized = String(status || '').toUpperCase();
    if (normalized === 'SUCCESS' || normalized === 'SUCCEEDED' || normalized === 'READY') {
        return 'slds-badge slds-theme_success';
    }
    if (normalized === 'FAILED' || normalized === 'BLOCKED' || normalized === 'ERROR') {
        return 'slds-badge slds-theme_error';
    }
    if (normalized === 'WARNING' || normalized === 'PARTIAL') {
        return 'slds-badge slds-theme_warning';
    }
    return 'slds-badge slds-theme_info';
}

/**
 * Phase 11.5 — presentation-only readiness report from existing validation fields.
 * Does not rename backend properties or alter deploy/gate logic.
 */
_buildDeploymentReadinessReport(data) {
    if (!data || typeof data !== 'object') {
        return null;
    }

    const deploymentReadiness = data.deploymentReadiness || {};
    const summary =
        deploymentReadiness.compatibilitySummary ||
        deploymentReadiness.summary ||
        {};

    const excludedComponents = Array.isArray(data.excludedComponents)
        ? data.excludedComponents
        : Array.isArray(deploymentReadiness.excludedComponents)
          ? deploymentReadiness.excludedComponents
          : [];

    const blockingComponents = Array.isArray(data.blockingComponents)
        ? data.blockingComponents
        : Array.isArray(deploymentReadiness.blockingComponents)
          ? deploymentReadiness.blockingComponents
          : [];

    const compatibilityWarnings = Array.isArray(data.compatibilityWarnings)
        ? data.compatibilityWarnings
        : Array.isArray(
                data.deploymentCompatibilityPlan?.compatibilityWarnings
            )
          ? data.deploymentCompatibilityPlan.compatibilityWarnings
          : [];

    const readyForDeployment = this._resolveReadyForDeployment(
        deploymentReadiness
    );

    const deployableCount =
        summary.deployable ??
        summary.totalDeployable ??
        (Array.isArray(deploymentReadiness.deployableComponents)
            ? deploymentReadiness.deployableComponents.length
            : 0);

    const excludedCount =
        summary.excluded ??
        summary.totalExcluded ??
        excludedComponents.length;

    const blockingCount =
        summary.blocking ??
        summary.totalBlocking ??
        data.blockingSummary?.totalBlocking ??
        blockingComponents.length;

    const warningCount =
        summary.warnings ??
        summary.totalWarnings ??
        compatibilityWarnings.length;

    let statusKey = 'READY';
    if (!readyForDeployment) {
        statusKey = 'BLOCKED';
    } else if (excludedCount > 0) {
        statusKey = 'WARNING';
    }

    const statusPresentation = {
        READY: {
            statusKey: 'READY',
            title: 'Ready for Deployment',
            message: 'All required metadata is deployable.',
            detail: 'Deployment can continue.',
            iconName: 'utility:success',
            iconVariant: 'success',
            cardClass: 'readiness-status-card readiness-status-card_ready',
            badgeClass: 'slds-badge slds-theme_success',
            badgeLabel: 'READY'
        },
        WARNING: {
            statusKey: 'WARNING',
            title: 'Deployment Ready with Exclusions',
            message:
                'Some metadata was automatically excluded because it is incompatible with the destination org.',
            detail: 'Deployment may continue.',
            iconName: 'utility:warning',
            iconVariant: 'warning',
            cardClass: 'readiness-status-card readiness-status-card_warning',
            badgeClass: 'slds-badge slds-theme_warning',
            badgeLabel: 'WARNING'
        },
        BLOCKED: {
            statusKey: 'BLOCKED',
            title: 'Deployment Blocked',
            message:
                'One or more deployable components still depend on excluded components.',
            detail: 'Deployment has been intentionally prevented.',
            iconName: 'utility:error',
            iconVariant: 'error',
            cardClass: 'readiness-status-card readiness-status-card_blocked',
            badgeClass: 'slds-badge slds-theme_error',
            badgeLabel: 'BLOCKED'
        }
    }[statusKey];

    const excludedRows = excludedComponents.map((item, index) => ({
        id: `excluded-${index}`,
        component: item.metadataName || item.name || '—',
        metadataType: item.metadataType || item.type || '—',
        reason: item.reason || item.message || '—',
        category: item.category || '—'
    }));

    const blockingRows = blockingComponents.map((item, index) => {
        const blockedByList = Array.isArray(item.blockedBy)
            ? item.blockedBy
            : [];
        const blockedByLabel = blockedByList
            .map((dep) => dep.metadataName || dep.name || '')
            .filter(Boolean)
            .join(', ');
        const primaryBlockedBy = blockedByList[0] || {};

        return {
            id: `blocking-${index}`,
            component: item.metadataName || item.name || '—',
            blockedBy: blockedByLabel || '—',
            reason:
                primaryBlockedBy.reason ||
                primaryBlockedBy.message ||
                item.reason ||
                'Missing dependency'
        };
    });

    const warningRows = compatibilityWarnings.map((item, index) => ({
        id: `warning-${index}`,
        text:
            item.message ||
            item.reason ||
            [
                item.metadataType,
                item.metadataName,
                item.category
            ]
                .filter(Boolean)
                .join(' — ') ||
            'Compatibility warning'
    }));

    return {
        readyForDeployment,
        statusKey,
        ...statusPresentation,
        isReady: statusKey === 'READY',
        isWarning: statusKey === 'WARNING',
        isBlocked: statusKey === 'BLOCKED',
        kpis: {
            deployable: deployableCount,
            excluded: excludedCount,
            blocking: blockingCount,
            warnings: warningCount
        },
        excludedRows,
        hasExcludedRows: excludedRows.length > 0,
        blockingRows,
        hasBlockingRows: blockingRows.length > 0,
        warningRows,
        hasWarningRows: warningRows.length > 0,
        decisionTitle: readyForDeployment
            ? 'Ready to Deploy'
            : 'Deployment Prevented',
        decisionMessage: readyForDeployment
            ? 'Deployment will include only compatible metadata.'
            : 'No deployment has been started because blocking compatibility issues were detected.',
        decisionClass: readyForDeployment
            ? 'readiness-decision readiness-decision_ready'
            : 'readiness-decision readiness-decision_blocked',
        deploymentSkipped: data.deploymentSkipped === true,
        reason: data.reason || null,
        showDeployActions: readyForDeployment === true,
        showBlockedActions: readyForDeployment !== true
    };
}

_resolveReadyForDeployment(deploymentReadiness = {}) {
    if (
        Object.prototype.hasOwnProperty.call(
            deploymentReadiness,
            'readyForDeployment'
        )
    ) {
        return deploymentReadiness.readyForDeployment === true;
    }
    // Legacy fallback when Phase 11 field is absent.
    return deploymentReadiness.canDeploy === true;
}

_isReadyForDeployment() {
    const readiness =
        this.deploymentValidationData?.deploymentReadiness ||
        this.deploymentValidationDisplay?.deploymentReadiness ||
        {};
    return this._resolveReadyForDeployment(readiness);
}

_getDisplayMetadataName(fileName, metadataType) {

    if (!fileName) {
        return fileName;
    }

    const type = metadataType || '';

    if (type === 'NamedCredential') {
        return fileName
            .replace(/\.namedCredential-meta\.xml$/i, '')
            .replace(/\.namedCredential-meta$/i, '');
    }

    if (type === 'CustomLabel') {
        return fileName.replace(/\.labels-meta\.xml$/i, '');
    }

    if (type === 'CustomMetadata') {
        return fileName.replace(/\.md-meta\.xml$/i, '');
    }

    if (type === 'ApexClass') {
        return fileName.replace(/\.cls$/i, '');
    }

    if (type === 'Flow') {
        return fileName.replace(/\.flow-meta\.xml$/i, '');
    }

    if (type === 'PermissionSet') {
        return fileName.replace(/\.permissionset-meta\.xml$/i, '');
    }

    if (type === 'Profile') {
        return fileName.replace(/\.profile-meta\.xml$/i, '');
    }

    const dotIndex = fileName.indexOf('.');

    if (dotIndex > 0) {
        return fileName.substring(0, dotIndex);
    }

    return fileName;

}

_getConnectivityBadgeClass(status) {

    const normalized = (status || '').toUpperCase();

    if (normalized === 'PASS') {
        return 'slds-badge slds-theme_success';
    }

    return 'slds-badge slds-theme_error';

}

_getReadinessBadgeClass(status) {

    const normalized = (status || '').toUpperCase();

    if (normalized === 'READY') {
        return 'slds-badge slds-theme_success';
    }

    if (normalized === 'READY_WITH_WARNINGS') {
        return 'slds-badge slds-theme_warning';
    }

    if (normalized === 'BLOCKED') {
        return 'slds-badge slds-theme_error';
    }

    return 'slds-badge slds-theme_info';

}

_getPassFailBadgeClass(status) {

    const normalized = (status || '').toUpperCase();

    if (normalized === 'PASS') {
        return 'slds-badge slds-theme_success';
    }

    if (normalized === 'FAIL') {
        return 'slds-badge slds-theme_error';
    }

    return 'slds-badge slds-theme_info';

}


}