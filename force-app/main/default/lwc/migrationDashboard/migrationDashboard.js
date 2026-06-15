import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';

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
        this.currentView = 'comparison';
        this.selectedComparison = '';
        this.selectedComparisonRecord = null;
        this.savedComparisonResults = [];
        this.groupedComparisonResults = [];
    }

    // Thin wrapper — calls original handleComparisonChange (unchanged)
    handleComparisonSelect(event) {
        this.handleComparisonChange(event);
    }
    // ────────────────────────────────────────────────────────────────────


    // ─── PHASE 2: Stage Modal Flags ──────────────────────────────────────
    isStage1ModalOpen = false;
    isStage2ModalOpen = false;
    isStage3ModalOpen = false;
    

    openStage1Modal()  { this.isStage1ModalOpen = true; }
    closeStage1Modal() { this.isStage1ModalOpen = false; }

    openStage2Modal()  { this.isStage2ModalOpen = true; }
    closeStage2Modal() { this.isStage2ModalOpen = false; }

    openStage3Modal()  { this.isStage3ModalOpen = true; }
    closeStage3Modal() { this.isStage3ModalOpen = false; }

    
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

   

    // Stage disabled flags (for button disabled attribute)
    get stage1Disabled() { return !this.stage1Active; }
    get stage2Disabled() { return !this.stage2Active; }
    get stage3Disabled() { return !this.stage3Active; }
    

    // Stage CSS classes — drives active / complete / idle appearance
    get stage1Class() { return this._stageClass(this.stage1Active, this.stage1Complete); }
    get stage2Class() { return this._stageClass(this.stage2Active, this.stage2Complete); }
    get stage3Class() { return this._stageClass(this.stage3Active, this.stage3Complete); }
    

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

    

    // Stage status pill CSS classes
    get stage1StatusClass() { return this._statusClass(this.stage1Active, this.stage1Complete); }
    get stage2StatusClass() { return this._statusClass(this.stage2Active, this.stage2Complete); }
    get stage3StatusClass() { return this._statusClass(this.stage3Active, this.stage3Complete); }
    

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

    comparisonRepoUrl = '';

    sourceBranch = '';

    destinationBranch = '';

    backendStatus = '';

    sourceMigrationCompleted = false;

    destinationMigrationCompleted = false;

    showCompareButton = false;

    sourceStatusMessage = '';

    destinationStatusMessage = '';

    differentFiles = [];

    showComparisonResults = false;

    comparisonLoading = false;

    isComparing = false;

    groupedComparisonResults = [];

    savedComparisonResults = [];

    showFileDetailsModal = false;

    selectedFile = null;

    showDiffModal = false;

    diffContent = '';

    differenceReport = null;

    showRawDiff = false;

    formattedDiff = [];

    isLoadingDiff = false;

    searchKeyword = '';

    aiSummary;

    isGeneratingSummary = false;

    formattedAiSummary = '';

    aiExplanation = '';

    aiProviderName = '';

    isGeneratingExplanation = false;

    selectedModel = 'gemini';

    compareCompleted = false;

    isNewComparisonModalOpen = false;

    isConnectOrgModalOpen = false;

    statusPollingInterval;

    activeMigrationType;

    isSourceRetrievalRunning = false;

    isDestinationRetrievalRunning = false;


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

    handleSaveComparison() {
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
            comparisonName: this.comparisonName,
            sourceOrgId: this.sourceOrgId,
            destinationOrgId: this.destinationOrgId
        })
        .then(() => {
            refreshApex(this.wiredComparisonResult);
            alert('Comparison Saved Successfully');
        })
        .catch(error => {
            console.error(error);
        });
    }

    handleComparisonChange(event) {
        this.selectedComparison = event.detail.value;
        this.compareCompleted = false;
        this.showComparisonResults = false;

        // CHANGE 3 — Clear stale AI state when switching comparisons
        this.aiSummary = '';
        this.formattedAiSummary = '';
        this.aiExplanation = '';
        this.aiProviderName = '';
        this.isGeneratingSummary = false;
        this.isGeneratingExplanation = false;

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
        })
        .catch(error => {
            console.error(error);
        });
    }

    handleComparisonRepoChange(event) {
        this.comparisonRepoUrl = event.target.value;
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

        this.isSourceRetrievalRunning = true;


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
            alert(JSON.stringify(error));
        });
    }

    handleDestinationMigration() {
        if (!this.destinationBranch) {
            alert('Please enter Destination Branch');
            return;
        }
        this.isDestinationRetrievalRunning = true;
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
                    this.showComparisonResults = true;
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
            return;
        }
        getComparisonResults({
            comparisonId: this.selectedComparison
        })
        .then(result => {
            this.savedComparisonResults = result;
            console.log('Saved Results:', result.length);
            this.buildGroupedResults();
            console.log('First Record:', JSON.stringify(result[0]));

            // CHANGE 4 — If saved results exist, comparison already ran; keep button disabled
            if (result && result.length > 0) {
                this.compareCompleted = true;
            }
        })
        .catch(error => {
            console.error('Load Results Error', error);
        });
    }

    buildGroupedResults() {
        const grouped = {};
        this.savedComparisonResults.forEach(record => {
            if (
                this.searchKeyword &&
                !record.File_Name__c.toLowerCase().includes(this.searchKeyword)
            ) {
                return;
            }
            const type = record.Metadata_Type__c || 'Other';
            if (!grouped[type]) {
                grouped[type] = {
                    type: type,
                    count: 0,
                    expanded: false,
                    files: []
                };
            }
            grouped[type].count++;
            grouped[type].files.push({
                ...record,
                badgeClass: this.getBadgeClass(record.Change_Type__c)
            });
        });
        this.groupedComparisonResults = Object.values(grouped);
        console.log('Grouped Results:', this.groupedComparisonResults);
        console.log(JSON.stringify(this.groupedComparisonResults));
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
                this.showRawDiff = true;
                this.formattedDiff = this.formatDiff(response.diff || '');
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

    toggleRawDiff() {
        this.showRawDiff = !this.showRawDiff;
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
            return 'Exists in Source Org • Missing in Destination Org';
        }
        if (this.differenceReport.changeType === 'DELETED') {
            return 'Missing in Source Org • Exists in Destination Org';
        }
        return 'Exists in Both Orgs • Content is Different';
    }

    handleSearch(event) {
        this.searchKeyword = event.target.value.toLowerCase();
        this.buildGroupedResults();
    }

    // AI Summary Generation — unchanged
    async generateAISummary() {
        this.isGeneratingSummary = true;
        try {
            const response = await fetch(
                'https://metadata-backup-backend.onrender.com/api/ai/comparison-summary',
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
            }
        } catch(error) {
            console.error(error);
        }
        this.isGeneratingSummary = false;
    }

    async handleExplainWithAI() {
        this.isGeneratingExplanation = true;
        try {
            const response = await fetch(
                'https://metadata-backup-backend.onrender.com/api/ai/explain-diff',
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
        this.isNewComparisonModalOpen = true;
    }

    closeNewComparisonModal() {
        this.isNewComparisonModalOpen = false;
    }

    openConnectOrgModal() {
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

    this.isSourceRetrievalRunning = false;
    this.isDestinationRetrievalRunning = false;

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

                this.isSourceRetrievalRunning = false;
                this.isDestinationRetrievalRunning = false;

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

}