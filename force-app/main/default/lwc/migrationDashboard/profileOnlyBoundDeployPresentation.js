/**
 * Profile-only validation-bound deployment (client-side binding + outcome labels).
 * Backend contract: POST /api/deployment/deploy/bound
 */

export const BOUND_DEPLOY_CODES = Object.freeze({
    SUCCEEDED: 'BOUND_DEPLOY_SUCCEEDED',
    FAILED: 'BOUND_DEPLOY_FAILED',
    IN_PROGRESS: 'BOUND_DEPLOY_IN_PROGRESS',
    CONSUMED: 'BOUND_DEPLOY_CONSUMED',
    UNCERTAIN: 'BOUND_DEPLOY_UNCERTAIN'
});

/** Backend isolated Profile-only validation path (validate/start result). */
export const PROFILE_ONLY_MINIMAL_VALIDATION_EXECUTION_PATH =
    'PROFILE_ONLY_MINIMAL';

export function buildBoundDeployBindingContext({
    comparisonId = null,
    destinationOrgId = null,
    profileOnlyMinimalPackage = false,
    explicitPrimarySelectedMetadata = []
} = {}) {
    const explicit = Array.isArray(explicitPrimarySelectedMetadata)
        ? explicitPrimarySelectedMetadata
        : [];

    const explicitSelectionKey = explicit
        .map((item) => {
            const type = item?.metadataType || item?.type || '';
            const name = item?.metadataName || item?.name || '';
            return `${type}:${name}`;
        })
        .filter((key) => key !== ':')
        .sort()
        .join('|');

    return {
        comparisonId: comparisonId || null,
        destinationOrgId: destinationOrgId || null,
        profileOnlyMinimalPackage: profileOnlyMinimalPackage === true,
        explicitSelectionKey
    };
}

export function bindingContextMatches(stored, current) {
    if (!stored || !current) {
        return false;
    }

    return (
        stored.comparisonId === current.comparisonId &&
        stored.destinationOrgId === current.destinationOrgId &&
        stored.profileOnlyMinimalPackage === current.profileOnlyMinimalPackage &&
        stored.explicitSelectionKey === current.explicitSelectionKey
    );
}

export function canRetainBoundDeployBinding({
    profileOnlyMinimalPackage = false,
    checkOnlySuccess = false,
    boundDeployArtifact = null,
    asyncValidationId = null,
    validationExecutionPath = null,
    profileOnlyMinimalPackageBlocked = false
} = {}) {
    if (profileOnlyMinimalPackage !== true) {
        return false;
    }

    if (profileOnlyMinimalPackageBlocked === true) {
        return false;
    }

    if (
        validationExecutionPath !==
        PROFILE_ONLY_MINIMAL_VALIDATION_EXECUTION_PATH
    ) {
        return false;
    }

    if (checkOnlySuccess !== true) {
        return false;
    }

    if (
        !asyncValidationId ||
        typeof asyncValidationId !== 'string' ||
        !asyncValidationId.startsWith('validation_')
    ) {
        return false;
    }

    if (!boundDeployArtifact || typeof boundDeployArtifact !== 'object') {
        return false;
    }

    if (
        boundDeployArtifact.validationId &&
        boundDeployArtifact.validationId !== asyncValidationId
    ) {
        return false;
    }

    return true;
}

/**
 * Classify bound-deploy HTTP JSON for UI handling.
 * Does not invent backend fields.
 */
export function interpretBoundDeployResponse({
    parsed = null,
    httpStatusCode = null,
    transportError = null
} = {}) {
    if (transportError) {
        return {
            kind: 'TRANSPORT_UNCERTAIN',
            title: 'Deployment outcome unknown',
            message:
                'The bound deployment request did not complete reliably. Do not retry automatically. Investigate the destination org or re-run Stage 5 validation.',
            allowLegacyFallback: false,
            processAsDeploymentCompletion: false
        };
    }

    const boundDeploy = parsed?.boundDeploy;
    const code =
        boundDeploy && typeof boundDeploy === 'object'
            ? boundDeploy.code
            : null;
    const message =
        (boundDeploy && boundDeploy.message) ||
        parsed?.error ||
        null;

    if (code === BOUND_DEPLOY_CODES.IN_PROGRESS) {
        return {
            kind: 'BLOCKED_IN_PROGRESS',
            title: 'Deployment already in progress',
            message:
                message ||
                'A bound deployment for this validation is already in progress.',
            allowLegacyFallback: false,
            processAsDeploymentCompletion: false
        };
    }

    if (code === BOUND_DEPLOY_CODES.CONSUMED) {
        return {
            kind: 'BLOCKED_CONSUMED',
            title: 'Validation artifact already used',
            message:
                message ||
                'This validated package was already consumed. Re-run Stage 5 validation before deploying again.',
            allowLegacyFallback: false,
            processAsDeploymentCompletion: false
        };
    }

    if (code === BOUND_DEPLOY_CODES.UNCERTAIN) {
        return {
            kind: 'BLOCKED_UNCERTAIN',
            title: 'Deployment outcome uncertain',
            message:
                message ||
                'The bound deployment outcome is uncertain and must be investigated. Do not retry with the normal deploy path.',
            allowLegacyFallback: false,
            processAsDeploymentCompletion: false
        };
    }

    if (
        parsed?.success === true &&
        code === BOUND_DEPLOY_CODES.SUCCEEDED &&
        parsed?.deploymentExecution
    ) {
        return {
            kind: 'SUCCESS',
            title: 'Deployment completed',
            message: message || 'Bound deployment completed successfully.',
            allowLegacyFallback: false,
            processAsDeploymentCompletion: true
        };
    }

    if (
        code === BOUND_DEPLOY_CODES.FAILED ||
        (boundDeploy?.status === 'BLOCKED' && code === 'BOUND_DEPLOY_FAILED')
    ) {
        return {
            kind: 'DEPLOY_FAILED',
            title: 'Bound deployment failed',
            message:
                message ||
                parsed?.deploymentExecution?.message ||
                'Bound deployment failed.',
            allowLegacyFallback: false,
            processAsDeploymentCompletion: Boolean(parsed?.deploymentExecution)
        };
    }

    if (boundDeploy?.status === 'BLOCKED' && code) {
        return {
            kind: 'BLOCKED',
            title: 'Bound deployment blocked',
            message:
                message ||
                `Bound deployment could not proceed (${code}). Re-run Stage 5 validation if the validation reference expired.`,
            allowLegacyFallback: false,
            processAsDeploymentCompletion: false
        };
    }

    if (parsed?.success === false || (httpStatusCode && httpStatusCode >= 400)) {
        return {
            kind: 'ERROR',
            title: 'Bound deployment error',
            message:
                message ||
                'Bound deployment returned an error. Re-run Stage 5 validation before trying again.',
            allowLegacyFallback: false,
            processAsDeploymentCompletion: false
        };
    }

    return {
        kind: 'UNKNOWN',
        title: 'Unexpected bound deployment response',
        message:
            message ||
            'The bound deployment response could not be interpreted. Re-run Stage 5 validation.',
        allowLegacyFallback: false,
        processAsDeploymentCompletion: false
    };
}

export function shouldUseLegacyDeployPath({
    profileOnlyMinimalPackage = false,
    hasValidBoundBinding = false,
    boundDeployLegacyBlocked = false
} = {}) {
    if (profileOnlyMinimalPackage === true) {
        // Enforced in handleConfirmDeploy: bound path only; no legacy DEPLOY.
        return false;
    }

    // Checkbox off: stale bound-deploy block/binding must not block legacy deploy.
    return true;
}