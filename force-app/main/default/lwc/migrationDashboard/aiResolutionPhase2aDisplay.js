/**
 * Phase 2A — AI Resolution display mapping (presentation only).
 * Reads backend-authoritative explanation fields. Does not infer ownership,
 * auto-fixability, SAFE_SKIP, or remediation steps.
 */

const FIX_OWNER_LABELS = Object.freeze({
    RUNTIME_AUTOFIX: 'Backend / Automatic Fix',
    MANUAL_METADATA: 'Source Metadata / Manual Fix',
    DESTINATION_FEATURE: 'Destination Org / Configuration',
    UNKNOWN: 'Manual Investigation'
});

function isPlainObject(value) {
    return value != null && typeof value === 'object' && !Array.isArray(value);
}

/**
 * Map backend fixOwner enum to human-readable label.
 * Missing / unrecognized values display as Manual Investigation.
 *
 * @param {string|null|undefined} fixOwner
 * @returns {string}
 */
export function mapFixOwnerLabel(fixOwner) {
    if (typeof fixOwner !== 'string' || !fixOwner.trim()) {
        return FIX_OWNER_LABELS.UNKNOWN;
    }
    const key = fixOwner.trim().toUpperCase();
    return FIX_OWNER_LABELS[key] || FIX_OWNER_LABELS.UNKNOWN;
}

/**
 * Display helper for nullable backend facts.
 * null / undefined / UNKNOWN confidence → "Unknown" (not invented meaning).
 *
 * @param {*} value
 * @returns {string}
 */
export function formatFactValue(value) {
    if (value === null || value === undefined) {
        return 'Unknown';
    }
    if (typeof value === 'boolean') {
        return value ? 'Yes' : 'No';
    }
    const text = String(value).trim();
    if (!text || text.toUpperCase() === 'UNKNOWN') {
        return 'Unknown';
    }
    return text;
}

/**
 * @param {object|null|undefined} side
 * @returns {{ show: boolean, typeLabel: string, calculatedLabel: string, existsLabel: string, labelText: string|null, confidenceLabel: string }}
 */
export function mapFieldSideDisplay(side) {
    if (!isPlainObject(side)) {
        return {
            show: false,
            typeLabel: 'Unknown',
            calculatedLabel: 'Unknown',
            existsLabel: 'Unknown',
            labelText: null,
            confidenceLabel: 'Unknown'
        };
    }

    const labelText =
        typeof side.label === 'string' && side.label.trim()
            ? side.label.trim()
            : null;

    return {
        show: true,
        typeLabel: formatFactValue(side.type),
        calculatedLabel: formatFactValue(side.calculated),
        existsLabel: formatFactValue(side.exists),
        labelText,
        confidenceLabel: formatFactValue(side.confidence)
    };
}

/**
 * @param {object|null|undefined} conflict
 * @returns {{ show: boolean, typeLabel: string|null, description: string|null, confidenceLabel: string|null, cliProblem: string|null }}
 */
export function mapConflictDisplay(conflict) {
    if (!isPlainObject(conflict)) {
        return {
            show: false,
            typeLabel: null,
            description: null,
            confidenceLabel: null,
            cliProblem: null
        };
    }

    const typeLabel =
        conflict.type != null && String(conflict.type).trim()
            ? String(conflict.type).trim()
            : null;
    const description =
        typeof conflict.description === 'string' && conflict.description.trim()
            ? conflict.description.trim()
            : null;
    const confidenceLabel =
        conflict.confidence != null
            ? formatFactValue(conflict.confidence)
            : null;
    const cliProblem =
        typeof conflict.cliProblem === 'string' && conflict.cliProblem.trim()
            ? conflict.cliProblem.trim()
            : null;

    const show = !!(typeLabel || description || confidenceLabel || cliProblem);

    return {
        show,
        typeLabel,
        description,
        confidenceLabel,
        cliProblem
    };
}

/**
 * @param {object|null|undefined} resolution
 * @returns {{ show: boolean, action: string|null, reason: string|null, steps: Array<{ id: string, text: string }> }}
 */
export function mapResolutionStepsDisplay(resolution, rowId = 'row') {
    if (!isPlainObject(resolution)) {
        return {
            show: false,
            action: null,
            reason: null,
            steps: []
        };
    }

    const action =
        typeof resolution.action === 'string' && resolution.action.trim()
            ? resolution.action.trim()
            : null;
    const reason =
        typeof resolution.reason === 'string' && resolution.reason.trim()
            ? resolution.reason.trim()
            : null;

    const steps = Array.isArray(resolution.steps)
        ? resolution.steps
              .map((step, index) => {
                  if (typeof step === 'string' && step.trim()) {
                      return {
                          id: `${rowId}-step-${index}`,
                          text: step.trim()
                      };
                  }
                  if (isPlainObject(step) && typeof step.text === 'string') {
                      const text = step.text.trim();
                      return text
                          ? { id: `${rowId}-step-${index}`, text }
                          : null;
                  }
                  return null;
              })
              .filter(Boolean)
        : [];

    return {
        show: steps.length > 0 || !!action || !!reason,
        action,
        reason,
        steps,
        hasSteps: steps.length > 0
    };
}

/**
 * Map one backend explanation into Phase 2A presentation fields.
 * Does not invent backend facts.
 *
 * @param {object} item
 * @param {string} rowId
 * @returns {object}
 */
export function mapPhase2aExplanationDisplay(item, rowId = 'ondemand-ai') {
    const source = isPlainObject(item) ? item : {};
    const fixOwnerRaw =
        typeof source.fixOwner === 'string' ? source.fixOwner : null;
    const backendResolution =
        typeof source.backendResolution === 'string' &&
        source.backendResolution.trim()
            ? source.backendResolution.trim()
            : null;

    const sourceFacts = mapFieldSideDisplay(source.source);
    const destinationFacts = mapFieldSideDisplay(source.destination);
    const conflictDisplay = mapConflictDisplay(source.conflict);
    const resolutionDisplay = mapResolutionStepsDisplay(
        source.resolution,
        rowId
    );

    const backendCanAutoFix = source.backendCanAutoFix;
    const backendCanAutoFixStatus =
        backendCanAutoFix === true
            ? 'Backend can automatically fix this'
            : backendCanAutoFix === false
              ? 'Backend cannot automatically fix this'
              : null;

    const showUserActionRequired = source.userActionRequired === true;

    // Existing skip indication only when backend provided boolean (null → hide).
    const showAiSafeToSkip = source.safeToSkip === true || source.safeToSkip === false;
    const aiSafeToSkipLabel =
        source.safeToSkip === true
            ? 'Yes (advisory)'
            : source.safeToSkip === false
              ? 'No (advisory)'
              : null;

    return {
        fixOwnerRaw,
        fixOwnerLabel: mapFixOwnerLabel(fixOwnerRaw),
        showBackendResolution: !!backendResolution,
        backendResolution,
        sourceFacts,
        destinationFacts,
        conflictDisplay,
        resolutionDisplay,
        showBackendCanAutoFixStatus: !!backendCanAutoFixStatus,
        backendCanAutoFixStatus,
        showUserActionRequired,
        userActionRequiredBanner: showUserActionRequired
            ? 'User action required'
            : null,
        showAiSafeToSkip,
        aiSafeToSkipLabel
    };
}

export const PHASE2A_FIX_OWNER_LABELS = FIX_OWNER_LABELS;