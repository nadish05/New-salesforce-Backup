export const SOURCE_VALIDATION_CONTINUE_MESSAGE =
    'Source validation completed, but the Apex code coverage quality gate did not pass because coverage is below the required 85%. You can still continue to Deployment Planning by selecting the next stage above.';

/**
 * Source validation tests passed but the Apex coverage quality gate failed.
 */
export function isCoverageOnlySourceValidationFailure(
    sourceValidationData,
    overallSourceValidationStatus
) {
    if (!sourceValidationData || overallSourceValidationStatus !== 'FAIL') {
        return false;
    }

    const testStatus = sourceValidationData?.sourceValidation?.overallStatus;
    const coverageStatus = sourceValidationData?.coverageValidation?.overallStatus;

    return testStatus === 'PASS' && coverageStatus === 'FAIL';
}

export function shouldShowSourceValidationContinueHint({
    sourceValidationData,
    overallSourceValidationStatus,
    isLoadingSourceValidation,
    hasDisplayItems
}) {
    if (isLoadingSourceValidation || !hasDisplayItems) {
        return false;
    }

    return isCoverageOnlySourceValidationFailure(
        sourceValidationData,
        overallSourceValidationStatus
    );
}

export function isStage5ContinuableAfterCoverageFailure({
    isCoverageOnlyFailure,
    isRetrievalInProgress,
    stage5Complete,
    stage5Active
}) {
    return (
        isCoverageOnlyFailure &&
        !isRetrievalInProgress &&
        !stage5Complete &&
        !stage5Active
    );
}

export function resolveStage5Class({ stage5Active, stage5Complete, stage5Continuable }) {
    if (stage5Complete) {
        return 'lc-node lc-node--complete';
    }
    if (stage5Active) {
        return 'lc-node lc-node--active';
    }
    if (stage5Continuable) {
        return 'lc-node lc-node--continuable';
    }
    return 'lc-node lc-node--idle';
}

export function resolveStage5StatusLabel({ stage5Active, stage5Complete, stage5Continuable }) {
    if (stage5Complete) {
        return 'Complete';
    }
    if (stage5Active) {
        return 'Ready';
    }
    if (stage5Continuable) {
        return 'Continue';
    }
    return 'Pending';
}

export function resolveStage5StatusClass({ stage5Active, stage5Complete, stage5Continuable }) {
    if (stage5Complete) {
        return 'lc-node-status lc-status--complete';
    }
    if (stage5Active) {
        return 'lc-node-status lc-status--active';
    }
    if (stage5Continuable) {
        return 'lc-node-status lc-status--continuable';
    }
    return 'lc-node-status lc-status--idle';
}