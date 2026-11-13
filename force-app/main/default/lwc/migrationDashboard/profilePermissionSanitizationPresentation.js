/**
 * Presentation for backend profilePermissionSanitization (Profile-only path only).
 * Backend is authoritative — no client-side permission logic.
 */

import { PROFILE_ONLY_MINIMAL_VALIDATION_EXECUTION_PATH } from './profileOnlyBoundDeployPresentation';

/** Matches backend MAX_PROFILE_ONLY_CHECK_ONLY_ATTEMPTS. */
export const PROFILE_ONLY_MAX_CHECK_ONLY_ATTEMPTS = 5;

export const DISABLED_PERMISSION_DEPENDENCY_FOOTNOTE =
    'This permission was disabled because the destination org requires dependent permissions that were unavailable in the source Profile. You may need to re-enable it manually after deployment if the destination supports those dependencies.';

function isPlainObject(value) {
    return value != null && typeof value === 'object' && !Array.isArray(value);
}

function safeNonNegativeCount(value, fallbackArray) {
    if (typeof value === 'number' && Number.isFinite(value) && value >= 0) {
        return value;
    }

    if (Array.isArray(fallbackArray)) {
        return fallbackArray.length;
    }

    return 0;
}

function resolveSanitizationAppliedCounts(raw) {
    const removedCount = safeNonNegativeCount(
        raw.removedCount,
        raw.removedPermissions
    );
    const disabledCount = safeNonNegativeCount(
        raw.disabledCount,
        raw.disabledPermissions
    );

    return {
        removedCount,
        disabledCount,
        appliedTotal: removedCount + disabledCount
    };
}

function resolveCheckOnlySucceeded(data) {
    const checkOnly = data?.checkOnlyDeployment;

    if (!isPlainObject(checkOnly)) {
        return false;
    }

    if (
        checkOnly.executed === false ||
        checkOnly.skipped === true ||
        checkOnly.notExecuted === true
    ) {
        return false;
    }

    return checkOnly.success === true;
}

function buildPermissionChangeRows(raw) {
    const rows = [];

    for (const entry of raw.removedPermissions || []) {
        if (!entry || typeof entry !== 'object') {
            continue;
        }

        if (entry.originalEnabled !== true) {
            continue;
        }

        const profileName = entry.profileName || entry.profile || null;
        const permissionName =
            entry.permissionName || entry.permission || null;

        if (!profileName || !permissionName) {
            continue;
        }

        rows.push({
            id: `removed:${profileName}:${permissionName}`,
            profileName: String(profileName),
            permissionName: String(permissionName),
            action: 'Removed',
            originalValue: 'true',
            finalValue: 'Removed',
            reason:
                entry.reason ||
                entry.sourceFailure?.problem ||
                'Removed during Profile-only check-only validation.'
        });
    }

    for (const entry of raw.disabledPermissions || []) {
        if (!entry || typeof entry !== 'object') {
            continue;
        }

        if (entry.originalEnabled !== true || entry.finalEnabled !== false) {
            continue;
        }

        const profileName = entry.profileName || entry.profile || null;
        const permissionName =
            entry.permissionName || entry.permission || null;

        if (!profileName || !permissionName) {
            continue;
        }

        const dependencyPermissionNames = Array.isArray(
            entry.dependencyPermissionNames
        )
            ? entry.dependencyPermissionNames
                  .filter((name) => name != null && String(name).trim())
                  .map((name) => String(name).trim())
            : [];

        const dependencyList = dependencyPermissionNames.join(', ');

        rows.push({
            id: `disabled:${profileName}:${permissionName}`,
            profileName: String(profileName),
            permissionName: String(permissionName),
            action: 'Disabled',
            originalValue: 'true',
            finalValue: 'false',
            reason: entry.reason || '—',
            dependencyPermissionNames: dependencyList,
            showDependencyFootnote: dependencyPermissionNames.length > 0
        });
    }

    return rows;
}

function buildAppliedSummaryMessage(removedCount, disabledCount) {
    const parts = [];

    if (removedCount > 0) {
        parts.push(
            `${removedCount} user permission${
                removedCount === 1 ? '' : 's'
            } removed`
        );
    }

    if (disabledCount > 0) {
        parts.push(
            `${disabledCount} user permission${
                disabledCount === 1 ? '' : 's'
            } disabled`
        );
    }

    if (!parts.length) {
        return null;
    }

    return `${parts.join(' and ')} to complete check-only validation.`;
}

/**
 * @param {object} validationData deploymentValidationData
 * @param {object} options
 * @param {boolean} options.profileOnlyModeActive current checkbox state
 */
export function buildProfilePermissionSanitizationDisplay(
    validationData,
    options = {}
) {
    if (options.profileOnlyModeActive !== true) {
        return null;
    }

    if (!validationData || typeof validationData !== 'object') {
        return null;
    }

    if (
        validationData.validationExecutionPath !==
        PROFILE_ONLY_MINIMAL_VALIDATION_EXECUTION_PATH
    ) {
        return null;
    }

    const raw = validationData.profilePermissionSanitization;

    if (!isPlainObject(raw)) {
        return null;
    }

    const status = typeof raw.status === 'string' ? raw.status : null;
    const overallStatus =
        typeof raw.overallStatus === 'string' ? raw.overallStatus : null;
    const { removedCount, disabledCount, appliedTotal } =
        resolveSanitizationAppliedCounts(raw);
    const checkOnlyAttempts =
        typeof raw.checkOnlyAttempts === 'number' && raw.checkOnlyAttempts > 0
            ? raw.checkOnlyAttempts
            : null;
    const errors = Array.isArray(raw.errors)
        ? raw.errors.filter((e) => e != null && String(e).trim())
        : [];
    const checkOnlySucceeded = resolveCheckOnlySucceeded(validationData);

    const attemptLabel =
        checkOnlyAttempts != null
            ? `Check-only attempt: ${checkOnlyAttempts} of ${PROFILE_ONLY_MAX_CHECK_ONLY_ATTEMPTS}`
            : null;

    const sanitizationStatusLabel = status || '—';

    if (overallStatus === 'BLOCKED' || status === 'BLOCKED') {
        return {
            visible: true,
            variant: 'error',
            title: 'Profile Permission Compatibility',
            sanitizationStatusLabel,
            attemptLabel,
            summaryMessage:
                errors[0] ||
                'Profile user permission sanitization blocked validation.',
            showPermissionTable: false,
            permissionRows: [],
            removedTotal: removedCount,
            disabledTotal: disabledCount,
            showInfoOnly: false,
            showErrors: errors.length > 0,
            showDisabledDependencyFootnote: false,
            errors: errors.map((message, index) => ({
                id: `sanitization-error-${index}`,
                message: String(message)
            }))
        };
    }

    if (status === 'COMPLETED' && appliedTotal > 0) {
        const permissionRows = buildPermissionChangeRows(raw);
        const summaryMessage = buildAppliedSummaryMessage(
            removedCount,
            disabledCount
        );

        return {
            visible: true,
            variant: 'warning',
            title: 'Profile Permission Compatibility',
            sanitizationStatusLabel,
            attemptLabel,
            summaryMessage:
                summaryMessage ||
                'Profile user permissions were adjusted to complete check-only validation.',
            showPermissionTable: permissionRows.length > 0,
            permissionRows,
            removedTotal: removedCount,
            disabledTotal: disabledCount,
            showInfoOnly: false,
            showErrors: false,
            showDisabledDependencyFootnote: permissionRows.some(
                (row) => row.showDependencyFootnote
            ),
            errors: []
        };
    }

    if (
        status === 'SKIPPED' &&
        appliedTotal === 0 &&
        checkOnlySucceeded
    ) {
        return {
            visible: true,
            variant: 'success',
            title: 'Profile Permission Compatibility',
            sanitizationStatusLabel,
            attemptLabel,
            summaryMessage:
                'All selected Profile user permissions are supported by the destination org.',
            showPermissionTable: false,
            permissionRows: [],
            removedTotal: 0,
            disabledTotal: 0,
            showInfoOnly: true,
            showErrors: false,
            showDisabledDependencyFootnote: false,
            errors: []
        };
    }

    if (status === 'NOT_EXECUTED' || status === 'SKIPPED') {
        return {
            visible: true,
            variant: 'neutral',
            title: 'Profile Permission Compatibility',
            sanitizationStatusLabel,
            attemptLabel,
            summaryMessage:
                status === 'NOT_EXECUTED'
                    ? 'Permission sanitization was not executed for this validation run.'
                    : checkOnlySucceeded
                      ? 'No unsupported user permissions required removal or disabling.'
                      : 'Sanitization did not complete with a successful check-only result.',
            showPermissionTable: false,
            permissionRows: [],
            removedTotal: removedCount,
            disabledTotal: disabledCount,
            showInfoOnly: true,
            showErrors: false,
            showDisabledDependencyFootnote: false,
            errors: []
        };
    }

    return null;
}