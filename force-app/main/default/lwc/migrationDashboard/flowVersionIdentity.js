/**
 * Flow Phase 1 — backend compare/deploy identity pass-through.
 * Does not query Salesforce Flow APIs or infer version from filenames.
 */

export const FLOW_RECORD_FIELDS = {
    definitionDeveloperName: 'Flow_Definition_Developer_Name__c',
    sourceVersionNumber: 'Source_Flow_Version_Number__c',
    sourceVersionId: 'Source_Flow_Version_Id__c',
    selectedMetadataMemberName: 'Selected_Metadata_Member_Name__c',
    selectionIdentity: 'Selection_Identity__c'
};

function text(value) {
    return value === undefined || value === null ? '' : String(value).trim();
}

function isFlowRecord(record) {
    const type = text(record?.Metadata_Type__c || record?.metadataType);
    return type === 'Flow';
}

/**
 * Map backend compare file object keys onto Comparison_Result__c-shaped fields.
 */
export function flowFieldsFromCompareFile(fileData) {
    if (!fileData || typeof fileData !== 'object') {
        return {};
    }

    const definitionDeveloperName = text(fileData.flowDefinitionDeveloperName);
    const selectedMetadataMemberName = text(fileData.selectedMetadataMemberName);
    const sourceFlowVersionId = text(fileData.sourceFlowVersionId);
    const selectionIdentity = text(fileData.selectionIdentity);

    let sourceVersionNumber = null;
    if (
        fileData.sourceFlowVersionNumber !== undefined &&
        fileData.sourceFlowVersionNumber !== null &&
        fileData.sourceFlowVersionNumber !== ''
    ) {
        const parsed = Number(fileData.sourceFlowVersionNumber);
        if (!Number.isNaN(parsed)) {
            sourceVersionNumber = parsed;
        }
    }

    const hasVersionMetadata =
        !!definitionDeveloperName ||
        !!selectedMetadataMemberName ||
        !!sourceFlowVersionId ||
        sourceVersionNumber != null ||
        !!selectionIdentity;

    if (!hasVersionMetadata) {
        return {};
    }

    return {
        [FLOW_RECORD_FIELDS.definitionDeveloperName]: definitionDeveloperName || null,
        [FLOW_RECORD_FIELDS.selectedMetadataMemberName]:
            selectedMetadataMemberName || null,
        [FLOW_RECORD_FIELDS.sourceVersionId]: sourceFlowVersionId || null,
        [FLOW_RECORD_FIELDS.sourceVersionNumber]: sourceVersionNumber,
        [FLOW_RECORD_FIELDS.selectionIdentity]: selectionIdentity || null
    };
}

export function hasFlowVersionMetadata(record) {
    if (!isFlowRecord(record)) {
        return false;
    }

    return (
        !!text(record[FLOW_RECORD_FIELDS.definitionDeveloperName]) ||
        !!text(record[FLOW_RECORD_FIELDS.selectedMetadataMemberName]) ||
        !!text(record[FLOW_RECORD_FIELDS.sourceVersionId]) ||
        record[FLOW_RECORD_FIELDS.sourceVersionNumber] != null ||
        !!text(record[FLOW_RECORD_FIELDS.selectionIdentity])
    );
}

export function resolveFlowDefinitionDeveloperName(record) {
    if (!isFlowRecord(record)) {
        return '';
    }

    const fromField = text(record[FLOW_RECORD_FIELDS.definitionDeveloperName]);
    if (fromField) {
        return fromField;
    }

    return '';
}

/**
 * Version-qualified label for UI; legacy rows use caller fallback (e.g. File_Name__c).
 */
export function resolveFlowDisplayName(record, legacyFileName) {
    if (!isFlowRecord(record)) {
        return legacyFileName || '';
    }

    const memberName = text(record[FLOW_RECORD_FIELDS.selectedMetadataMemberName]);
    if (memberName) {
        return memberName;
    }

    return legacyFileName || '';
}

/**
 * Metadata API member name for deployment transport.
 */
export function resolveFlowDeploymentMetadataName(record, legacyMetadataName) {
    if (!isFlowRecord(record)) {
        return legacyMetadataName || '';
    }

    const memberName = text(record[FLOW_RECORD_FIELDS.selectedMetadataMemberName]);
    if (memberName) {
        return memberName;
    }

    return legacyMetadataName || '';
}

export function resolveFlowSelectionIdentity(record) {
    if (!isFlowRecord(record)) {
        return '';
    }

    const identity = text(record[FLOW_RECORD_FIELDS.selectionIdentity]);
    if (identity) {
        return identity;
    }

    const versionId = text(record[FLOW_RECORD_FIELDS.sourceVersionId]);
    const definitionName = text(record[FLOW_RECORD_FIELDS.definitionDeveloperName]);
    if (definitionName && versionId) {
        return `Flow:${definitionName}:${versionId}`;
    }

    return '';
}

/**
 * Planner / dedupe key — never DeveloperName alone.
 */
export function resolveFlowPlannerKey(record) {
    const identity = resolveFlowSelectionIdentity(record);
    if (identity) {
        return `primary:${identity}`;
    }

    const path = text(record?.File_Path__c);
    if (path) {
        return `primary:${path}`;
    }

    const id = text(record?.Id);
    return id ? `primary:${id}` : 'primary:unknown';
}

/**
 * Active / Inactive / Other buckets for groupFlowFiles.
 * Uses backend-provided Flow_Status__c only — no version-number inference.
 */
export function resolveFlowCategoryBucket(record) {
    const status = text(record?.Flow_Status__c);

    if (status === 'Active') {
        return 'Active';
    }

    if (status === 'Obsolete') {
        return 'Inactive';
    }

    return 'Other';
}

/**
 * Backend Phase 1 selectedMetadata / review row extension for Flow.
 */
export function buildFlowSelectionTransport(record, baseEntry) {
    if (!isFlowRecord(record) || !baseEntry) {
        return baseEntry;
    }

    const definitionDeveloperName = resolveFlowDefinitionDeveloperName(record);
    const sourceFlowVersionId = text(record[FLOW_RECORD_FIELDS.sourceVersionId]);
    const selectionIdentity = resolveFlowSelectionIdentity(record);
    const workspaceArtifactPath = text(record?.File_Path__c);
    const sourceFlowVersionNumber =
        record[FLOW_RECORD_FIELDS.sourceVersionNumber];

    const payload = {
        ...baseEntry,
        metadataType: 'Flow',
        metadataName: resolveFlowDeploymentMetadataName(
            record,
            baseEntry.metadataName
        ),
        name: resolveFlowDeploymentMetadataName(record, baseEntry.name),
        filePath: baseEntry.filePath || workspaceArtifactPath || undefined,
        path: baseEntry.path || workspaceArtifactPath || undefined
    };

    if (definitionDeveloperName) {
        payload.flowDefinitionDeveloperName = definitionDeveloperName;
    }
    if (sourceFlowVersionNumber != null && sourceFlowVersionNumber !== '') {
        payload.sourceFlowVersionNumber = sourceFlowVersionNumber;
    }
    if (sourceFlowVersionId) {
        payload.sourceFlowVersionId = sourceFlowVersionId;
    }
    const selectedMetadataMemberName = text(
        record[FLOW_RECORD_FIELDS.selectedMetadataMemberName]
    );
    if (selectedMetadataMemberName) {
        payload.selectedMetadataMemberName = selectedMetadataMemberName;
    }
    if (workspaceArtifactPath) {
        payload.workspaceArtifactPath = workspaceArtifactPath;
    }
    if (selectionIdentity) {
        payload.selectionIdentity = selectionIdentity;
    }

    return payload;
}

export function enrichFlowComparisonRow(record, legacyFileName) {
    if (!isFlowRecord(record)) {
        return {
            flowDisplayName: legacyFileName || '',
            flowDefinitionDeveloperName: ''
        };
    }

    return {
        flowDisplayName: resolveFlowDisplayName(record, legacyFileName),
        flowDefinitionDeveloperName:
            resolveFlowDefinitionDeveloperName(record) || null
    };
}