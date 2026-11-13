/**
 * Presentation-only helpers for Comparison Summary bulk deployment intent.
 * Operates on savedComparisonResults; does not mutate records.
 */

export const BULK_CHANGE_TYPE_ORDER = ['DELETED', 'MODIFIED', 'NEW'];

export const BULK_INTENT_OPTIONS = [
    { label: 'Deploy ALL', value: 'Deploy' },
    { label: 'Ignore ALL', value: 'Ignore' },
    { label: 'Clear Selection', value: '__CLEAR__' }
];

/**
 * Mirrors migrationDashboard._resolveDisplayGroupType for bulk scoping.
 */
export function resolveDisplayGroupType(record) {
    if (!record) {
        return '';
    }

    const storedType = record.Metadata_Type__c;

    if (storedType && storedType !== 'Other') {
        return storedType;
    }

    const filePath = record.File_Path__c || '';
    const fileName = record.File_Name__c || '';

    if (
        filePath.includes('/namedCredentials/') ||
        fileName.endsWith('.namedCredential-meta.xml')
    ) {
        return 'NamedCredential';
    }

    if (
        filePath.includes('/labels/') ||
        fileName.endsWith('.labels-meta.xml')
    ) {
        return 'CustomLabel';
    }

    if (
        filePath.includes('/customMetadata/') ||
        fileName.endsWith('.md-meta.xml')
    ) {
        return 'CustomMetadata';
    }

    if (
        filePath.includes('/layouts/') ||
        filePath.startsWith('layouts/') ||
        fileName.endsWith('.layout-meta.xml')
    ) {
        return 'Layout';
    }

    return storedType || 'Other';
}

/**
 * Returns Comparison_Result Ids matching metadata type + change type.
 */
export function getBulkIntentTargetIds(
    savedComparisonResults,
    metadataType,
    changeType
) {
    if (!metadataType || !changeType) {
        return [];
    }

    return (savedComparisonResults || [])
        .filter(
            (record) => resolveDisplayGroupType(record) === metadataType
        )
        .filter((record) => (record.Change_Type__c || '') === changeType)
        .map((record) => record.Id)
        .filter(Boolean);
}

function formatChangeTypeLabel(changeType) {
    switch (changeType) {
        case 'NEW':
            return 'New';
        case 'MODIFIED':
            return 'Modified';
        case 'DELETED':
            return 'Deleted';
        default:
            return changeType;
    }
}

function getChangeTypeBadgeClass(changeType) {
    switch (changeType) {
        case 'NEW':
            return 'badge-new';
        case 'MODIFIED':
            return 'badge-modified';
        case 'DELETED':
            return 'badge-deleted';
        default:
            return 'badge-default';
    }
}

function buildBulkActionTitle(metadataType, changeTypeLabel, verb) {
    return `${verb} all ${changeTypeLabel} ${metadataType} records in this comparison`;
}

function resolveRecordDeploymentIntent(record) {
    if (
        record.Deployment_Intent__c === 'Deploy' ||
        record.Deployment_Intent__c === 'Ignore'
    ) {
        return record.Deployment_Intent__c;
    }

    return record.Selected_For_Deployment__c === true ? 'Deploy' : '';
}

/**
 * Derive a shared bulk combobox value when all matching records share intent.
 */
export function deriveBulkChangeTypeIntent(
    savedComparisonResults,
    metadataType,
    changeType
) {
    const matching = (savedComparisonResults || []).filter(
        (record) =>
            resolveDisplayGroupType(record) === metadataType &&
            (record.Change_Type__c || '') === changeType
    );

    if (!matching.length) {
        return {
            value: '',
            placeholder: 'Select'
        };
    }

    const intents = matching.map((record) =>
        resolveRecordDeploymentIntent(record)
    );
    const first = intents[0];
    const allSame = intents.every((intent) => intent === first);

    if (!allSame) {
        return {
            value: '',
            placeholder: 'Select'
        };
    }

    if (first === 'Deploy' || first === 'Ignore') {
        return {
            value: first,
            placeholder: 'Select'
        };
    }

    return {
        value: '',
        placeholder: 'Select'
    };
}

/**
 * Build per-change-type bulk action descriptors for a metadata type group.
 * Counts are from the full savedComparisonResults working copy.
 */
export function buildBulkChangeTypeActions(
    savedComparisonResults,
    metadataType
) {
    if (!metadataType) {
        return [];
    }

    const counts = {};

    (savedComparisonResults || []).forEach((record) => {
        if (resolveDisplayGroupType(record) !== metadataType) {
            return;
        }

        const changeType = record.Change_Type__c || '';
        if (!changeType) {
            return;
        }

        counts[changeType] = (counts[changeType] || 0) + 1;
    });

    return BULK_CHANGE_TYPE_ORDER.filter((changeType) => counts[changeType] > 0).map(
        (changeType) => {
            const label = formatChangeTypeLabel(changeType);
            const derivedIntent = deriveBulkChangeTypeIntent(
                savedComparisonResults,
                metadataType,
                changeType
            );

            return {
                key: `${metadataType}::${changeType}`,
                changeType,
                label,
                count: counts[changeType],
                badgeClass: getChangeTypeBadgeClass(changeType),
                bulkIntentValue: derivedIntent.value,
                bulkIntentPlaceholder: derivedIntent.placeholder,
                comboboxTitle: `Apply bulk deployment intent to all ${label} ${metadataType} records in this comparison`,
                deployTitle: buildBulkActionTitle(
                    metadataType,
                    label,
                    'Deploy'
                ),
                ignoreTitle: buildBulkActionTitle(
                    metadataType,
                    label,
                    'Ignore'
                ),
                clearTitle: `Clear deployment intent for all ${label} ${metadataType} records in this comparison`
            };
        }
    );
}