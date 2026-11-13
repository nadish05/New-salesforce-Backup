/**
 * Pure helpers for Apex Merge eligibility (Stage 4A).
 * Operates on comparison result records; does not mutate.
 */

import { resolveDisplayGroupType } from './bulkDeploymentIntent';

/**
 * Logical Apex class name for merge identity / deduplication.
 */
export function resolveApexClassIdentity(record) {
    if (!record) {
        return '';
    }

    const fileName = record.File_Name__c || '';
    const filePath = record.File_Path__c || '';

    if (/\.cls$/i.test(fileName) && !/\.cls-meta\.xml$/i.test(fileName)) {
        return fileName.replace(/\.cls$/i, '');
    }

    if (filePath.includes('/')) {
        const base = filePath.split('/').pop() || '';
        if (/\.cls$/i.test(base) && !/\.cls-meta\.xml$/i.test(base)) {
            return base.replace(/\.cls$/i, '');
        }
    }

  return '';
}

/**
 * @param {object} record Comparison_Result-shaped row
 */
export function isEligibleApexMergeRecord(record) {
    if (!record || record.Selected_For_Deployment__c !== true) {
        return false;
    }

    if (record.Change_Type__c !== 'MODIFIED') {
        return false;
    }

    if (resolveDisplayGroupType(record) !== 'ApexClass') {
        return false;
    }

    const filePath = (record.File_Path__c || '').trim();
    const fileName = (record.File_Name__c || '').trim();
    const pathLower = filePath.toLowerCase();
    const nameLower = fileName.toLowerCase();

    if (pathLower.endsWith('.cls-meta.xml') || nameLower.endsWith('.cls-meta.xml')) {
        return false;
    }

    return pathLower.endsWith('.cls') || /\.cls$/i.test(fileName);
}

/**
 * Eligible modified Apex classes selected for deployment (.cls only, deduped).
 */
export function getEligibleApexMergeRecords(savedComparisonResults) {
    const records = (savedComparisonResults || []).filter(
        isEligibleApexMergeRecord
    );

    const seen = new Set();
    const deduped = [];

    records.forEach((record) => {
        const identity = resolveApexClassIdentity(record);
        const dedupeKey = identity || record.Id;
        if (seen.has(dedupeKey)) {
            return;
        }
        seen.add(dedupeKey);
        deduped.push(record);
    });

    return deduped;
}

export function buildMergeScopeKey(comparisonId, deploymentPlanId) {
    return `${comparisonId || ''}::${deploymentPlanId || ''}`;
}

export function requiresApexMergePhase(savedComparisonResults) {
    return getEligibleApexMergeRecords(savedComparisonResults).length > 0;
}