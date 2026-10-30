/**
 * Profile-only minimal package request helpers (client intent from comparison selection).
 */

export function evaluateProfileOnlyMinimalPackageEligibility(selectedMetadata) {
    if (!Array.isArray(selectedMetadata) || selectedMetadata.length === 0) {
        return { eligible: false, reason: 'empty_selection' };
    }

    const keys = new Set();

    for (const item of selectedMetadata) {
        if (!item || typeof item !== 'object') {
            return { eligible: false, reason: 'invalid_selection_item' };
        }

        const metadataType = item.metadataType || item.type || null;
        const metadataName = item.metadataName || item.name || null;

        if (metadataType !== 'Profile') {
            return { eligible: false, reason: 'mixed_or_non_profile_selection' };
        }

        if (typeof metadataName !== 'string' || !metadataName.trim()) {
            return { eligible: false, reason: 'profile_missing_name' };
        }

        const key = `Profile:${metadataName.trim()}`;

        if (keys.has(key)) {
            return { eligible: false, reason: 'duplicate_profile_selection' };
        }

        keys.add(key);
    }

    return { eligible: true, reason: null };
}

/**
 * When the user had enabled Profile-only mode but explicit selection is now
 * empty or ineligible, the checkbox must be cleared (not only gated at build time).
 */
export function shouldResetProfileOnlyMinimalPackageEnabled(
    currentlyEnabled,
    explicitPrimaryCandidates
) {
    if (currentlyEnabled !== true) {
        return false;
    }

    const eligibility = evaluateProfileOnlyMinimalPackageEligibility(
        explicitPrimaryCandidates
    );

    return !eligibility.eligible;
}

/**
 * Resolve whether profile-only fields belong on a deployment package request.
 */
export function resolveProfileOnlyMinimalPackageForRequest({
    userEnabled = false,
    explicitPrimaryCandidates = [],
    includeProfileOnlyMinimalPackage = true
} = {}) {
    if (includeProfileOnlyMinimalPackage === false) {
        return {
            requested: false,
            eligible: false,
            explicitPrimary: []
        };
    }

    const eligibility = evaluateProfileOnlyMinimalPackageEligibility(
        explicitPrimaryCandidates
    );
    const requested = userEnabled === true && eligibility.eligible;

    return {
        requested,
        eligible: eligibility.eligible,
        explicitPrimary: requested
            ? buildExplicitPrimarySelectedMetadata(explicitPrimaryCandidates)
            : []
    };
}

/**
 * Minimal explicit primary rows for backend (Profile members only).
 */
export function buildExplicitPrimarySelectedMetadata(selectedMetadata) {
    const eligibility = evaluateProfileOnlyMinimalPackageEligibility(
        selectedMetadata
    );

    if (!eligibility.eligible) {
        return [];
    }

    return selectedMetadata.map((item) => ({
        metadataType: 'Profile',
        metadataName: String(item.metadataName || item.name).trim()
    }));
}

/**
 * Apply Profile-only minimal packaging flags without altering selectedMetadata / dependencies.
 * When disabled or ineligible, omits optional fields to preserve legacy requests.
 */
export function applyProfileOnlyMinimalPackageOptions(
    deploymentPackage,
    options = {}
) {
    const pkg = { ...(deploymentPackage || {}) };
    const eligible = options.eligible === true;
    const requested = options.profileOnlyMinimalPackage === true;

    if (!requested || !eligible) {
        return pkg;
    }

    const explicitPrimary = Array.isArray(options.explicitPrimarySelectedMetadata)
        ? options.explicitPrimarySelectedMetadata
        : [];

    if (!explicitPrimary.length) {
        return pkg;
    }

    pkg.profileOnlyMinimalPackage = true;
    pkg.explicitPrimarySelectedMetadata = explicitPrimary;
    return pkg;
}

const PROFILE_ONLY_BLOCKED_MESSAGES = Object.freeze({
    empty_selection:
        'Select at least one Profile in Stage 3 before running Profile-only validation.',
    mixed_or_non_profile_selection:
        'Profile-only validation requires that every item selected for deployment in Stage 3 is a Profile.',
    profile_missing_name:
        'Each selected Profile must have a valid name before Profile-only validation can run.',
    duplicate_profile_selection:
        'Remove duplicate Profile selections in Stage 3 before running Profile-only validation.',
    invalid_selection_item:
        'Profile-only validation could not read the Stage 3 selection. Refresh the comparison and try again.'
});

export function buildProfileOnlyValidationBlockedMessage(reason) {
    if (reason && PROFILE_ONLY_BLOCKED_MESSAGES[reason]) {
        return PROFILE_ONLY_BLOCKED_MESSAGES[reason];
    }

    return 'Profile-only validation cannot start with the current Stage 3 selection.';
}

/**
 * Isolated Stage 5 Profile-only validation package (explicit Profiles only).
 */
export function buildIsolatedProfileOnlyValidationPackage({
    repoUrl = null,
    sourceBranch = null,
    destinationBranch = null,
    explicitPrimaryCandidates = []
} = {}) {
    const eligibility = evaluateProfileOnlyMinimalPackageEligibility(
        explicitPrimaryCandidates
    );

    if (!eligibility.eligible) {
        return {
            ok: false,
            reason: eligibility.reason,
            package: null
        };
    }

    const explicitPrimary =
        buildExplicitPrimarySelectedMetadata(explicitPrimaryCandidates);
    const selectedMetadata = explicitPrimary.map((item) => ({ ...item }));

    return {
        ok: true,
        reason: null,
        package: {
            repoUrl,
            sourceBranch,
            destinationBranch,
            selectedMetadata,
            requiredDependencies: [],
            selectedTestClasses: [],
            deploymentSelections: [],
            profileOnlyMinimalPackage: true,
            explicitPrimarySelectedMetadata: explicitPrimary.map((item) => ({
                ...item
            })),
            autoExcludeShapeFormulaConflicts: false
        }
    };
}

/**
 * Resolve Stage 5 validation deployment package by checkbox mode.
 * Normal mode returns the caller-supplied legacy package unchanged.
 */
export function resolveStage5ValidationDeploymentPackage({
    profileOnlyMinimalPackageEnabled = false,
    normalDeploymentPackage = null,
    explicitPrimaryCandidates = [],
    repoUrl = null,
    sourceBranch = null,
    destinationBranch = null
} = {}) {
    if (profileOnlyMinimalPackageEnabled !== true) {
        return {
            mode: 'normal',
            deploymentPackage: normalDeploymentPackage
        };
    }

    const isolated = buildIsolatedProfileOnlyValidationPackage({
        repoUrl,
        sourceBranch,
        destinationBranch,
        explicitPrimaryCandidates
    });

    if (!isolated.ok) {
        return {
            mode: 'blocked',
            reason: isolated.reason,
            message: buildProfileOnlyValidationBlockedMessage(isolated.reason)
        };
    }

    return {
        mode: 'profileOnly',
        deploymentPackage: isolated.package
    };
}

/**
 * Presentation for generated package / manifest size (do not conflate member types).
 */
export function buildGeneratedPackageSizeDisplay(validationData) {
    if (!validationData || typeof validationData !== 'object') {
        return null;
    }

    const packageSummary =
        validationData.generatedDeploymentPackage?.summary || null;
    const manifestSummary = validationData.generatedManifest?.summary || null;

    if (!packageSummary && !manifestSummary) {
        return null;
    }

    const formatCount = (value) =>
        value === null || value === undefined || value === ''
            ? '—'
            : String(value);

    return {
        hasPackageSummary: packageSummary != null,
        hasManifestSummary: manifestSummary != null,
        primaryPackageMembers: formatCount(packageSummary?.metadataCount),
        resolvedDependencies: formatCount(packageSummary?.dependencyCount),
        manifestMembers: formatCount(
            manifestSummary?.metadataCount ??
                manifestSummary?.totalComponents ??
                null
        ),
        note:
            'Primary package members are manifest-oriented selections; resolved dependencies support analysis and may not all appear as manifest members.'
    };
}