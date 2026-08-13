/**
 * Phase 18.3.2 — Curated Support Bundle validationContext.
 * Builds a small diagnostic snapshot for POST /api/deployment/support-bundle.
 * Does not mutate the source validation payload. Does not call AI/deploy/validate.
 */

const IDENTIFIER_KEYS = Object.freeze([
    'historyId',
    'deploymentId',
    'validationCorrelationId',
    'correlationId',
    'requestId'
]);

const SCALAR_STATUS_KEYS = Object.freeze([
    'deploymentMode',
    'executionMode',
    'status',
    'overallStatus',
    'success'
]);

const PHASE17_REPORT_KEYS = Object.freeze([
    'failureClassification',
    'resolutionReport',
    'autoFixReport',
    'autoValidationReport',
    'enterpriseDeploymentReport',
    'safeSkipReport'
]);

const DEPLOYMENT_SUMMARY_KEEP = Object.freeze([
    'status',
    'overallStatus',
    'deploymentStatus',
    'counts',
    'totalMetadata',
    'successfulMetadata',
    'failedMetadata',
    'warnings',
    'errors',
    'componentsValidated',
    'componentsFailed',
    'componentsDeployed',
    'testsRun',
    'testsFailed',
    'overallCoverage',
    'success'
]);

const PACKAGE_SUMMARY_KEEP = Object.freeze([
    'metadataCount',
    'dependencyCount',
    'testClassCount',
    'totalComponents',
    'typeCount',
    'memberCount',
    'status',
    'packageStatus',
    'manifestStatus',
    'apiVersion',
    'overallStatus'
]);

const DEPENDENCY_RESULT_KEEP = Object.freeze([
    'name',
    'type',
    'status',
    'existsInDestination',
    'includedInDeploymentPackage',
    'message',
    'resolution'
]);

const COMPONENT_FAILURE_KEEP = Object.freeze([
    'metadataType',
    'metadataName',
    'fullName',
    'fileName',
    'problem',
    'problemType',
    'lineNumber',
    'columnNumber',
    'success',
    'changed',
    'created',
    'deleted',
    'warning',
    'errorStatus'
]);

function hasOwn(obj, key) {
    return Object.prototype.hasOwnProperty.call(obj, key);
}

function isPlainObject(value) {
    return value != null && typeof value === 'object' && !Array.isArray(value);
}

function pickExisting(source, keys) {
    if (!isPlainObject(source)) {
        return null;
    }
    const out = {};
    let count = 0;
    for (const key of keys) {
        if (hasOwn(source, key) && source[key] != null) {
            out[key] = source[key];
            count += 1;
        }
    }
    return count > 0 ? out : null;
}

function slimDeploymentSummary(summary) {
    return pickExisting(summary, DEPLOYMENT_SUMMARY_KEEP);
}

function slimComponentFailure(failure) {
    if (!isPlainObject(failure)) {
        return null;
    }
    const slim = pickExisting(failure, COMPONENT_FAILURE_KEEP);
    return slim;
}

function slimDeploymentDiagnostics(diagnostics) {
    if (!isPlainObject(diagnostics)) {
        return null;
    }

    const slim = {};
    if (hasOwn(diagnostics, 'deploymentId') && diagnostics.deploymentId != null) {
        slim.deploymentId = diagnostics.deploymentId;
    }
    if (hasOwn(diagnostics, 'status') && diagnostics.status != null) {
        slim.status = diagnostics.status;
    }
    if (hasOwn(diagnostics, 'overallStatus') && diagnostics.overallStatus != null) {
        slim.overallStatus = diagnostics.overallStatus;
    }
    if (isPlainObject(diagnostics.summary)) {
        slim.summary = { ...diagnostics.summary };
    }
    if (Array.isArray(diagnostics.componentFailures)) {
        slim.componentFailures = diagnostics.componentFailures
            .map(slimComponentFailure)
            .filter(Boolean);
    }

    return Object.keys(slim).length > 0 ? slim : null;
}

function slimDependencyResult(row) {
    return pickExisting(row, DEPENDENCY_RESULT_KEEP);
}

function slimDependencyValidation(dependencyValidation) {
    if (!isPlainObject(dependencyValidation)) {
        return null;
    }

    const slim = {};
    if (
        hasOwn(dependencyValidation, 'overallStatus') &&
        dependencyValidation.overallStatus != null
    ) {
        slim.overallStatus = dependencyValidation.overallStatus;
    }
    if (hasOwn(dependencyValidation, 'message') && dependencyValidation.message != null) {
        slim.message = dependencyValidation.message;
    }
    if (hasOwn(dependencyValidation, 'status') && dependencyValidation.status != null) {
        slim.status = dependencyValidation.status;
    }

    const results = Array.isArray(dependencyValidation.results)
        ? dependencyValidation.results
        : [];
    const relevant = results.filter((row) => {
        const status = String(row?.status || '').toUpperCase();
        return status === 'BLOCKED' || status === 'WARNING' || status === 'FAIL';
    });

    slim.results = relevant.map(slimDependencyResult).filter(Boolean);

    const blockedCount = results.filter(
        (row) => String(row?.status || '').toUpperCase() === 'BLOCKED'
    ).length;
    const warningCount = results.filter(
        (row) => String(row?.status || '').toUpperCase() === 'WARNING'
    ).length;
    const passCount = results.filter(
        (row) => String(row?.status || '').toUpperCase() === 'PASS'
    ).length;

    slim.summary = {
        total: results.length,
        blocked: blockedCount,
        warning: warningCount,
        pass: passCount,
        relevantFailures: slim.results.length
    };

    if (isPlainObject(dependencyValidation.summary)) {
        slim.summary = {
            ...slim.summary,
            ...pickExisting(dependencyValidation.summary, [
                'total',
                'blocked',
                'warning',
                'pass',
                'failed',
                'counts'
            ])
        };
    }

    return slim;
}

function slimDeploymentReadiness(readiness) {
    if (!isPlainObject(readiness)) {
        return null;
    }

    const slim = {};
    for (const key of [
        'overallStatus',
        'status',
        'canDeploy',
        'readyForDeployment'
    ]) {
        if (hasOwn(readiness, key) && readiness[key] != null) {
            slim[key] = readiness[key];
        }
    }
    if (isPlainObject(readiness.summary)) {
        slim.summary = { ...readiness.summary };
    }
    if (Array.isArray(readiness.blockingIssues)) {
        slim.blockingIssueCount = readiness.blockingIssues.length;
    } else if (
        hasOwn(readiness, 'blockingIssueCount') &&
        readiness.blockingIssueCount != null
    ) {
        slim.blockingIssueCount = readiness.blockingIssueCount;
    }
    if (Array.isArray(readiness.warnings)) {
        slim.warningCount = readiness.warnings.length;
    } else if (hasOwn(readiness, 'warningCount') && readiness.warningCount != null) {
        slim.warningCount = readiness.warningCount;
    }

    return Object.keys(slim).length > 0 ? slim : null;
}

function slimDeploymentReadinessAnalysis(analysis) {
    if (!isPlainObject(analysis)) {
        return null;
    }

    const slim = {};
    if (hasOwn(analysis, 'overallStatus') && analysis.overallStatus != null) {
        slim.overallStatus = analysis.overallStatus;
    }
    if (hasOwn(analysis, 'status') && analysis.status != null) {
        slim.status = analysis.status;
    }
    if (isPlainObject(analysis.summary)) {
        slim.summary = { ...analysis.summary };
    }

    return Object.keys(slim).length > 0 ? slim : null;
}

function slimPackageLikeSummary(summary) {
    return pickExisting(summary, PACKAGE_SUMMARY_KEEP);
}

function resolveGeneratedAiReport(data, onDemandAiResolution) {
    if (
        isPlainObject(onDemandAiResolution) &&
        onDemandAiResolution.generated === true
    ) {
        return onDemandAiResolution;
    }
    if (
        isPlainObject(data?.aiResolutionReport) &&
        data.aiResolutionReport.generated === true
    ) {
        return data.aiResolutionReport;
    }
    if (
        isPlainObject(data?.aiResolution) &&
        data.aiResolution.generated === true
    ) {
        return data.aiResolution;
    }
    return null;
}

/**
 * @param {object|null|undefined} data deploymentValidationData
 * @param {{ backendValidationHistoryId?: string|null, onDemandAiResolution?: object|null }} [options]
 * @returns {object|null}
 */
export function buildCuratedSupportBundleValidationContext(
    data,
    {
        backendValidationHistoryId = null,
        onDemandAiResolution = null
    } = {}
) {
    if (!isPlainObject(data)) {
        return null;
    }

    const context = {};

    for (const key of IDENTIFIER_KEYS) {
        if (hasOwn(data, key) && data[key] != null) {
            context[key] = data[key];
        }
    }

    for (const key of SCALAR_STATUS_KEYS) {
        if (hasOwn(data, key) && data[key] != null) {
            context[key] = data[key];
        }
    }

    for (const key of PHASE17_REPORT_KEYS) {
        if (hasOwn(data, key) && data[key] != null) {
            context[key] = data[key];
        }
    }

    if (hasOwn(data, 'metadataCount') && data.metadataCount != null) {
        context.metadataCount = data.metadataCount;
    }
    if (hasOwn(data, 'dependencyCount') && data.dependencyCount != null) {
        context.dependencyCount = data.dependencyCount;
    }

    const summarySource =
        data.deploymentSummary ||
        data.checkOnlyDeployment?.deploymentSummary ||
        data.deploymentExecution?.deploymentSummary ||
        null;
    const slimSummary = slimDeploymentSummary(summarySource);
    if (slimSummary) {
        context.deploymentSummary = slimSummary;
    }

    const diagnosticsSource =
        data.deploymentDiagnostics ||
        data.checkOnlyDeployment?.deploymentDiagnostics ||
        data.deploymentExecution?.deploymentDiagnostics ||
        null;
    const slimDiagnostics = slimDeploymentDiagnostics(diagnosticsSource);
    if (slimDiagnostics) {
        context.deploymentDiagnostics = slimDiagnostics;
    }

    const slimDeps = slimDependencyValidation(data.dependencyValidation);
    if (slimDeps) {
        context.dependencyValidation = slimDeps;
    }

    const slimReadiness = slimDeploymentReadiness(data.deploymentReadiness);
    if (slimReadiness) {
        context.deploymentReadiness = slimReadiness;
    }

    const slimAnalysis = slimDeploymentReadinessAnalysis(
        data.deploymentReadinessAnalysis
    );
    if (slimAnalysis) {
        context.deploymentReadinessAnalysis = slimAnalysis;
    }

    const slimPackage = slimPackageLikeSummary(data.packageSummary);
    if (slimPackage) {
        context.packageSummary = slimPackage;
    }

    const slimSelection = slimPackageLikeSummary(data.selectionSummary);
    if (slimSelection) {
        context.selectionSummary = slimSelection;
    }

    const slimManifest = slimPackageLikeSummary(data.manifestSummary);
    if (slimManifest) {
        context.manifestSummary = slimManifest;
    }

    const aiReport = resolveGeneratedAiReport(data, onDemandAiResolution);
    if (aiReport) {
        context.aiResolutionReport = aiReport;
    }

    if (backendValidationHistoryId && !context.historyId) {
        context.historyId = backendValidationHistoryId;
        context.validationCorrelationId =
            context.validationCorrelationId || backendValidationHistoryId;
    }

    if (!context.failureClassification && !context.enterpriseDeploymentReport) {
        return null;
    }

    return context;
}

/**
 * Dev/test-only request size helper. Does not log bodies or secrets.
 * @param {object} requestPayload
 * @returns {{ byteLength: number, charLength: number }}
 */
export function measureSupportBundleRequestSize(requestPayload) {
    const serialized = JSON.stringify(requestPayload);
    let byteLength = serialized.length;
    if (typeof TextEncoder !== 'undefined') {
        byteLength = new TextEncoder().encode(serialized).length;
    }
    return {
        byteLength,
        charLength: serialized.length
    };
}

export const SUPPORT_BUNDLE_CURATION = Object.freeze({
    IDENTIFIER_KEYS,
    PHASE17_REPORT_KEYS,
    DEPLOYMENT_SUMMARY_KEEP,
    PACKAGE_SUMMARY_KEEP
});