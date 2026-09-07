const LAYOUT_SUFFIX = '.layout-meta.xml';

/**
 * Salesforce object API names: letters, digits, underscore; custom objects end with __c.
 * Standard object API names do not contain hyphens.
 */
const OBJECT_API_PATTERN = /^[A-Za-z][A-Za-z0-9_]*(__c)?$/;

export function isLayoutRecord(record) {
    if (!record) {
        return false;
    }

    const type = record.Metadata_Type__c || record.metadataType || '';
    if (type === 'Layout') {
        return true;
    }

    const fileName = (record.File_Name__c || '').toLowerCase();
    const filePath = record.File_Path__c || '';

    return (
        fileName.endsWith(LAYOUT_SUFFIX) ||
        filePath.includes('/layouts/') ||
        filePath.startsWith('layouts/')
    );
}

export function getLayoutBaseName(record) {
    const fileName = record.File_Name__c || '';
    const filePath = record.File_Path__c || '';
    let baseName = fileName;

    if (!baseName.toLowerCase().endsWith(LAYOUT_SUFFIX) && filePath) {
        const segment = filePath.split('/').pop() || '';
        if (segment.toLowerCase().endsWith(LAYOUT_SUFFIX)) {
            baseName = segment;
        }
    }

    if (baseName.toLowerCase().endsWith(LAYOUT_SUFFIX)) {
        return baseName.slice(0, -LAYOUT_SUFFIX.length);
    }

    return baseName;
}

/**
 * Derive parent object from Layout DX filename:
 * {ObjectApiName}-{LayoutLabel}.layout-meta.xml
 */
export function extractLayoutParentObject(record) {
    let baseName = getLayoutBaseName(record);
    if (!baseName) {
        return null;
    }

    try {
        baseName = decodeURIComponent(baseName.replace(/\+/g, ' '));
    } catch (error) {
        // Keep raw name when URI decoding fails.
    }

    const hyphenIndex = baseName.indexOf('-');
    if (hyphenIndex <= 0) {
        return null;
    }

    const parentObject = baseName.substring(0, hyphenIndex).trim();
    if (!parentObject || !OBJECT_API_PATTERN.test(parentObject)) {
        return null;
    }

    return parentObject;
}

export function apexClassBelongsToObject(file, objectName) {
    if (!file || !objectName) {
        return false;
    }

    const className = (file.File_Name__c || '').replace(/\.cls$/i, '');
    if (!className) {
        return false;
    }

    return className === objectName || className.startsWith(objectName);
}

export function recordMatchesSearch(record, searchKeyword) {
    if (!searchKeyword) {
        return true;
    }

    const keyword = searchKeyword.toLowerCase();
    const fileName = (record.File_Name__c || '').toLowerCase();

    if (fileName.includes(keyword)) {
        return true;
    }

    if (!isLayoutRecord(record)) {
        return false;
    }

    const parent = extractLayoutParentObject(record);
    if (parent && parent.toLowerCase().includes(keyword)) {
        return true;
    }

    try {
        const decoded = decodeURIComponent(record.File_Name__c || '')
            .toLowerCase()
            .replace(/\+/g, ' ');
        if (decoded.includes(keyword)) {
            return true;
        }
    } catch (error) {
        // Ignore decode errors.
    }

    return false;
}

export function sortFilesByName(files) {
    return [...(files || [])].sort((left, right) =>
        (left.File_Name__c || '').localeCompare(right.File_Name__c || '')
    );
}

export const PAGE_LAYOUTS_CATEGORY = 'Page Layouts';

/**
 * Attach Layout comparison rows under a Page Layouts metadata category
 * on an existing object group (same pattern as Fields / Record Types).
 */
export function attachPageLayoutsToObjectGroup(objectGroup, layoutFiles) {
    if (!objectGroup || !layoutFiles?.length) {
        return;
    }

    const sorted = sortFilesByName(layoutFiles);
    objectGroup.metadataGroups = objectGroup.metadataGroups || [];

    let pageLayoutsCategory = objectGroup.metadataGroups.find(
        (category) => category.categoryName === PAGE_LAYOUTS_CATEGORY
    );

    if (!pageLayoutsCategory) {
        pageLayoutsCategory = {
            categoryName: PAGE_LAYOUTS_CATEGORY,
            expanded: false,
            files: []
        };
        objectGroup.metadataGroups.unshift(pageLayoutsCategory);
    }

    pageLayoutsCategory.files.push(...sorted);
    objectGroup.files = [...(objectGroup.files || []), ...sorted];
}

export function createLayoutOnlyObjectGroup(objectName, layoutFiles) {
    const objectGroup = {
        objectName,
        expanded: false,
        files: [],
        metadataGroups: []
    };
    attachPageLayoutsToObjectGroup(objectGroup, layoutFiles);
    return objectGroup;
}

/**
 * Flat Layout files that are not linked to an existing CustomObject object group.
 */
export function buildUnlinkedLayoutFiles(unresolvedLayouts, remainingByObject) {
    const remainingFiles = Object.values(remainingByObject || {}).flat();
    return sortFilesByName([...(unresolvedLayouts || []), ...remainingFiles]);
}