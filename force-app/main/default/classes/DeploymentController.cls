public with sharing class DeploymentController {

    @AuraEnabled
    public static void updateSelection(
        Id resultId,
        Boolean selected
    ) {

        update new Comparison_Result__c(
            Id = resultId,
            Selected_For_Deployment__c = selected
        );

    }

    /**
     * Persists Deployment Intent and keeps Selected_For_Deployment__c in sync.
     * Deploy → Selected_For_Deployment__c = true
     * Ignore → Selected_For_Deployment__c = false
     * Blank/null → clear intent; Selected_For_Deployment__c = false (Select / default)
     */
    @AuraEnabled
    public static void updateIntent(
        Id resultId,
        String intent
    ) {

        if (resultId == null) {
            throw new AuraHandledException('Comparison result Id is required');
        }

        // Phase 5 — Clear Selection: restore fresh-comparison empty state
        if (String.isBlank(intent)) {
            update new Comparison_Result__c(
                Id = resultId,
                Deployment_Intent__c = null,
                Selected_For_Deployment__c = false
            );
            return;
        }

        if (intent != 'Deploy' && intent != 'Ignore') {
            throw new AuraHandledException(
                'Deployment Intent must be Deploy, Ignore, or blank'
            );
        }

        update new Comparison_Result__c(
            Id = resultId,
            Deployment_Intent__c = intent,
            Selected_For_Deployment__c = (intent == 'Deploy')
        );

    }

    @AuraEnabled
public static void analyzeDependencies(
    Id deploymentPlanId
) {

    System.debug(
        'Analyzing Dependencies for: '
        + deploymentPlanId
    );

}

}