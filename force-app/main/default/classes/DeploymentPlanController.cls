public with sharing class DeploymentPlanController {

    private static final Integer MAX_INLINE_SNAPSHOT_JSON_LENGTH = 131072;
    private static final Integer SNAPSHOT_CHUNK_SIZE = 100000;
    private static final String SNAPSHOT_STATUS_COMPLETE = 'COMPLETE';

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
     * Read-only: latest Deployment Plan plus Stage 4/5 snapshot payloads.
     * Active plan rule: ORDER BY CreatedDate DESC LIMIT 1.
     * Inline Long Text wins when present; otherwise reconstruct COMPLETE chunks.
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
        state.latestReviewStatus = plan.Latest_Review_Status__c;
        state.latestReviewCompletedAt = plan.Latest_Review_Completed_At__c;
        state.latestSourceValidationStatus =
            plan.Latest_Source_Validation_Status__c;
        state.latestSourceValidationCompletedAt =
            plan.Latest_Source_Validation_Completed_At__c;
        state.latestDeploymentValidationStatus =
            plan.Latest_Deployment_Validation_Status__c;
        state.latestDeploymentValidationCompletedAt =
            plan.Latest_Deploy_Val_Completed_At__c;

        state.latestReviewJson = resolveSnapshotJson(
            plan.Id,
            SnapshotType.REVIEW,
            plan.Latest_Review_JSON__c
        );
        state.latestSourceValidationJson = resolveSnapshotJson(
            plan.Id,
            SnapshotType.SOURCE_VALIDATION,
            plan.Latest_Source_Validation_JSON__c
        );
        state.latestDeploymentValidationJson = resolveSnapshotJson(
            plan.Id,
            SnapshotType.DEPLOYMENT_VALIDATION,
            plan.Latest_Deployment_Validation_JSON__c
        );
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

        Integer payloadLength = snapshotJson.length();
        System.debug(
            LoggingLevel.INFO,
            'DeploymentPlanController.saveSnapshot type=' +
            snapshotTypeName(snapshotType) +
            ' charLength=' +
            payloadLength
        );

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

        Datetime completedAt = Datetime.now();
        String normalizedStatus =
            String.isBlank(status) ? 'COMPLETED' : status.trim();

        try {
            if (payloadLength <= MAX_INLINE_SNAPSHOT_JSON_LENGTH) {
                persistInlineSnapshot(
                    deploymentPlanId,
                    snapshotJson,
                    normalizedStatus,
                    completedAt,
                    snapshotType
                );
            } else {
                persistChunkedSnapshot(
                    deploymentPlanId,
                    snapshotJson,
                    normalizedStatus,
                    completedAt,
                    snapshotType
                );
            }

            response.put('success', true);
            response.put('message', null);
            response.put('completedAt', completedAt);
            response.put('charLength', payloadLength);
            response.put(
                'storageMode',
                payloadLength <= MAX_INLINE_SNAPSHOT_JSON_LENGTH
                    ? 'INLINE'
                    : 'CHUNKED'
            );
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

    private static void persistInlineSnapshot(
        Id deploymentPlanId,
        String snapshotJson,
        String normalizedStatus,
        Datetime completedAt,
        SnapshotType snapshotType
    ) {
        Deployment_Plan__c plan = new Deployment_Plan__c(
            Id = deploymentPlanId
        );
        applyPlanSnapshotFields(
            plan,
            snapshotJson,
            normalizedStatus,
            completedAt,
            snapshotType
        );
        update plan;
        deleteChunksForType(deploymentPlanId, snapshotType, null);
    }

    private static void persistChunkedSnapshot(
        Id deploymentPlanId,
        String snapshotJson,
        String normalizedStatus,
        Datetime completedAt,
        SnapshotType snapshotType
    ) {
        String snapshotKey = EncodingUtil.convertToHex(
            Crypto.generateAesKey(128)
        );
        if (snapshotKey.length() > 36) {
            snapshotKey = snapshotKey.substring(0, 36);
        }

        List<String> chunks = splitIntoChunks(
            snapshotJson,
            SNAPSHOT_CHUNK_SIZE
        );
        Integer totalChunks = chunks.size();
        String typeName = snapshotTypeName(snapshotType);

        List<Deployment_Plan_Snapshot__c> rows =
            new List<Deployment_Plan_Snapshot__c>();

        for (Integer i = 0; i < totalChunks; i++) {
            rows.add(
                new Deployment_Plan_Snapshot__c(
                    Deployment_Plan__c = deploymentPlanId,
                    Snapshot_Type__c = typeName,
                    Snapshot_Status__c = SNAPSHOT_STATUS_COMPLETE,
                    Snapshot_Key__c = snapshotKey,
                    Chunk_Number__c = i + 1,
                    Total_Chunks__c = totalChunks,
                    Payload_Chunk__c = chunks[i],
                    Completed_At__c = completedAt
                )
            );
        }

        try {
            insert rows;
        } catch (Exception insertError) {
            deleteChunksByKey(deploymentPlanId, snapshotType, snapshotKey);
            throw insertError;
        }

        // Mark plan status only after all chunks exist. Clear inline JSON.
        Deployment_Plan__c plan = new Deployment_Plan__c(
            Id = deploymentPlanId
        );
        applyPlanSnapshotFields(
            plan,
            null,
            normalizedStatus,
            completedAt,
            snapshotType
        );
        try {
            update plan;
        } catch (Exception planError) {
            deleteChunksByKey(deploymentPlanId, snapshotType, snapshotKey);
            throw planError;
        }

        deleteChunksForType(deploymentPlanId, snapshotType, snapshotKey);
    }

    private static void applyPlanSnapshotFields(
        Deployment_Plan__c plan,
        String snapshotJson,
        String normalizedStatus,
        Datetime completedAt,
        SnapshotType snapshotType
    ) {
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
    }

    private static String resolveSnapshotJson(
        Id deploymentPlanId,
        SnapshotType snapshotType,
        String inlineJson
    ) {
        if (String.isNotBlank(inlineJson)) {
            return inlineJson;
        }
        return reconstructChunkedSnapshot(deploymentPlanId, snapshotType);
    }

    private static String reconstructChunkedSnapshot(
        Id deploymentPlanId,
        SnapshotType snapshotType
    ) {
        String typeName = snapshotTypeName(snapshotType);

        List<Deployment_Plan_Snapshot__c> rows = [
            SELECT
                Payload_Chunk__c,
                Chunk_Number__c,
                Total_Chunks__c,
                Snapshot_Key__c,
                Completed_At__c
            FROM Deployment_Plan_Snapshot__c
            WHERE Deployment_Plan__c = :deploymentPlanId
            AND Snapshot_Type__c = :typeName
            AND Snapshot_Status__c = :SNAPSHOT_STATUS_COMPLETE
            ORDER BY Completed_At__c DESC, Chunk_Number__c ASC
        ];

        if (rows.isEmpty()) {
            return null;
        }

        String latestKey = rows[0].Snapshot_Key__c;
        Integer expectedTotal = rows[0].Total_Chunks__c == null
            ? null
            : Integer.valueOf(rows[0].Total_Chunks__c);

        if (String.isBlank(latestKey) || expectedTotal == null || expectedTotal < 1) {
            return null;
        }

        Map<Integer, String> chunkByNumber = new Map<Integer, String>();
        for (Deployment_Plan_Snapshot__c row : rows) {
            if (row.Snapshot_Key__c != latestKey) {
                continue;
            }
            if (row.Chunk_Number__c == null) {
                continue;
            }
            Integer chunkNumber = Integer.valueOf(row.Chunk_Number__c);
            if (!chunkByNumber.containsKey(chunkNumber)) {
                chunkByNumber.put(chunkNumber, row.Payload_Chunk__c);
            }
        }

        if (chunkByNumber.size() != expectedTotal) {
            System.debug(
                LoggingLevel.ERROR,
                'Incomplete snapshot chunks for plan=' +
                deploymentPlanId +
                ' type=' +
                typeName +
                ' expected=' +
                expectedTotal +
                ' actual=' +
                chunkByNumber.size()
            );
            return null;
        }

        List<String> ordered = new List<String>();
        for (Integer i = 1; i <= expectedTotal; i++) {
            if (!chunkByNumber.containsKey(i)) {
                return null;
            }
            ordered.add(
                chunkByNumber.get(i) == null ? '' : chunkByNumber.get(i)
            );
        }

        String reconstructed = String.join(ordered, '');
        if (String.isBlank(reconstructed)) {
            return null;
        }

        // Validate JSON shape before returning for hydration.
        try {
            JSON.deserializeUntyped(reconstructed);
        } catch (Exception parseError) {
            System.debug(
                LoggingLevel.ERROR,
                'Reconstructed snapshot JSON invalid for plan=' +
                deploymentPlanId +
                ' type=' +
                typeName
            );
            return null;
        }

        return reconstructed;
    }

    private static List<String> splitIntoChunks(
        String payload,
        Integer chunkSize
    ) {
        List<String> chunks = new List<String>();
        if (String.isBlank(payload)) {
            return chunks;
        }

        Integer startIndex = 0;
        Integer payloadLength = payload.length();
        while (startIndex < payloadLength) {
            Integer endIndex = Math.min(startIndex + chunkSize, payloadLength);
            chunks.add(payload.substring(startIndex, endIndex));
            startIndex = endIndex;
        }
        return chunks;
    }

    private static void deleteChunksForType(
        Id deploymentPlanId,
        SnapshotType snapshotType,
        String keepSnapshotKey
    ) {
        String typeName = snapshotTypeName(snapshotType);
        List<Deployment_Plan_Snapshot__c> stale;

        if (String.isBlank(keepSnapshotKey)) {
            stale = [
                SELECT Id
                FROM Deployment_Plan_Snapshot__c
                WHERE Deployment_Plan__c = :deploymentPlanId
                AND Snapshot_Type__c = :typeName
            ];
        } else {
            stale = [
                SELECT Id
                FROM Deployment_Plan_Snapshot__c
                WHERE Deployment_Plan__c = :deploymentPlanId
                AND Snapshot_Type__c = :typeName
                AND Snapshot_Key__c != :keepSnapshotKey
            ];
        }

        if (!stale.isEmpty()) {
            delete stale;
        }
    }

    private static void deleteChunksByKey(
        Id deploymentPlanId,
        SnapshotType snapshotType,
        String snapshotKey
    ) {
        if (String.isBlank(snapshotKey)) {
            return;
        }
        String typeName = snapshotTypeName(snapshotType);
        List<Deployment_Plan_Snapshot__c> rows = [
            SELECT Id
            FROM Deployment_Plan_Snapshot__c
            WHERE Deployment_Plan__c = :deploymentPlanId
            AND Snapshot_Type__c = :typeName
            AND Snapshot_Key__c = :snapshotKey
        ];
        if (!rows.isEmpty()) {
            delete rows;
        }
    }

    private static String snapshotTypeName(SnapshotType snapshotType) {
        switch on snapshotType {
            when REVIEW {
                return 'REVIEW';
            }
            when SOURCE_VALIDATION {
                return 'SOURCE_VALIDATION';
            }
            when DEPLOYMENT_VALIDATION {
                return 'DEPLOYMENT_VALIDATION';
            }
        }
        return null;
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