import { LightningElement, track } from 'lwc';

import getConnectedOrgs
from '@salesforce/apex/ConnectedOrgService.getConnectedOrgs';

import executeBackup
from '@salesforce/apex/BackupExecutionService.executeBackup';

import getLogs
from '@salesforce/apex/BackupController.getLogs';

import { ShowToastEvent }
from 'lightning/platformShowToastEvent';

export default class BackupDashboard
extends LightningElement {

    // =====================================
    // Variables
    // =====================================

    @track repoUrl = '';

    @track loading = false;

    @track currentStep =
        'Waiting to start backup';

    @track logs = [];

    @track jobId = '';

    @track orgOptions = [];

    @track selectedOrgId = '';

    @track selectedEnvironment =
        'production';

    connectedOrgs = [];

    pollingInterval;

    // =====================================
    // Environment Options
    // =====================================

    environmentOptions = [

        {
            label: 'Production',
            value: 'production'
        },

        {
            label: 'Sandbox',
            value: 'sandbox'
        }

    ];

    // =====================================
    // Connected Callback
    // =====================================

    connectedCallback() {

        this.loadConnectedOrgs();

    }

    // =====================================
    // Load Connected Orgs
    // =====================================

    async loadConnectedOrgs() {

        try {

            const result =
                await getConnectedOrgs();

            this.connectedOrgs = result;

            this.orgOptions =
                result.map(org => {

                    return {

                        label:
                            `${org.Name} (${org.Environment__c})`,

                        value:
                            org.Id

                    };

                });

        } catch (error) {

            console.error(error);

            this.showToast(

                'Error',

                'Failed to load connected orgs',

                'error'

            );

        }

    }

    // =====================================
    // Handle Environment
    // =====================================

    handleEnvironmentChange(event) {

        this.selectedEnvironment =
            event.detail.value;

    }

    // =====================================
    // Connect Salesforce Org
    // =====================================

    connectOrg() {

        const oauthUrl =

            `https://salesforce-backup-backend-1.onrender.com` +

            `/connect-salesforce?environment=` +

            `${this.selectedEnvironment}`;

        // =================================
        // Redirect Same Tab
        // =================================

        window.location.href =
            oauthUrl;

    }

    // =====================================
    // Handle Org Change
    // =====================================

    handleOrgChange(event) {

        this.selectedOrgId =
            event.detail.value;

    }

    // =====================================
    // Handle Repo URL
    // =====================================

    handleRepoChange(event) {

        this.repoUrl =
            event.target.value;

    }

    // =====================================
    // Start Backup
    // =====================================

    async startBackup() {

        // =================================
        // Org Validation
        // =================================

        if (!this.selectedOrgId) {

            this.showToast(

                'Validation Error',

                'Please select a connected org',

                'warning'

            );

            return;

        }

        // =================================
        // Repo Validation
        // =================================

        if (!this.repoUrl) {

            this.showToast(

                'Validation Error',

                'Please enter repository URL',

                'warning'

            );

            return;

        }

        try {

            this.loading = true;

            this.currentStep =
                'Starting Backup...';

            const result =
                await executeBackup({

                    connectedOrgId:
                        this.selectedOrgId,

                    repoUrl:
                        this.repoUrl,

                    clientId:
                        '3MVG9YFqzc_KnL.wlgv7lI0sbWxevX27fdhmzJgDqzbR9rLdObZmXRfqDpDFAMV.AACUyOZSc1B5MAlH6jV1S',

                    clientSecret:
                        '6FAEB2100493E7A5855B6C15AA5DF092F3D4ADBB28DD4A98978D2EE4A4BE1F99'

                });

            const response =
                JSON.parse(result);

            if (

                response.success &&

                response.jobId

            ) {

                this.jobId =
                    response.jobId;

                this.currentStep =
                    'Backup in progress...';

                this.startPolling();

                this.showToast(

                    'Success',

                    'Backup Started Successfully',

                    'success'

                );

            } else {

                this.loading = false;

                this.showToast(

                    'Error',

                    response.message ||

                    'Failed to start backup',

                    'error'

                );

            }

        } catch (error) {

            console.error(error);

            this.loading = false;

            this.showToast(

                'Error',

                'Backup Failed',

                'error'

            );

        }

    }

    // =====================================
    // Poll Logs
    // =====================================

    startPolling() {

        this.pollingInterval =

            setInterval(async () => {

                try {

                    const result =
                        await getLogs({

                            jobId:
                                this.jobId

                        });

                    const response =
                        JSON.parse(result);

                    this.logs =
                        response.logs;

                    const finalLog =

                        response.logs[
                            response.logs.length - 1
                        ];

                    if (

                        finalLog &&

                        (

                            finalLog.includes(
                                'completed'
                            ) ||

                            finalLog.includes(
                                'ERROR'
                            )

                        )

                    ) {

                        clearInterval(
                            this.pollingInterval
                        );

                        this.loading = false;

                        this.currentStep =
                            'Backup Finished';

                    }

                } catch (error) {

                    console.error(error);

                    clearInterval(
                        this.pollingInterval
                    );

                    this.loading = false;

                }

            }, 3000);

    }

    // =====================================
    // Toast Helper
    // =====================================

    showToast(
        title,
        message,
        variant
    ) {

        this.dispatchEvent(

            new ShowToastEvent({

                title,
                message,
                variant

            })

        );

    }

}