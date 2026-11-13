export function buildLatestPlanLifecycleLookup(deploymentItems = []) {
    const byComparisonResultId = new Map();
    const byFilePath = new Map();
    const successfulItems = [];

    deploymentItems.forEach((item) => {
        const status = item.Deployment_Status__c;
        if (status !== 'Validated' && status !== 'Deployed') {
            return;
        }

        successfulItems.push(item);

        if (item.Comparison_Result__c) {
            byComparisonResultId.set(
                item.Comparison_Result__c,
                higherLifecycleStatus(
                    byComparisonResultId.get(item.Comparison_Result__c),
                    status
                )
            );
        }
        if (item.File_Path__c) {
            byFilePath.set(
                item.File_Path__c,
                higherLifecycleStatus(
                    byFilePath.get(item.File_Path__c),
                    status
                )
            );
        }
    });

    // Exact path is the stable identity across re-comparisons. Synchronize
    // every historical Comparison_Result Id for that path to its aggregated
    // status so the preferred Id join cannot hide a higher path-level state.
    successfulItems.forEach((item) => {
        if (!item.Comparison_Result__c || !item.File_Path__c) {
            return;
        }

        byComparisonResultId.set(
            item.Comparison_Result__c,
            higherLifecycleStatus(
                byComparisonResultId.get(item.Comparison_Result__c),
                byFilePath.get(item.File_Path__c)
            )
        );
    });

    return { byComparisonResultId, byFilePath };
}

function higherLifecycleStatus(currentStatus, candidateStatus) {
    if (currentStatus === 'Deployed' || candidateStatus === 'Deployed') {
        return 'Deployed';
    }
    if (currentStatus === 'Validated' || candidateStatus === 'Validated') {
        return 'Validated';
    }
    return undefined;
}

export function resolveLatestPlanLifecycle(record, lookup) {
    const status =
        lookup.byComparisonResultId.get(record.Id) ||
        lookup.byFilePath.get(record.File_Path__c);

    if (status === 'Validated') {
        return {
            showBadge: true,
            label: 'Validated',
            cssClass:
                'metadata-lifecycle-badge metadata-lifecycle-validated'
        };
    }

    if (status === 'Deployed') {
        return {
            showBadge: true,
            label: 'Deployed',
            cssClass:
                'metadata-lifecycle-badge metadata-lifecycle-deployed'
        };
    }

    return {
        showBadge: false,
        label: '',
        cssClass: ''
    };
}