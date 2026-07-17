public with sharing class DeploymentPlanController {

    @AuraEnabled
    public static Id createDeploymentPlan(
        Id comparisonId
    ) {

        Metadata_Comparison__c comparison = [

            SELECT
                Id,
                Source_Org__c,
                Destination_Org__c

            FROM Metadata_Comparison__c

            WHERE Id = :comparisonId

            LIMIT 1
        ];

        List<Comparison_Result__c> selectedFiles = [

            SELECT
                Id,
                Metadata_Type__c,
                File_Name__c,
                File_Path__c,
                Selected_For_Deployment__c

            FROM Comparison_Result__c

            WHERE Metadata_Comparison__c = :comparisonId
            AND Selected_For_Deployment__c = true
        ];

        Deployment_Plan__c plan =
            new Deployment_Plan__c(

                Name =
                    'DP-' +
                    Datetime.now().getTime(),

                Metadata_Comparison__c =
                    comparisonId,

                Source_Org__c =
                    comparison.Source_Org__c,

                Destination_Org__c =
                    comparison.Destination_Org__c,

                Status__c =
                    'Draft',

                Selected_Count__c =
                    selectedFiles.size(),

                Dependency_Count__c =
                    0
            );

        insert plan;

        List<Deployment_Item__c> items =
            new List<Deployment_Item__c>();

        for(
            Comparison_Result__c result :
            selectedFiles
        ) {

            items.add(

                new Deployment_Item__c(

                    Deployment_Plan__c =
                        plan.Id,

                    Comparison_Result__c =
                        result.Id,

                    Metadata_Type__c =
                        result.Metadata_Type__c,

                    File_Name__c =
                        result.File_Name__c,

                    File_Path__c =
                        result.File_Path__c,

                    Required__c =
                        false,

                    Selected_By_User__c =
                        true,

                    Deployment_Status__c =
                        'Pending'
                )

            );

        }

        if(!items.isEmpty()) {
            insert items;
        }

        return plan.Id;
    }


@AuraEnabled
public static void analyzeDependencies(
    Id deploymentPlanId
) {

    List<Deployment_Item__c> items = [

        SELECT
            Id,
            Metadata_Type__c,
            File_Name__c,
            File_Path__c

        FROM Deployment_Item__c

        WHERE Deployment_Plan__c =
            :deploymentPlanId

    ];

    for(
        Deployment_Item__c item :
        items
    ) {

        if(
            item.Metadata_Type__c ==
            'ApexClass'
        ) {

            String testClass1 =
                item.File_Name__c.replace('.cls', '') +
                'Test';

            String testClass2 =
                'Test' +
                item.File_Name__c.replace('.cls', '');

            Integer countClasses = [

                SELECT Count()

                FROM ApexClass

                WHERE Name = :testClass1
                OR Name = :testClass2

            ];

            Boolean hasTestClass =
                countClasses > 0;

            DependencyReviewResult result =
                new DependencyReviewResult();

            if(hasTestClass) {

                result.status = 'Ready';

                result.validations.add(
                    'Test Class Found'
                );

            }
            else {

                result.status = 'Blocked';

                result.validations.add(
                    'No Test Class Found'
                );

            }

            result.dependencies.add(
                'Apex Class Review'
            );

            item.Dependency_Source__c =

                String.join(
                    result.dependencies,
                    ', '
                );

            item.Dependency_Count__c =

                result.dependencies.size();

            item.Validation_Status__c =

                result.status;

            item.Validation_Result__c =

                String.join(
                    result.validations,
                    ', '
                );

            item.Coverage_Percentage__c =

                result.coveragePercentage;

        }
        else {

            item.Dependency_Source__c =
                'Dependency analysis pending';

            item.Dependency_Count__c =
                0;

        }

    }

    if(!items.isEmpty()) {

        update items;

    }

}

@AuraEnabled
public static void validateDeploymentPlan(
    Id deploymentPlanId
) {

    List<Deployment_Item__c> items = [

        SELECT
            Id,
            File_Name__c,
            Metadata_Type__c

        FROM Deployment_Item__c

        WHERE Deployment_Plan__c =
            :deploymentPlanId

    ];

    List<Deployment_Item__c> itemsToUpdate =
        new List<Deployment_Item__c>();

    for(
    Deployment_Item__c item :
    items
) {

    item.Validation_Status__c =
        'Ready';

    item.Validation_Result__c =
        'Test';

    item.Dependency_Count__c =
        0;

    itemsToUpdate.add(item);

}

    if(
        !itemsToUpdate.isEmpty()
    ) {

        update itemsToUpdate;

    }

}

}