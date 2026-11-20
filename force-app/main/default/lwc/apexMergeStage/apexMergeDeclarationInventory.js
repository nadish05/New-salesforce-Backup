import {
    classHasUnresolvedMethodConflicts,
    isMethodMergePreview,
    methodPreviewHasResolvedMethods
} from './apexMergeMethodInventory';

export const DECLARATION_STATUS = {
    AUTO_RESOLVED: 'AUTO_RESOLVED',
    CONFLICT: 'CONFLICT',
    RESOLVED: 'RESOLVED'
};

export const DECLARATION_RESOLUTION_SIDE = {
    SOURCE: 'SOURCE',
    DESTINATION: 'DESTINATION'
};

const DECLARATION_STATUS_LABELS = {
    [DECLARATION_STATUS.AUTO_RESOLVED]: 'Automatic',
    [DECLARATION_STATUS.CONFLICT]: 'Conflict',
    [DECLARATION_STATUS.RESOLVED]: 'Resolved'
};

const DECLARATION_STATUS_BADGE_CLASS = {
    [DECLARATION_STATUS.AUTO_RESOLVED]: 'slds-badge slds-theme_success',
    [DECLARATION_STATUS.CONFLICT]: 'slds-badge slds-theme_error',
    [DECLARATION_STATUS.RESOLVED]: 'slds-badge slds-theme_success'
};

const ACCESS_LABELS = {
    public: 'Public',
    global: 'Global',
    unspecified: 'No explicit access modifier',
    protected: 'Protected',
    private: 'Private'
};

const SHARING_LABELS = {
    with: 'With Sharing',
    without: 'Without Sharing',
    inherited: 'Inherited Sharing',
    omitted: 'No explicit sharing declaration'
};

export function formatAccessLabel(value) {
    if (value === null || value === undefined || value === '') {
        return '—';
    }
    const key = String(value).toLowerCase();
    return ACCESS_LABELS[key] || String(value);
}

export function formatSharingLabel(value) {
    if (value === null || value === undefined || value === '') {
        return '—';
    }
    const key = String(value).toLowerCase();
    return SHARING_LABELS[key] || String(value);
}

export function formatDeclarationValueLabel(attribute, value) {
    if (attribute === 'sharing') {
        return formatSharingLabel(value);
    }
    return formatAccessLabel(value);
}

export function formatDeclarationResolutionLabel(side) {
    if (side === DECLARATION_RESOLUTION_SIDE.SOURCE) {
        return 'Accepted Source';
    }
    if (side === DECLARATION_RESOLUTION_SIDE.DESTINATION) {
        return 'Accepted Destination';
    }
    return side ? String(side) : '';
}

export function buildDeclarationResolutionEntry(conflictKey, side) {
    return {
        conflictKey: String(conflictKey || '').trim(),
        side
    };
}

export function classHasUnresolvedDeclarationConflicts(previewData) {
    if (!isMethodMergePreview(previewData)) {
        return false;
    }

    if (
        previewData.declarations == null &&
        previewData.declarationConflictCount == null &&
        previewData.declarationsResolved == null
    ) {
        return false;
    }

    if (typeof previewData.declarationConflictCount === 'number') {
        return previewData.declarationConflictCount > 0;
    }

    if (previewData.declarationsResolved === false) {
        return true;
    }

    return false;
}

export function classHasUnresolvedMethodOrDeclarationConflicts(previewData) {
    if (!isMethodMergePreview(previewData)) {
        return false;
    }

    return (
        classHasUnresolvedMethodConflicts(previewData) ||
        classHasUnresolvedDeclarationConflicts(previewData)
    );
}

export function methodMergePreviewFullyResolved(previewData) {
    if (!isMethodMergePreview(previewData)) {
        return false;
    }

    return (
        !classHasUnresolvedMethodConflicts(previewData) &&
        !classHasUnresolvedDeclarationConflicts(previewData)
    );
}

export function methodPreviewHasResolvedDeclarations(previewData) {
    if (!isMethodMergePreview(previewData)) {
        return false;
    }

    const declarations = previewData?.declarations;
    if (!declarations) {
        return false;
    }

    const entries = [declarations.access, declarations.sharing].filter(Boolean);

    return entries.some(
        (entry) => entry.status === DECLARATION_STATUS.RESOLVED
    );
}

export function previewRequiresRepreviewConfirmation(previewData) {
    return (
        methodPreviewHasResolvedMethods(previewData) ||
        methodPreviewHasResolvedDeclarations(previewData)
    );
}

function buildDeclarationRow(entry, attributeLabel) {
    if (!entry) {
        return null;
    }

    const status = entry.status || '';
    const isConflict = status === DECLARATION_STATUS.CONFLICT;
    const isResolved = status === DECLARATION_STATUS.RESOLVED;
    const isAutomatic = status === DECLARATION_STATUS.AUTO_RESOLVED;
    const attribute = entry.attribute || '';
    const valueLabelFn =
        attribute === 'sharing' ? formatSharingLabel : formatAccessLabel;

    let rowClass = 'method-inventory-row declaration-inventory-row';
    if (isConflict) {
        rowClass += ' method-inventory-row_conflict';
    } else if (isResolved || isAutomatic) {
        rowClass += ' method-inventory-row_resolved';
    }

    const selectedValueLabel =
        entry.selectedValue != null && entry.selectedValue !== ''
            ? valueLabelFn(entry.selectedValue)
            : '';

    const showSharingWarning =
        attribute === 'sharing' &&
        (String(entry.sourceValue) === 'without' ||
            String(entry.destinationValue) === 'without' ||
            String(entry.selectedValue) === 'without');

    return {
        ...entry,
        _key: entry.conflictKey || attribute,
        attributeLabel,
        status,
        statusLabel:
            DECLARATION_STATUS_LABELS[status] || status || 'Unknown',
        badgeClass:
            DECLARATION_STATUS_BADGE_CLASS[status] || 'slds-badge',
        isConflict,
        isResolved,
        isAutomatic,
        rowClass,
        showBase: entry.baseValue !== null && entry.baseValue !== undefined,
        baseValueLabel: valueLabelFn(entry.baseValue),
        sourceValueLabel: valueLabelFn(entry.sourceValue),
        destinationValueLabel: valueLabelFn(entry.destinationValue),
        showSelectedValue: isAutomatic && Boolean(selectedValueLabel),
        selectedValueLabel,
        showResolveActions: isConflict,
        showResolutionChoice: isResolved && Boolean(entry.resolution),
        resolutionLabel: formatDeclarationResolutionLabel(entry.resolution),
        showSharingWarning
    };
}

export function buildDeclarationRows(declarations) {
    if (!declarations) {
        return [];
    }

    const rows = [
        buildDeclarationRow(declarations.access, 'Access'),
        buildDeclarationRow(declarations.sharing, 'Sharing')
    ].filter(Boolean);

    return rows;
}