import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import BACKEND_BASE_URL
from '@salesforce/label/c.Backend_Base_URL';

import updateSelection
from '@salesforce/apex/DeploymentController.updateSelection';

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

import getDeploymentReview
from '@salesforce/apex/DeploymentReviewController.getDeploymentReview';

import GITHUB_REPO_URL
from '@salesforce/label/c.GitHub_Repo_URL';

import validateSource
from '@salesforce/apex/SourceValidationController.validateDeployment';

import validateDestinationDeployment
from '@salesforce/apex/DeploymentValidationController.validateDeployment';

import saveDeploymentHistory
from '@salesforce/apex/DeploymentHistoryController.saveDeploymentHistory';

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

    // AI Summary Generation — unchanged
    async generateAISummary() {
        this.isGeneratingSummary = true;
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

handleSelection(event) {

    const recordId =
        event.target.dataset.id;

    const selected =
        event.target.checked;

    updateSelection({
        resultId: recordId,
        selected: selected
    })
    .then(() => {

    this.savedComparisonResults =
        this.savedComparisonResults.map(file => {

            if(file.Id === recordId){
                return {
                    ...file,
                    Selected_For_Deployment__c: selected
                };
            }

            return file;
        });

    this.groupedComparisonResults.forEach(group => {

        if(group.files){

            group.files.forEach(file => {

                if(file.Id === recordId){
                    file.Selected_For_Deployment__c =
                        selected;
                }

            });

        }

    });

    this.groupedComparisonResults =
        [...this.groupedComparisonResults];

})
    .catch(error => {
        console.error(error);
    });

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

        this.currentDeploymentPlanId = planId;
        this.showDeploymentReview = true;

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

selectedTestClasses = {};

showDeploymentReview = false;

currentDeploymentPlanId = null;

isLoadingDeploymentReview = false;

sourceValidationData = null;

sourceValidationDisplayItems = [];

isLoadingSourceValidation = false;

deploymentValidationData = null;

deploymentValidationDisplay = null;

isLoadingDeploymentValidation = false;

showDeployConfirmation = false;
isDeploying = false;
deployCompleted = false;

historyRecordId = null;

get deploymentLoading() {
    return this.isLoadingDeploymentReview ||
        this.isLoadingSourceValidation ||
        this.isLoadingDeploymentValidation ||
        this.isDeploying;
}

get deploymentReview() {
    return this.deploymentReviewItems;
}

get sourceValidation() {
    return this.sourceValidationData;
}

get deploymentValidation() {
    return this.deploymentValidationData;
}

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
    return this.deploymentValidationDisplay?.deploymentReadiness?.canDeploy === true &&
        this.deployCompleted !== true;
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
        return;
    }

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

    getDeploymentReview({
        comparisonId: this.selectedComparison,
        selectedMetadataJson: JSON.stringify(selectedMetadata)
    })
    .then(result => {

        this.deploymentReviewData = JSON.parse(result);

        const items =
            this._buildDeploymentReviewItems(
                this.deploymentReviewData
            );

        this.deploymentReviewItems = items;

        this._initializeSelectedTestClasses(items);

        this.isLoadingDeploymentReview = false;

    })
    .catch(error => {

        console.error(error);

        this.deploymentReviewItems = [];

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

    const destinationOrg =
        this.selectedComparisonDetails.Destination_Org__r;

    const deploymentPackage = this._buildDeploymentPackage();

    this.isLoadingDeploymentValidation = true;

    validateDestinationDeployment({
        refreshToken: destinationOrg.Refresh_Token__c,
        instanceUrl: destinationOrg.Instance_URL__c,
        orgId: destinationOrg.Org_ID__c,
        deploymentPackage: JSON.stringify(deploymentPackage)
    })
    .then(result => {

        const response = JSON.parse(result);

        this.deploymentValidationData = response;

        this.deploymentValidationDisplay =
            this._buildDeploymentValidationDisplay(
                this.deploymentValidationData
            );

        this.isLoadingDeploymentValidation = false;

        // Fresh validation unlocks Deploy again after a prior successful deploy.
        this.deployCompleted = false;

        // Persist deployment history independently — same pattern as
        // compareBranches → saveComparisonResults. Must not affect validation UI.
        if (response && response.deploymentHistory) {
            this._persistDeploymentHistory(response.deploymentHistory);
        }

    })
    .catch(error => {

        console.error(error);

        this.deploymentValidationData = null;

        this.deploymentValidationDisplay = null;

        this.isLoadingDeploymentValidation = false;

    });

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
            this._buildDeploymentPackageSelectedTestClasses()
    };

    if (deploymentMode) {
        deploymentPackage.deploymentMode = deploymentMode;
    }

    return deploymentPackage;

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
        (row, index) => ({
            id: `dependency-${index}`,
            name: row.name,
            existsLabel: row.existsInDestination ? 'Yes' : 'No',
            includedLabel:
                row.includedInDeploymentPackage ? 'Yes' : 'No',
            status: row.status || '—'
        })
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