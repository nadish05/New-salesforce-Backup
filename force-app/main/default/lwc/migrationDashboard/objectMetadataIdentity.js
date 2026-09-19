/**
 * DX metadata identity derived from Salesforce source file paths.
 * Keeps comparison classification and deployment package naming aligned
 * with the backend Metadata API contract (Object.Child qualified names).
 */

const OBJECT_CHILD_TYPE_RULES = [
    {
        folder: '/fields/',
        suffix: '.field-meta.xml',
        type: 'CustomField'
    },
    {
        folder: '/validationrules/',
        suffix: '.validationrule-meta.xml',
        type: 'ValidationRule'
    },
    {
        folder: '/recordtypes/',
        suffix: '.recordtype-meta.xml',
        type: 'RecordType'
    },
    {
        folder: '/listviews/',
        suffix: '.listview-meta.xml',
        type: 'ListView'
    },
    {
        folder: '/compactlayouts/',
        suffix: '.compactlayout-meta.xml',
        type: 'CompactLayout'
    },
    {
        folder: '/fieldsets/',
        suffix: '.fieldset-meta.xml',
        type: 'FieldSet'
    },
    {
        folder: '/sharingreasons/',
        suffix: '.sharingreason-meta.xml',
        type: 'SharingReason'
    },
    {
        folder: '/weblinks/',
        suffix: '.weblink-meta.xml',
        type: 'WebLink'
    },
    {
        folder: '/indexes/',
        suffix: '.index-meta.xml',
        type: 'CustomIndex'
    },
    {
        folder: '/businessprocesses/',
        suffix: '.businessprocess-meta.xml',
        type: 'BusinessProcess'
    }
];

const QUALIFIED_OBJECT_CHILD_TYPES = new Set(
    OBJECT_CHILD_TYPE_RULES.map((rule) => rule.type)
);

function normalizePath(filePath) {
    return filePath ? filePath.replace(/\\/g, '/') : '';
}

export function containsObjectsFolder(filePath) {
    const normalizedPath = normalizePath(filePath).toLowerCase();
    return (
        normalizedPath.includes('/objects/') ||
        normalizedPath.startsWith('objects/')
    );
}

export function extractObjectApiNameFromPath(filePath) {
    if (!filePath) {
        return null;
    }

    const match = normalizePath(filePath).match(/objects\/([^/]+)\//i);
    return match ? match[1] : null;
}

export function resolveCustomObjectChildMetadataType(filePath) {
    if (!containsObjectsFolder(filePath)) {
        return null;
    }

    const normalizedPath = filePath.toLowerCase();

    for (const rule of OBJECT_CHILD_TYPE_RULES) {
        if (
            normalizedPath.includes(rule.folder) &&
            normalizedPath.endsWith(rule.suffix)
        ) {
            return rule.type;
        }
    }

    return null;
}

export function isCustomObjectDefinitionPath(filePath) {
    return (
        containsObjectsFolder(filePath) &&
        normalizePath(filePath).toLowerCase().endsWith('.object-meta.xml')
    );
}

export function isObjectFolderMetadataPath(filePath) {
    return containsObjectsFolder(filePath);
}

export function resolveMetadataTypeFromPath(filePath) {
    const childType = resolveCustomObjectChildMetadataType(filePath);
    if (childType) {
        return childType;
    }

    if (isCustomObjectDefinitionPath(filePath)) {
        return 'CustomObject';
    }

    return null;
}

export function extractMemberNameFromFileName(fileName) {
    if (!fileName) {
        return '';
    }

    const dotIndex = fileName.indexOf('.');
    return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
}

export function resolveQualifiedMetadataName(filePath, metadataType, fileName) {
    const pathInferredType = resolveMetadataTypeFromPath(filePath);
    const effectiveType =
        metadataType === 'CustomObject' && pathInferredType
            ? pathInferredType
            : metadataType;

    if (effectiveType === 'CustomObject') {
        if (isCustomObjectDefinitionPath(filePath)) {
            return extractObjectApiNameFromPath(filePath);
        }

        return extractMemberNameFromFileName(fileName);
    }

    if (QUALIFIED_OBJECT_CHILD_TYPES.has(effectiveType)) {
        const objectApiName = extractObjectApiNameFromPath(filePath);
        const memberName = extractMemberNameFromFileName(fileName);

        if (objectApiName && memberName) {
            return `${objectApiName}.${memberName}`;
        }
    }

    return null;
}

/**
 * Resolves deployment metadataName from a Comparison_Result row.
 * Returns null when the caller should apply type-specific handling (Layout).
 */
export function extractMetadataNameFromComparisonFile(file) {
    const fileName = file?.File_Name__c || '';
    const filePath = file?.File_Path__c || '';
    const metadataType = file?.Metadata_Type__c || file?.metadataType || '';

    if (metadataType === 'CustomMetadata') {
        const baseName = filePath.includes('/')
            ? filePath.split('/').pop() || fileName
            : fileName;
        return baseName.replace(/\.md-meta\.xml$/i, '');
    }

    if (metadataType === 'Layout' || fileName.endsWith('.layout-meta.xml')) {
        return null;
    }

    if (fileName.endsWith('.cls')) {
        return fileName.replace(/\.cls$/i, '');
    }

    if (fileName.endsWith('.trigger')) {
        return fileName.replace(/\.trigger$/i, '');
    }

    const qualifiedName = resolveQualifiedMetadataName(
        filePath,
        metadataType,
        fileName
    );
    if (qualifiedName) {
        return qualifiedName;
    }

    if (filePath.includes('/')) {
        const parts = filePath.split('/');
        const base = parts[parts.length - 1];
        return extractMemberNameFromFileName(base);
    }

    return extractMemberNameFromFileName(fileName);
}