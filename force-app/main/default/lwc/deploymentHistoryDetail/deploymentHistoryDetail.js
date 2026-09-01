import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import TIMELINE_FIELD from '@salesforce/schema/Deployment_History__c.Timeline__c';
import DEPLOYMENT_SUMMARY_FIELD from '@salesforce/schema/Deployment_History__c.Deployment_Summary__c';
import VALIDATION_SUMMARY_FIELD from '@salesforce/schema/Deployment_History__c.Validation_Summary__c';
import TEST_RESULTS_FIELD from '@salesforce/schema/Deployment_History__c.Test_Results__c';
import CLI_COMPATIBILITY_FIELD from '@salesforce/schema/Deployment_History__c.CLI_Compatibility__c';

const FIELDS = [
    TIMELINE_FIELD,
    DEPLOYMENT_SUMMARY_FIELD,
    VALIDATION_SUMMARY_FIELD,
    TEST_RESULTS_FIELD,
    CLI_COMPATIBILITY_FIELD
];

export default class DeploymentHistoryDetail extends LightningElement {
    @api recordId;

    timelineItems = [];
    deploymentSummaryRows = [];
    validationSummaryRows = [];
    testResultRows = [];
    failingTests = [];
    cliCompatibilityRows = [];
    errorMessage;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this.errorMessage = undefined;
            this._hydrate(data);
        } else if (error) {
            this.errorMessage =
                error.body?.message ||
                error.message ||
                'Unable to load deployment history details.';
            this._clear();
        }
    }

    get hasTimeline() {
        return this.timelineItems.length > 0;
    }

    get hasDeploymentSummary() {
        return this.deploymentSummaryRows.length > 0;
    }

    get hasValidationSummary() {
        return this.validationSummaryRows.length > 0;
    }

    get hasTestResults() {
        return this.testResultRows.length > 0 || this.failingTests.length > 0;
    }

    get hasFailingTests() {
        return this.failingTests.length > 0;
    }

    get hasCliCompatibility() {
        return this.cliCompatibilityRows.length > 0;
    }

    get hasContent() {
        return (
            this.hasTimeline ||
            this.hasDeploymentSummary ||
            this.hasValidationSummary ||
            this.hasTestResults ||
            this.hasCliCompatibility
        );
    }

    _hydrate(data) {
        this.timelineItems = this._parseTimeline(
            getFieldValue(data, TIMELINE_FIELD)
        );
        this.deploymentSummaryRows = this._parseDeploymentSummary(
            getFieldValue(data, DEPLOYMENT_SUMMARY_FIELD)
        );
        this.validationSummaryRows = this._parseValidationSummary(
            getFieldValue(data, VALIDATION_SUMMARY_FIELD)
        );

        const testResults = this._parseTestResults(
            getFieldValue(data, TEST_RESULTS_FIELD)
        );
        this.testResultRows = testResults.summaryRows;
        this.failingTests = testResults.failingTests;

        this.cliCompatibilityRows = this._parseCliCompatibility(
            getFieldValue(data, CLI_COMPATIBILITY_FIELD)
        );
    }

    _clear() {
        this.timelineItems = [];
        this.deploymentSummaryRows = [];
        this.validationSummaryRows = [];
        this.testResultRows = [];
        this.failingTests = [];
        this.cliCompatibilityRows = [];
    }

    _parseJson(raw) {
        if (!raw || typeof raw !== 'string' || !raw.trim()) {
            return null;
        }
        try {
            return JSON.parse(raw);
        } catch (e) {
            return null;
        }
    }

    _display(value) {
        if (value === null || value === undefined || value === '') {
            return '—';
        }
        if (typeof value === 'boolean') {
            return value ? 'Yes' : 'No';
        }
        return String(value);
    }

    _rowsFromPairs(pairs) {
        return pairs.map(([label, value], index) => ({
            id: `${label}-${index}`,
            label,
            value: this._display(value)
        }));
    }

    _parseTimeline(raw) {
        const parsed = this._parseJson(raw);
        if (!Array.isArray(parsed)) {
            return [];
        }

        return parsed.map((item, index) => ({
            id: `timeline-${index}`,
            stage: item?.stage || item?.name || '—',
            timestamp: item?.timestamp || '—'
        }));
    }

    _parseDeploymentSummary(raw) {
        const parsed = this._parseJson(raw);
        if (!parsed || typeof parsed !== 'object') {
            return [];
        }

        return this._rowsFromPairs([
            ['Components Deployed', parsed.componentsDeployed],
            ['Components Failed', parsed.componentsFailed],
            ['Tests Run', parsed.testsRun],
            ['Coverage', parsed.overallCoverage],
            ['Deployment Status', parsed.deploymentStatus || parsed.status]
        ]);
    }

    _parseValidationSummary(raw) {
        const parsed = this._parseJson(raw);
        if (!parsed || typeof parsed !== 'object') {
            return [];
        }

        return this._rowsFromPairs([
            ['Destination Connectivity', parsed.destinationConnectivity],
            ['Metadata Validation', parsed.metadataValidation],
            ['Dependency Validation', parsed.dependencyValidation],
            ['Overall Status', parsed.overallStatus || parsed.status],
            ['Can Deploy', parsed.canDeploy]
        ]);
    }

    _parseTestResults(raw) {
        const parsed = this._parseJson(raw);
        if (!parsed || typeof parsed !== 'object') {
            return { summaryRows: [], failingTests: [] };
        }

        const summaryRows = this._rowsFromPairs([
            ['Tests Run', parsed.testsRun],
            ['Tests Passed', parsed.testsPassed],
            ['Tests Failed', parsed.testsFailed]
        ]);

        const failingSource = Array.isArray(parsed.failingTests)
            ? parsed.failingTests
            : [];

        const failingTests = failingSource.map((item, index) => ({
            id: `fail-${index}`,
            className: item?.className || '—',
            methodName: item?.methodName || '—',
            message: item?.message || '—'
        }));

        return { summaryRows, failingTests };
    }

    _parseCliCompatibility(raw) {
        const parsed = this._parseJson(raw);
        if (!parsed || typeof parsed !== 'object') {
            return [];
        }

        return this._rowsFromPairs([
            ['CLI Version', parsed.cliVersion],
            ['Validation Flag', parsed.deploymentValidationFlag],
            ['Supports Dry Run', parsed.supportsDryRun],
            ['Supports Check Only', parsed.supportsCheckOnly],
            ['Detection Source', parsed.detectionSource]
        ]);
    }
}