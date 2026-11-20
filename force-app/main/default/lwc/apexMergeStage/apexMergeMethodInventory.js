export const METHOD_MERGE_MODE = 'METHOD';
export const FULL_MERGE_MODE = 'FULL';

export const METHOD_STATUS = {
    AUTO_INCLUDED: 'AUTO_INCLUDED',
    AUTO_EXCLUDED: 'AUTO_EXCLUDED',
    CONFLICT: 'CONFLICT',
    RESOLVED: 'RESOLVED'
};

export const METHOD_RESOLUTION_STRATEGY = {
    ACCEPT_SOURCE: 'ACCEPT_SOURCE',
    ACCEPT_TARGET: 'ACCEPT_TARGET'
};

export function formatResolutionLabel(strategy) {
    if (strategy === METHOD_RESOLUTION_STRATEGY.ACCEPT_SOURCE) {
        return 'Accepted Source';
    }
    if (strategy === METHOD_RESOLUTION_STRATEGY.ACCEPT_TARGET) {
        return 'Accepted Destination';
    }
    return strategy ? String(strategy) : '';
}

export function buildMethodResolutionEntry(methodKey, strategy) {
    return {
        methodKey: String(methodKey || '').trim(),
        strategy
    };
}

export function methodPreviewHasResolvedMethods(previewData) {
    if (!isMethodMergePreview(previewData)) {
        return false;
    }
    const methods = previewData?.methods;
    if (!Array.isArray(methods)) {
        return false;
    }
    return methods.some(
        (entry) => entry?.status === METHOD_STATUS.RESOLVED
    );
}

export function classHasUnresolvedMethodConflicts(previewData) {
    if (!isMethodMergePreview(previewData)) {
        return false;
    }
    if (typeof previewData.conflictCount === 'number') {
        return previewData.conflictCount > 0;
    }
    if (previewData.resolved === true) {
        return false;
    }
    return previewData.hasConflicts === true;
}

const METHOD_STATUS_LABELS = {
    [METHOD_STATUS.AUTO_INCLUDED]: 'Auto included',
    [METHOD_STATUS.AUTO_EXCLUDED]: 'Auto excluded',
    [METHOD_STATUS.CONFLICT]: 'Conflict',
    [METHOD_STATUS.RESOLVED]: 'Resolved'
};

const METHOD_STATUS_BADGE_CLASS = {
    [METHOD_STATUS.AUTO_INCLUDED]: 'slds-badge slds-theme_success',
    [METHOD_STATUS.AUTO_EXCLUDED]: 'slds-badge slds-theme_warning',
    [METHOD_STATUS.CONFLICT]: 'slds-badge slds-theme_error',
    [METHOD_STATUS.RESOLVED]: 'slds-badge slds-theme_success'
};

const IMPLEMENTATION_PLACEHOLDER = '(Not available)';

export function formatImplementationText(value) {
    if (value === null || value === undefined) {
        return IMPLEMENTATION_PLACEHOLDER;
    }
    const text = String(value);
    if (!text.trim()) {
        return '(Empty)';
    }
    return text;
}

export function resolveMethodDisplayName(methodKey) {
    if (!methodKey) {
        return '';
    }
    const match = String(methodKey).match(/^([^(]+)/);
    return match ? match[1].trim() : String(methodKey);
}

export function isMethodMergePreview(previewData) {
    return previewData?.mergeMode === METHOD_MERGE_MODE;
}

export function isFullMergePreview(previewData) {
    if (!previewData) {
        return false;
    }
    return previewData.mergeMode !== METHOD_MERGE_MODE;
}

export function buildMethodInventoryRows(methods) {
    if (!Array.isArray(methods)) {
        return [];
    }

    return methods.map((entry, index) => {
        const methodKey = entry?.methodKey || '';
        const status = entry?.status || '';
        const isConflict = status === METHOD_STATUS.CONFLICT;
        const isResolved = status === METHOD_STATUS.RESOLVED;
        const statusLabel =
            METHOD_STATUS_LABELS[status] || status || 'Unknown';
        const badgeClass =
            METHOD_STATUS_BADGE_CLASS[status] ||
            'slds-badge';
        const resolutionLabel = formatResolutionLabel(entry?.resolution);
        const showInclusionHint =
            entry?.included === false ||
            status === METHOD_STATUS.AUTO_EXCLUDED;

        let rowClass = 'method-inventory-row';
        if (isConflict) {
            rowClass += ' method-inventory-row_conflict';
        } else if (isResolved) {
            rowClass += ' method-inventory-row_resolved';
        }

        return {
            ...entry,
            _key: methodKey || `method-${index}`,
            methodName: resolveMethodDisplayName(methodKey),
            signature: methodKey,
            status,
            statusLabel,
            badgeClass,
            isConflict,
            isResolved,
            resolutionLabel,
            showResolutionChoice: Boolean(resolutionLabel),
            showResolveActions: isConflict,
            showInclusionHint,
            inclusionHint: showInclusionHint
                ? 'Excluded from merged class composition'
                : '',
            rowClass,
            showImplementations: isConflict,
            baseImplementationText: formatImplementationText(
                entry?.baseImplementation
            ),
            sourceImplementationText: formatImplementationText(
                entry?.sourceImplementation
            ),
            destinationImplementationText: formatImplementationText(
                entry?.destinationImplementation
            )
        };
    });
}