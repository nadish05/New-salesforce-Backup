public with sharing class DeploymentPlanController {

    private static final Integer MAX_SNAPSHOT_JSON_LENGTH = 131072;

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

    /**
     * Read-only: latest Deployment Plan Id for a Metadata Comparison.
     * Does not create or modify plans.
     * Not cacheable — must reflect plans created earlier in the same session.
     */
    @AuraEnabled
    public static Id getLatestDeploymentPlanId(Id comparisonId) {

        if (comparisonId == null) {
            return null;
        }

        List<Deployment_Plan__c> plans = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (plans.isEmpty()) {
            return null;
        }

        return plans[0].Id;
    }

    /**
     * Read-only: latest Deployment Plan plus Stage 4/5 snapshot fields.
     * Active plan rule: ORDER BY CreatedDate DESC LIMIT 1.
     */
    @AuraEnabled
    public static DeploymentPlanState getLatestDeploymentPlanState(
        Id comparisonId
    ) {
        DeploymentPlanState state = new DeploymentPlanState();

        if (comparisonId == null) {
            return state;
        }

        List<Deployment_Plan__c> plans = [
            SELECT
                Id,
                Latest_Review_JSON__c,
                Latest_Review_Status__c,
                Latest_Review_Completed_At__c,
                Latest_Source_Validation_JSON__c,
                Latest_Source_Validation_Status__c,
                Latest_Source_Validation_Completed_At__c,
                Latest_Deployment_Validation_JSON__c,
                Latest_Deployment_Validation_Status__c,
                Latest_Deploy_Val_Completed_At__c
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (plans.isEmpty()) {
            return state;
        }

        Deployment_Plan__c plan = plans[0];
        state.deploymentPlanId = plan.Id;
        state.latestReviewJson = plan.Latest_Review_JSON__c;
        state.latestReviewStatus = plan.Latest_Review_Status__c;
        state.latestReviewCompletedAt = plan.Latest_Review_Completed_At__c;
        state.latestSourceValidationJson =
            plan.Latest_Source_Validation_JSON__c;
        state.latestSourceValidationStatus =
            plan.Latest_Source_Validation_Status__c;
        state.latestSourceValidationCompletedAt =
            plan.Latest_Source_Validation_Completed_At__c;
        state.latestDeploymentValidationJson =
            plan.Latest_Deployment_Validation_JSON__c;
        state.latestDeploymentValidationStatus =
            plan.Latest_Deployment_Validation_Status__c;
        state.latestDeploymentValidationCompletedAt =
            plan.Latest_Deploy_Val_Completed_At__c;
        return state;
    }

    @AuraEnabled
    public static Map<String, Object> saveLatestReviewSnapshot(
        Id deploymentPlanId,
        String reviewJson,
        String status
    ) {
        return saveSnapshot(
            deploymentPlanId,
            reviewJson,
            status,
            SnapshotType.REVIEW
        );
    }

    @AuraEnabled
    public static Map<String, Object> saveLatestSourceValidationSnapshot(
        Id deploymentPlanId,
        String sourceValidationJson,
        String status
    ) {
        return saveSnapshot(
            deploymentPlanId,
            sourceValidationJson,
            status,
            SnapshotType.SOURCE_VALIDATION
        );
    }

    @AuraEnabled
    public static Map<String, Object> saveLatestDeploymentValidationSnapshot(
        Id deploymentPlanId,
        String deploymentValidationJson,
        String status
    ) {
        return saveSnapshot(
            deploymentPlanId,
            deploymentValidationJson,
            status,
            SnapshotType.DEPLOYMENT_VALIDATION
        );
    }

    private enum SnapshotType {
        REVIEW,
        SOURCE_VALIDATION,
        DEPLOYMENT_VALIDATION
    }

    private static Map<String, Object> saveSnapshot(
        Id deploymentPlanId,
        String snapshotJson,
        String status,
        SnapshotType snapshotType
    ) {
        Map<String, Object> response = new Map<String, Object>{
            'success' => false,
            'message' => 'Unable to save deployment plan snapshot.'
        };

        if (deploymentPlanId == null) {
            response.put('message', 'Deployment Plan Id is required.');
            return response;
        }

        if (String.isBlank(snapshotJson)) {
            response.put('message', 'Snapshot JSON is required.');
            return response;
        }

        if (snapshotJson.length() > MAX_SNAPSHOT_JSON_LENGTH) {
            response.put(
                'message',
                'Snapshot JSON exceeds the 131072 character Long Text limit and was not saved.'
            );
            return response;
        }

        List<Deployment_Plan__c> plans = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Id = :deploymentPlanId
            LIMIT 1
        ];

        if (plans.isEmpty()) {
            response.put('message', 'Deployment Plan was not found.');
            return response;
        }

        Deployment_Plan__c plan = new Deployment_Plan__c(
            Id = deploymentPlanId
        );
        Datetime completedAt = Datetime.now();
        String normalizedStatus =
            String.isBlank(status) ? 'COMPLETED' : status.trim();

        switch on snapshotType {
            when REVIEW {
                plan.Latest_Review_JSON__c = snapshotJson;
                plan.Latest_Review_Status__c = truncateStatus(normalizedStatus);
                plan.Latest_Review_Completed_At__c = completedAt;
            }
            when SOURCE_VALIDATION {
                plan.Latest_Source_Validation_JSON__c = snapshotJson;
                plan.Latest_Source_Validation_Status__c =
                    truncateStatus(normalizedStatus);
                plan.Latest_Source_Validation_Completed_At__c = completedAt;
            }
            when DEPLOYMENT_VALIDATION {
                plan.Latest_Deployment_Validation_JSON__c = snapshotJson;
                plan.Latest_Deployment_Validation_Status__c =
                    truncateStatus(normalizedStatus);
                plan.Latest_Deploy_Val_Completed_At__c = completedAt;
            }
        }

        try {
            update plan;
            response.put('success', true);
            response.put('message', null);
            response.put('completedAt', completedAt);
            return response;
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'DeploymentPlanController.saveSnapshot failed: ' +
                e.getMessage()
            );
            response.put('message', e.getMessage());
            return response;
        }
    }

    private static String truncateStatus(String status) {
        if (status == null) {
            return null;
        }
        return status.length() > 80 ? status.substring(0, 80) : status;
    }

    public class DeploymentPlanState {
        @AuraEnabled public Id deploymentPlanId;
        @AuraEnabled public String latestReviewJson;
        @AuraEnabled public String latestReviewStatus;
        @AuraEnabled public Datetime latestReviewCompletedAt;
        @AuraEnabled public String latestSourceValidationJson;
        @AuraEnabled public String latestSourceValidationStatus;
        @AuraEnabled public Datetime latestSourceValidationCompletedAt;
        @AuraEnabled public String latestDeploymentValidationJson;
        @AuraEnabled public String latestDeploymentValidationStatus;
        @AuraEnabled public Datetime latestDeploymentValidationCompletedAt;
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