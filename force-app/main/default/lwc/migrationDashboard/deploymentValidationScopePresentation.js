/**
 * Presentation helpers for deployment validation scope / shape Formula exclusion UI.
 * Reads backend fields defensively; never fabricates missing counts.
 */

export function applyValidationRequestOptions(deploymentPackage, options = {}) {
    const pkg = { ...(deploymentPackage || {}) };
    pkg.autoExcludeShapeFormulaConflicts =
        options.autoExcludeShapeFormulaConflicts === true;
    return pkg;
}

export function buildDeploymentValidationScopeDisplay(data) {
    if (!data || typeof data !== 'object') {
        return null;
    }

    const scope = isPlainObject(data.deploymentValidationScope)
        ? data.deploymentValidationScope
        : null;
    const policy = isPlainObject(data.shapeFormulaExclusionPolicy)
        ? data.shapeFormulaExclusionPolicy
        : isPlainObject(scope?.shapeFormulaExclusionPolicy)
          ? scope.shapeFormulaExclusionPolicy
          : null;

    const checkOnly = resolveCheckOnlyState(data);
    const readyForDeployment = resolveReadyForDeploymentFlag(data);

    const metrics = buildScopeMetrics(scope, data);
    const suppressedRows = mapComponentRows(
        pickArray(
            scope?.suppressedShapeExclusions,
            policy?.suppressedShapeExclusions,
            data.suppressedShapeExclusions
        ),
        'suppressed'
    );
    const revertedRows = mapComponentRows(
        pickArray(
            scope?.revertedShapeExclusions,
            scope?.shapeExclusionsReverted,
            policy?.revertedShapeExclusions,
            data.revertedShapeExclusions
        ),
        'reverted'
    );
    const finalExcludedRows = mapComponentRows(
        pickArray(data.excludedComponents, scope?.finalExcludedComponents),
        'excluded'
    );
    const blockingRows = mapBlockingRows(
        pickArray(data.blockingComponents, scope?.blockingComponents)
    );
    const warningRows = mapWarningRows(
        pickArray(data.compatibilityWarnings, scope?.compatibilityWarnings)
    );

    const unresolvedRemain = readBoolean(
        scope?.unresolvedShapeFormulaConflictsRemain,
        scope?.unresolvedFormulaConflictsRemain
    );
    const revertedDueToBlockers = readBoolean(
        scope?.shapeExclusionsRevertedDueToDependencyBlockers,
        scope?.shapeExclusionsReverted
    );
    const validatedReducedPackage = readBoolean(scope?.validatedReducedPackage);
    const allSelectedValidated = readBoolean(
        scope?.allSelectedComponentsValidated
    );

    const scenario = resolveScenario({
        scopeAvailable: scope != null,
        checkOnly,
        validatedReducedPackage,
        revertedDueToBlockers,
        unresolvedRemain,
        shapeExclusionCount: metrics.shapeFormulaExclusionCount.value,
        readyForDeployment
    });

    const messages = buildScenarioMessages(scenario, {
        checkOnly,
        validatedReducedPackage,
        revertedDueToBlockers,
        unresolvedRemain,
        allSelectedValidated,
        readyForDeployment
    });

    const residualRiskNote =
        readString(scope?.residualDependencyDiscoveryRiskNote) ||
        readString(policy?.residualDependencyDiscoveryRiskNote) ||
        readString(scope?.dependencyDiscoveryRiskNote) ||
        null;

    return {
        scenario,
        hasScopePayload: scope != null,
        hasPolicyPayload: policy != null,
        primaryTitle: messages.title,
        primaryMessage: messages.message,
        secondaryMessage: messages.secondary,
        hasSecondaryMessage: !!messages.secondary,
        preventsAllValidatedClaim:
            unresolvedRemain === true ||
            validatedReducedPackage === true ||
            checkOnly.executed !== true ||
            checkOnly.succeeded !== true,
        checkOnly,
        readyForDeployment,
        readyForDeploymentKnown: data.deploymentReadiness != null ||
            Object.prototype.hasOwnProperty.call(data, 'readyForDeployment'),
        metrics,
        policySummary: buildPolicySummary(policy),
        suppressedRows,
        hasSuppressedRows: suppressedRows.length > 0,
        revertedRows,
        hasRevertedRows: revertedRows.length > 0,
        finalExcludedRows,
        hasFinalExcludedRows: finalExcludedRows.length > 0,
        blockingRows,
        hasBlockingRows: blockingRows.length > 0,
        warningRows,
        hasWarningRows: warningRows.length > 0,
        residualRiskNote,
        hasResidualRiskNote: !!residualRiskNote
    };
}

function resolveScenario(ctx) {
    if (!ctx.scopeAvailable) {
        if (ctx.checkOnly.known === false) {
            return 'SCOPE_UNAVAILABLE';
        }
    }

    if (ctx.checkOnly.executed === false) {
        return 'CHECK_ONLY_NOT_EXECUTED';
    }

    if (ctx.checkOnly.executed === true && ctx.checkOnly.succeeded === false) {
        return 'CHECK_ONLY_FAILED';
    }

    if (ctx.unresolvedRemain === true) {
        return 'UNRESOLVED_FORMULA_CONFLICTS';
    }

    if (ctx.revertedDueToBlockers === true) {
        return 'SHAPE_EXCLUSIONS_REVERTED';
    }

    if (
        ctx.validatedReducedPackage === true ||
        (ctx.shapeExclusionCount != null && ctx.shapeExclusionCount > 0)
    ) {
        return 'CHECK_ONLY_SUCCEEDED_REDUCED';
    }

    if (ctx.checkOnly.succeeded === true) {
        return 'CHECK_ONLY_SUCCEEDED_FULL';
    }

    return 'SCOPE_UNAVAILABLE';
}

function buildScenarioMessages(scenario, ctx) {
    switch (scenario) {
        case 'CHECK_ONLY_SUCCEEDED_FULL':
            return {
                title: 'Check-only validation succeeded',
                message:
                    'All selected components were validated with no shape Formula exclusions applied.',
                secondary: null
            };
        case 'CHECK_ONLY_SUCCEEDED_REDUCED':
            return {
                title: 'Check-only succeeded on a reduced package',
                message:
                    'Eligible CustomField conflicts with destination Formula fields were excluded before validation.',
                secondary:
                    'Excluded fields were not validated or deployed as part of the reduced package.'
            };
        case 'SHAPE_EXCLUSIONS_REVERTED':
            return {
                title: 'Shape exclusions were reverted',
                message:
                    'Proposed shape Formula exclusions were not kept because dependency blockers were found.',
                secondary:
                    'Review reverted exclusions and blocking components before deploying.'
            };
        case 'UNRESOLVED_FORMULA_CONFLICTS':
            return {
                title: 'Unresolved Formula conflicts remain',
                message:
                    'The final package still contains shape or Formula conflicts that were not fully resolved.',
                secondary:
                    'Do not assume every selected component was validated successfully.'
            };
        case 'CHECK_ONLY_FAILED':
            return {
                title: 'Check-only validation failed',
                message:
                    'The destination check-only deployment did not complete successfully.',
                secondary: null
            };
        case 'CHECK_ONLY_NOT_EXECUTED':
            return {
                title: 'Check-only validation was not executed',
                message:
                    'Validation stopped or was blocked before a check-only deployment could run.',
                secondary: null
            };
        default:
            return {
                title: 'Validation scope details unavailable',
                message:
                    'The backend did not return a full deploymentValidationScope payload for this run.',
                secondary:
                    'Counts below are shown only when explicitly reported — missing values are not treated as zero.'
            };
    }
}

function buildScopeMetrics(scope, data) {
    const readiness = isPlainObject(data.deploymentReadiness)
        ? data.deploymentReadiness
        : {};

    return {
        originalSelectedComponentCount: metricFrom(
            scope?.originalSelectedComponentCount,
            scope?.selectedComponentCount
        ),
        packageMemberCountBeforeFilter: metricFrom(
            scope?.packageMemberCountBeforeFilter,
            scope?.packageMembersBeforeFilter
        ),
        packageMemberCountAfterFilter: metricFrom(
            scope?.packageMemberCountAfterFilter,
            scope?.packageMembersAfterFilter
        ),
        finalExcludedComponentCount: metricFrom(
            scope?.finalExcludedComponentCount,
            scope?.excludedComponentCount
        ),
        shapeFormulaExclusionCount: metricFrom(
            scope?.shapeFormulaExclusionCount,
            Array.isArray(scope?.shapeFormulaExclusions)
                ? scope.shapeFormulaExclusions.length
                : null
        ),
        validatedReducedPackage: booleanMetric(scope?.validatedReducedPackage),
        allSelectedComponentsValidated: booleanMetric(
            scope?.allSelectedComponentsValidated
        ),
        unresolvedShapeFormulaConflictsRemain: booleanMetric(
            scope?.unresolvedShapeFormulaConflictsRemain,
            scope?.unresolvedFormulaConflictsRemain
        ),
        shapeExclusionsRevertedDueToDependencyBlockers: booleanMetric(
            scope?.shapeExclusionsRevertedDueToDependencyBlockers,
            scope?.shapeExclusionsReverted
        ),
        readyForDeployment: booleanMetric(
            data.readyForDeployment,
            readiness.readyForDeployment
        )
    };
}

function buildPolicySummary(policy) {
    if (!policy) {
        return null;
    }

    const enabled = readBoolean(
        policy.autoExcludeShapeFormulaConflicts,
        policy.enabled
    );

    return {
        enabledKnown: enabled !== null,
        enabledLabel:
            enabled === null
                ? '—'
                : enabled
                  ? 'Enabled for this run'
                  : 'Disabled for this run',
        mode: readString(policy.mode) || readString(policy.policy) || null
    };
}

function resolveCheckOnlyState(data) {
    const checkOnly = data.checkOnlyDeployment;

    if (!isPlainObject(checkOnly)) {
        return {
            known: false,
            executed: false,
            succeeded: false,
            label: 'Not reported',
            detail: null
        };
    }

    if (
        checkOnly.executed === false ||
        checkOnly.skipped === true ||
        checkOnly.notExecuted === true
    ) {
        return {
            known: true,
            executed: false,
            succeeded: false,
            label: 'Not executed',
            detail: readString(checkOnly.message) || readString(checkOnly.reason)
        };
    }

    const succeeded = checkOnly.success === true;
    const failed = checkOnly.success === false;

    return {
        known: true,
        executed: true,
        succeeded,
        failed,
        label: succeeded ? 'Succeeded' : failed ? 'Failed' : 'Completed',
        detail: readString(checkOnly.message) || readString(checkOnly.error)
    };
}

function resolveReadyForDeploymentFlag(data) {
    if (Object.prototype.hasOwnProperty.call(data, 'readyForDeployment')) {
        return data.readyForDeployment === true;
    }
    if (isPlainObject(data.deploymentReadiness)) {
        if (
            Object.prototype.hasOwnProperty.call(
                data.deploymentReadiness,
                'readyForDeployment'
            )
        ) {
            return data.deploymentReadiness.readyForDeployment === true;
        }
        return data.deploymentReadiness.canDeploy === true;
    }
    return false;
}

function mapComponentRows(items, prefix) {
    return (items || []).map((item, index) => {
        if (typeof item === 'string') {
            return {
                id: `${prefix}-${index}`,
                component: item,
                metadataType: '—',
                reason: '—',
                dependents: '—'
            };
        }

        if (!isPlainObject(item)) {
            return null;
        }

        const dependents = formatDependents(item.dependentComponents || item.dependents);

        return {
            id: `${prefix}-${index}`,
            component: item.metadataName || item.name || item.fullName || '—',
            metadataType: item.metadataType || item.type || '—',
            reason: item.reason || item.message || item.category || '—',
            dependents
        };
    }).filter(Boolean);
}

function mapBlockingRows(items) {
    return (items || []).map((item, index) => {
        if (!isPlainObject(item)) {
            return null;
        }

        const blockedByList = Array.isArray(item.blockedBy) ? item.blockedBy : [];
        const blockedByLabel = blockedByList
            .map((dep) => dep.metadataName || dep.name || '')
            .filter(Boolean)
            .join(', ');

        return {
            id: `blocking-${index}`,
            component: item.metadataName || item.name || '—',
            blockedBy: blockedByLabel || '—',
            reason:
                blockedByList[0]?.reason ||
                blockedByList[0]?.message ||
                item.reason ||
                '—'
        };
    }).filter(Boolean);
}

function mapWarningRows(items) {
    return (items || []).map((item, index) => {
        if (typeof item === 'string') {
            return { id: `warning-${index}`, text: item };
        }
        if (!isPlainObject(item)) {
            return null;
        }
        return {
            id: `warning-${index}`,
            text:
                item.message ||
                item.reason ||
                [item.metadataType, item.metadataName, item.category]
                    .filter(Boolean)
                    .join(' — ') ||
                'Compatibility warning'
        };
    }).filter(Boolean);
}

function formatDependents(dependents) {
    if (!Array.isArray(dependents) || !dependents.length) {
        return '—';
    }

    return dependents
        .map((dep) => {
            if (typeof dep === 'string') {
                return dep;
            }
            if (!isPlainObject(dep)) {
                return '';
            }
            return [dep.metadataType, dep.metadataName || dep.name]
                .filter(Boolean)
                .join(':');
        })
        .filter(Boolean)
        .join('; ') || '—';
}

function metricFrom(...candidates) {
    for (const candidate of candidates) {
        const value = optionalCount(candidate);
        if (value !== null) {
            return { value, display: String(value), reported: true };
        }
    }
    return { value: null, display: '—', reported: false };
}

function booleanMetric(...candidates) {
    for (const candidate of candidates) {
        const value = readBoolean(candidate);
        if (value !== null) {
            return {
                value,
                display: value ? 'Yes' : 'No',
                reported: true
            };
        }
    }
    return { value: null, display: '—', reported: false };
}

function optionalCount(value) {
    if (value === null || value === undefined || value === '') {
        return null;
    }
    if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
    }
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
}

function readBoolean(...candidates) {
    for (const candidate of candidates) {
        if (candidate === true || candidate === false) {
            return candidate;
        }
    }
    return null;
}

function readString(value) {
    if (value == null) {
        return null;
    }
    const text = String(value).trim();
    return text || null;
}

function pickArray(...candidates) {
    for (const candidate of candidates) {
        if (Array.isArray(candidate)) {
            return candidate;
        }
    }
    return [];
}

function isPlainObject(value) {
    return value != null && typeof value === 'object' && !Array.isArray(value);
}