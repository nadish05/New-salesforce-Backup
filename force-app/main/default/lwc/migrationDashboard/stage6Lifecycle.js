/**
 * Stage 6 lifecycle rail derivation (Deployment Execution).
 * Pure helpers — mirrors migrationDashboard getters for focused tests.
 */

export function resolveStage6Complete(deployCompleted, rollbackCompleted) {
    return deployCompleted === true && rollbackCompleted === true;
}

export function resolveStage6Active({
    isCheckOnlyValidationSuccessful,
    activeLifecycleStage,
    stage6Complete
}) {
    if (stage6Complete === true) {
        return false;
    }

    return (
        isCheckOnlyValidationSuccessful === true || activeLifecycleStage === 6
    );
}

export function resolveStage6StatusLabel(stage6Active, stage6Complete) {
    if (stage6Complete === true) {
        return 'Complete';
    }
    if (stage6Active === true) {
        return 'Ready';
    }
    return 'Pending';
}

/**
 * Normalizes timestamps from Apex (GMT Z strings, +0000 offsets) and plan
 * hydration (Datetime serialized to ISO) for lifecycle comparisons.
 *
 * @returns {number|null} UTC epoch milliseconds, or null when unusable
 */
export function parseLifecycleTimestamp(value) {
    if (value == null || value === '') {
        return null;
    }

    if (value instanceof Date) {
        const ms = value.getTime();
        return Number.isNaN(ms) ? null : ms;
    }

    if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
    }

    if (typeof value !== 'string') {
        return null;
    }

    let ms = Date.parse(value);
    if (!Number.isNaN(ms)) {
        return ms;
    }

    const normalized = value
        .replace(/(\.\d{3})\+0000$/, '$1Z')
        .replace(/\+0000$/, 'Z');
    ms = Date.parse(normalized);
    return Number.isNaN(ms) ? null : ms;
}

/**
 * Completed rollback hydration applies when the latest deployment validation
 * is not newer than the last successful deploy (rollbackDeploymentDateTime).
 * Re-validation after that deploy starts a new execution cycle without
 * erasing Rollback_Operation__c / Deployment_History__c records.
 *
 * Conservative fallback: when either timestamp is missing or unparsable,
 * apply completed rollback UI (do not assume a new cycle).
 */
export function shouldApplyCompletedRollbackHydration({
    validationCompletedAt,
    deploymentCompletedAt
}) {
    const validationMs = parseLifecycleTimestamp(validationCompletedAt);
    const deploymentMs = parseLifecycleTimestamp(deploymentCompletedAt);

    if (validationMs == null || deploymentMs == null) {
        return true;
    }

    return validationMs <= deploymentMs;
}

export function shouldShowRollbackCompletedSummary(
    deployCompleted,
    rollbackCompleted
) {
    return deployCompleted === true && rollbackCompleted === true;
}