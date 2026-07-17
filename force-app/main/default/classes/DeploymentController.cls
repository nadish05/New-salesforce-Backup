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