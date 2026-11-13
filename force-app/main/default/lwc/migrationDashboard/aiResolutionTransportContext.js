/**
 * Slim AI Resolution transport context for POST /api/deployment/ai-resolution.
 *
 * Mirrors what backend buildStructuredContext() + collectKnownItems() consume,
 * without shipping raw evidence / componentFailures arrays that the backend
 * already discards before building the AI prompt.
 *
 * Does not mutate the source validation payload.
 * Does not invent source/destination facts or SAFE_SKIP decisions.
 */

const TRANSPORT_KEYS = Object.freeze([
    'failureClassification',
    'resolutionReport',
    'autoFixReport',
    'autoValidationReport',
    'enterpriseDeploymentReport',
    'deploymentDiagnostics',
    'deploymentSummary',
    'aiResolutionFactPack'
]);

function isPlainObject(value) {
    return value != null && typeof value === 'object' && !Array.isArray(value);
}

function cloneJson(value) {
    if (value === undefined) {
        return undefined;
    }
    return JSON.parse(JSON.stringify(value));
}

function resolveCliProblem(entry) {
    if (!isPlainObject(entry)) {
        return null;
    }
    if (typeof entry.cliProblem === 'string' && entry.cliProblem.length) {
        return entry.cliProblem;
    }
    if (
        isPlainObject(entry.evidence) &&
        typeof entry.evidence.problem === 'string' &&
        entry.evidence.problem.length
    ) {
        return entry.evidence.problem;
    }
    return null;
}

/**
 * Fields collectKnownItems() / buildStructuredContext() read from a failure.
 * Raw evidence blobs are intentionally omitted after cliProblem is extracted.
 */
function slimFailureEntry(failure) {
    if (!isPlainObject(failure)) {
        return null;
    }

    const slim = {
        metadataType: failure.metadataType || failure.type || null,
        metadataName: failure.metadataName || failure.name || null,
        category: failure.category || null,
        severity: failure.severity || null,
        reason: failure.reason || null,
        recommendedNextStep: failure.recommendedNextStep || null,
        recommendation: failure.recommendation || null,
        recommendedAction: failure.recommendedAction || null,
        summary: failure.summary || null,
        title: failure.title || null,
        resolutionType: failure.resolutionType || null,
        autoFixed: failure.autoFixed === true,
        autoFixAvailable: failure.autoFixAvailable === true,
        canAutoFix: failure.canAutoFix === true,
        userActionRequired:
            typeof failure.userActionRequired === 'boolean'
                ? failure.userActionRequired
                : undefined,
        safeToSkip:
            failure.safeToSkip === true
                ? true
                : failure.safeToSkip === false
                  ? false
                  : null
    };

    const cliProblem = resolveCliProblem(failure);
    if (cliProblem) {
        slim.cliProblem = cliProblem;
    }

    if (slim.userActionRequired === undefined) {
        delete slim.userActionRequired;
    }

    return slim;
}

function slimResolutionEntry(resolution) {
    if (!isPlainObject(resolution)) {
        return null;
    }

    const slim = {
        metadataType: resolution.metadataType || resolution.type || null,
        metadataName: resolution.metadataName || resolution.name || null,
        resolutionType: resolution.resolutionType || null,
        severity: resolution.severity || null,
        title: resolution.title || null,
        summary: resolution.summary || null,
        reason: resolution.reason || null,
        recommendation: resolution.recommendation || null,
        recommendedNextStep: resolution.recommendedNextStep || null,
        recommendedAction: resolution.recommendedAction || null,
        autoFixAvailable: resolution.autoFixAvailable === true,
        autoFixed: resolution.autoFixed === true,
        canAutoFix: resolution.canAutoFix === true,
        userActionRequired:
            typeof resolution.userActionRequired === 'boolean'
                ? resolution.userActionRequired
                : undefined,
        safeToSkip:
            resolution.safeToSkip === true
                ? true
                : resolution.safeToSkip === false
                  ? false
                  : null
    };

    if (slim.userActionRequired === undefined) {
        delete slim.userActionRequired;
    }

    return slim;
}

function slimAutoFixEntry(fix) {
    if (!isPlainObject(fix)) {
        return null;
    }

    return {
        metadataType: fix.metadataType || null,
        metadataName: fix.metadataName || null,
        fixType: fix.fixType || null,
        action: fix.action || null,
        executed: fix.executed === true,
        successful: fix.successful === true
    };
}

function slimNextAction(action) {
    if (!isPlainObject(action)) {
        return null;
    }

    return {
        priority: action.priority ?? null,
        type: action.type || null,
        metadataType: action.metadataType || null,
        metadataName: action.metadataName || null,
        message: action.message || null,
        completed: action.completed === true
    };
}

function slimFailureClassification(raw) {
    if (!isPlainObject(raw)) {
        return undefined;
    }

    return {
        overallStatus: raw.overallStatus || null,
        summary: raw.summary != null ? cloneJson(raw.summary) : null,
        failures: Array.isArray(raw.failures)
            ? raw.failures.map(slimFailureEntry).filter(Boolean)
            : []
    };
}

function slimResolutionReport(raw) {
    if (!isPlainObject(raw)) {
        return undefined;
    }

    return {
        overallStatus: raw.overallStatus || null,
        summary: raw.summary != null ? cloneJson(raw.summary) : null,
        resolutions: Array.isArray(raw.resolutions)
            ? raw.resolutions.map(slimResolutionEntry).filter(Boolean)
            : []
    };
}

function slimAutoFixReport(raw) {
    if (!isPlainObject(raw)) {
        return undefined;
    }

    return {
        autoFixAvailable: raw.autoFixAvailable === true,
        autoFixApplied: raw.autoFixApplied === true,
        fixes: Array.isArray(raw.fixes)
            ? raw.fixes.map(slimAutoFixEntry).filter(Boolean)
            : []
    };
}

function slimAutoValidationReport(raw) {
    if (!isPlainObject(raw)) {
        return undefined;
    }

    return {
        attempts: raw.attempts ?? null,
        autoValidationExecuted: raw.autoValidationExecuted === true,
        initialStatus: raw.initialStatus || null,
        finalStatus: raw.finalStatus || null,
        autoFixesApplied: raw.autoFixesApplied ?? null,
        revalidated: raw.revalidated === true
    };
}

function slimEnterpriseDeploymentReport(raw) {
    if (!isPlainObject(raw)) {
        return undefined;
    }

    // buildStructuredContext keeps status/summary/statistics/nextActions.
    // collectKnownItems ALSO reads failures + resolutions — preserve slim copies.
    const slim = {
        overallStatus: raw.overallStatus || null,
        summary: raw.summary != null ? cloneJson(raw.summary) : null,
        statistics: raw.statistics != null ? cloneJson(raw.statistics) : null,
        nextActions: Array.isArray(raw.nextActions)
            ? raw.nextActions.map(slimNextAction).filter(Boolean)
            : []
    };

    if (Array.isArray(raw.failures)) {
        slim.failures = raw.failures.map(slimFailureEntry).filter(Boolean);
    }

    if (Array.isArray(raw.resolutions)) {
        slim.resolutions = raw.resolutions
            .map(slimResolutionEntry)
            .filter(Boolean);
    }

    return slim;
}

function slimDeploymentDiagnostics(raw) {
    if (!isPlainObject(raw)) {
        return undefined;
    }

    const failureArray = Array.isArray(raw.componentFailures)
        ? raw.componentFailures
        : null;
    const warningArray = Array.isArray(raw.componentWarnings)
        ? raw.componentWarnings
        : Array.isArray(raw.warnings)
          ? raw.warnings
          : null;

    return {
        componentFailureCount:
            failureArray != null
                ? failureArray.length
                : typeof raw.componentFailureCount === 'number'
                  ? raw.componentFailureCount
                  : 0,
        warningCount:
            warningArray != null
                ? warningArray.length
                : typeof raw.warningCount === 'number'
                  ? raw.warningCount
                  : 0
    };
}

function slimDeploymentSummary(raw) {
    if (!isPlainObject(raw)) {
        return undefined;
    }

    return {
        status: raw.status || null,
        success: raw.success,
        message: raw.message || null
    };
}

/**
 * Pass through Phase 1 fact pack without mutating caller state.
 * Backend sanitizeFactPackForAi() remains authoritative for final shape.
 */
function slimAiResolutionFactPack(raw) {
    if (!isPlainObject(raw)) {
        return undefined;
    }
    return cloneJson(raw);
}

function resolveDeploymentSummary(data) {
    if (isPlainObject(data.deploymentSummary)) {
        return data.deploymentSummary;
    }
    if (isPlainObject(data.checkOnlyDeployment?.deploymentSummary)) {
        return data.checkOnlyDeployment.deploymentSummary;
    }
    if (isPlainObject(data.deploymentExecution?.deploymentSummary)) {
        return data.deploymentExecution.deploymentSummary;
    }
    return null;
}

/**
 * Build the slim AI Resolution context object for Apex → backend transport.
 *
 * @param {object|null|undefined} data deploymentValidationData (or equivalent)
 * @returns {object|null}
 */
export function buildAiResolutionTransportContext(data) {
    if (!isPlainObject(data)) {
        return null;
    }

    const context = {};

    const failureClassification = slimFailureClassification(
        data.failureClassification
    );
    if (failureClassification) {
        context.failureClassification = failureClassification;
    }

    const resolutionReport = slimResolutionReport(data.resolutionReport);
    if (resolutionReport) {
        context.resolutionReport = resolutionReport;
    }

    const autoFixReport = slimAutoFixReport(data.autoFixReport);
    if (autoFixReport) {
        context.autoFixReport = autoFixReport;
    }

    const autoValidationReport = slimAutoValidationReport(
        data.autoValidationReport
    );
    if (autoValidationReport) {
        context.autoValidationReport = autoValidationReport;
    }

    const enterpriseDeploymentReport = slimEnterpriseDeploymentReport(
        data.enterpriseDeploymentReport
    );
    if (enterpriseDeploymentReport) {
        context.enterpriseDeploymentReport = enterpriseDeploymentReport;
    }

    const deploymentDiagnostics = slimDeploymentDiagnostics(
        data.deploymentDiagnostics
    );
    if (deploymentDiagnostics) {
        context.deploymentDiagnostics = deploymentDiagnostics;
    }

    const deploymentSummary = slimDeploymentSummary(
        resolveDeploymentSummary(data)
    );
    if (deploymentSummary) {
        context.deploymentSummary = deploymentSummary;
    }

    const aiResolutionFactPack = slimAiResolutionFactPack(
        data.aiResolutionFactPack
    );
    if (aiResolutionFactPack) {
        context.aiResolutionFactPack = aiResolutionFactPack;
    }

    if (
        !context.failureClassification &&
        !context.enterpriseDeploymentReport
    ) {
        return null;
    }

    return context;
}

/**
 * Measure serialized request size without logging secrets.
 *
 * @param {string} provider
 * @param {object} context
 * @returns {{ payloadBytes: number, contextBytes: number, factPackComponentCount: number, failureCount: number }}
 */
export function measureAiResolutionRequestSize(provider, context) {
    const safeContext = isPlainObject(context) ? context : {};
    const payload = {
        provider: provider || 'gemini',
        context: safeContext
    };
    const payloadJson = JSON.stringify(payload);
    const contextJson = JSON.stringify(safeContext);
    const components = Array.isArray(safeContext.aiResolutionFactPack?.components)
        ? safeContext.aiResolutionFactPack.components
        : [];
    const failures = Array.isArray(
        safeContext.failureClassification?.failures
    )
        ? safeContext.failureClassification.failures
        : [];

    return {
        payloadBytes: new TextEncoder().encode(payloadJson).length,
        contextBytes: new TextEncoder().encode(contextJson).length,
        factPackComponentCount: components.length,
        failureCount: failures.length
    };
}

export const AI_RESOLUTION_TRANSPORT_KEYS = TRANSPORT_KEYS;