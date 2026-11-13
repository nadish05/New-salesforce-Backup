/**
 * Unit tests for Apex merge artifact status serialization and persistence.
 */
@IsTest
private class ApexMergeArtifactStatusServiceTest {
    private static final String VALID_SHA =
        'a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3';

    private static Connected_Org__c createOrg(String suffix) {
        Connected_Org__c orgRec = new Connected_Org__c(
            Name = 'Org-' + suffix,
            Display_Name__c = 'Org-' + suffix,
            Org_ID__c = '00DTEST' + suffix,
            Instance_URL__c = 'https://example-' + suffix + '.my.salesforce.com',
            Refresh_Token__c = 'token-' + suffix,
            Active__c = true
        );
        insert orgRec;
        return orgRec;
    }

    private static Deployment_Plan__c createDeploymentPlan() {
        Connected_Org__c source = createOrg('src-status');
        Connected_Org__c dest = createOrg('dst-status');
        Metadata_Comparison__c comparison = new Metadata_Comparison__c(
            Name = 'Cmp Status',
            Source_Org__c = source.Id,
            Destination_Org__c = dest.Id
        );
        insert comparison;

        Deployment_Plan__c plan = new Deployment_Plan__c(
            Name = 'Plan Status',
            Metadata_Comparison__c = comparison.Id,
            Source_Org__c = source.Id,
            Destination_Org__c = dest.Id,
            Status__c = 'Draft',
            Selected_Count__c = 2,
            Dependency_Count__c = 0,
            Apex_Merge_Manifest_JSON__c = '{"manifestId":"m-1"}'
        );
        insert plan;
        return plan;
    }

    private static Id createContentDocument() {
        ContentVersion cv = new ContentVersion(
            Title = 'status-artifact',
            PathOnClient = 'MyClass.cls',
            VersionData = Blob.valueOf('public class MyClass {}')
        );
        insert cv;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ]
        .ContentDocumentId;
    }

    private static ApexMergeArtifactStatusService.StatusSnapshot buildValidSnapshot(
        Id deploymentPlanId,
        Id comparisonId
    ) {
        ApexMergeArtifactStatusService.StatusSnapshot snapshot =
            ApexMergeArtifactStatusService.newQueuedSnapshot(
                'manifest-sealed-001',
                'session-backend-001',
                comparisonId,
                deploymentPlanId,
                new List<String>{ 'ClassOne', 'ClassTwo' }
            );
        snapshot.overallStatus = ApexMergeArtifactStatusService.OVERALL_PROCESSING;
        snapshot.currentUnitIndex = 0;
        snapshot.updatedAt = ApexMergeArtifactStatusService.nowIsoUtc();
        return snapshot;
    }

    @IsTest
    static void serializesAndDeserializesValidSnapshot() {
        Deployment_Plan__c plan = createDeploymentPlan();
        Id docId = createContentDocument();

        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        ApexMergeArtifactStatusService.UnitStatus unit = snapshot.units[0];
        unit.status = ApexMergeArtifactStatusService.UNIT_FAILED;
        unit.artifacts.cls.status =
            ApexMergeArtifactStatusService.UNIT_COMPLETED;
        unit.artifacts.cls.contentDocumentId = String.valueOf(docId);
        unit.artifacts.cls.sha256 = VALID_SHA;
        unit.artifacts.cls.byteLength = 18;
        unit.artifacts.metaXml.status =
            ApexMergeArtifactStatusService.UNIT_FAILED;
        unit.artifacts.metaXml.errorCode = 'PERSIST_FAILED';
        unit.artifacts.metaXml.errorMessage = 'Meta XML persist failed.';

        String json = ApexMergeArtifactStatusService.serialize(snapshot);
        ApexMergeArtifactStatusService.StatusSnapshot parsed =
            ApexMergeArtifactStatusService.deserialize(json);

        System.assertEquals(
            snapshot.statusRunId,
            parsed.statusRunId,
            'statusRunId round-trips'
        );
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_FAILED,
            parsed.units[0].status
        );
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_COMPLETED,
            parsed.units[0].artifacts.cls.status
        );
        System.assertEquals(
            String.valueOf(docId),
            parsed.units[0].artifacts.cls.contentDocumentId
        );
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_FAILED,
            parsed.units[0].artifacts.metaXml.status
        );
        System.assertEquals(
            'PERSIST_FAILED',
            parsed.units[0].artifacts.metaXml.errorCode
        );
    }

    @IsTest
    static void allowsAllOverallStatuses() {
        Deployment_Plan__c plan = createDeploymentPlan();
        List<String> overalls = new List<String>{
            ApexMergeArtifactStatusService.OVERALL_QUEUED,
            ApexMergeArtifactStatusService.OVERALL_PROCESSING,
            ApexMergeArtifactStatusService.OVERALL_COMPLETED,
            ApexMergeArtifactStatusService.OVERALL_PARTIALLY_FAILED,
            ApexMergeArtifactStatusService.OVERALL_FAILED
        };
        for (String overall : overalls) {
            ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
                plan.Id,
                plan.Metadata_Comparison__c
            );
            snapshot.overallStatus = overall;
            if (
                ApexMergeArtifactStatusService.OVERALL_COMPLETED.equals(overall) ||
                ApexMergeArtifactStatusService.OVERALL_PARTIALLY_FAILED.equals(
                    overall
                ) ||
                ApexMergeArtifactStatusService.OVERALL_FAILED.equals(overall)
            ) {
                snapshot.completedAt = ApexMergeArtifactStatusService.nowIsoUtc();
            } else {
                snapshot.completedAt = null;
            }
            ApexMergeArtifactStatusService.ValidationResult result =
                ApexMergeArtifactStatusService.validate(snapshot);
            System.assertEquals(
                true,
                result.success,
                'Expected valid overallStatus ' + overall + ': ' + result.message
            );
        }
    }

    @IsTest
    static void allowsAllUnitStatuses() {
        Deployment_Plan__c plan = createDeploymentPlan();
        List<String> unitStatuses = new List<String>{
            ApexMergeArtifactStatusService.UNIT_NOT_STARTED,
            ApexMergeArtifactStatusService.UNIT_COMPLETED,
            ApexMergeArtifactStatusService.UNIT_FAILED
        };
        for (String unitStatus : unitStatuses) {
            ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
                plan.Id,
                plan.Metadata_Comparison__c
            );
            snapshot.units[0].status = unitStatus;
            ApexMergeArtifactStatusService.ValidationResult result =
                ApexMergeArtifactStatusService.validate(snapshot);
            System.assertEquals(
                true,
                result.success,
                'Expected valid unit status ' + unitStatus
            );
        }
    }

    @IsTest
    static void rejectsMissingRequiredIdentifiers() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );

        snapshot.statusRunId = null;
        assertInvalid(snapshot, 'statusRunId');

        snapshot = buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        snapshot.mergeManifestId = null;
        assertInvalid(snapshot, 'mergeManifestId');

        snapshot = buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        snapshot.mergeSessionId = null;
        assertInvalid(snapshot, 'mergeSessionId');

        snapshot = buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        snapshot.comparisonId = null;
        assertInvalid(snapshot, 'comparisonId');

        snapshot = buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        snapshot.deploymentPlanId = null;
        assertInvalid(snapshot, 'deploymentPlanId');
    }

    @IsTest
    static void rejectsInvalidOverallStatus() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.overallStatus = 'CANCELLED';
        assertInvalid(snapshot, 'overallStatus');
    }

    @IsTest
    static void rejectsInvalidUnitStatus() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.units[0].status = 'PROCESSING';
        assertInvalid(snapshot, 'unit status');
    }

    @IsTest
    static void rejectsDuplicateMetadataNames() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.units[1].metadataName = 'ClassOne';
        assertInvalid(snapshot, 'Duplicate');
    }

    @IsTest
    static void rejectsInvalidUnitIndexAndCounts() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.totalUnits = 3;
        assertInvalid(snapshot, 'totalUnits');

        snapshot = buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        snapshot.currentUnitIndex = -2;
        assertInvalid(snapshot, 'currentUnitIndex');

        snapshot = buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        snapshot.currentUnitIndex = 2;
        assertInvalid(snapshot, 'currentUnitIndex');
    }

    @IsTest
    static void rejectsInvalidContentDocumentId() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.units[0].artifacts.cls.contentDocumentId = 'not-an-id';
        assertInvalid(snapshot, 'contentDocumentId');
    }

    @IsTest
    static void rejectsNegativeByteLength() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.units[0].artifacts.cls.byteLength = -1;
        assertInvalid(snapshot, 'byteLength');
    }

    @IsTest
    static void rejectsTerminalWithoutCompletedAt() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_FAILED;
        snapshot.completedAt = null;
        assertInvalid(snapshot, 'completedAt');
    }

    @IsTest
    static void rejectsInvalidSha256() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.units[0].artifacts.cls.sha256 = 'not-a-sha256';
        assertInvalid(snapshot, 'sha256');
    }

    @IsTest
    static void rejectsInvalidArtifactRoleViaLastError() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.lastError = new ApexMergeArtifactStatusService.LastError();
        snapshot.lastError.code = 'ERR';
        snapshot.lastError.message = 'failure';
        snapshot.lastError.role = 'sourceCode';
        assertInvalid(snapshot, 'lastError.role');
    }

    @IsTest
    static void loadFromDeploymentPlan_returnsStoredSnapshot() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.overallStatus = ApexMergeArtifactStatusService.OVERALL_QUEUED;
        snapshot.currentUnitIndex = -1;
        System.assertEquals(
            true,
            ApexMergeArtifactStatusService.persist(snapshot).success
        );

        ApexMergeArtifactStatusService.LoadResult loaded =
            ApexMergeArtifactStatusService.loadFromDeploymentPlan(plan.Id);
        System.assertEquals(true, loaded.success);
        System.assertEquals(snapshot.statusRunId, loaded.snapshot.statusRunId);
        System.assertEquals(
            ApexMergeArtifactStatusService.OVERALL_QUEUED,
            loaded.storedOverallStatus
        );
    }

    @IsTest
    static void rejectsMissingDeploymentPlanOnPersist() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );

        Deployment_Plan__c deletedPlan = createDeploymentPlan();
        Id missingPlanId = deletedPlan.Id;
        delete deletedPlan;

        snapshot.deploymentPlanId = String.valueOf(missingPlanId);
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(snapshot);
        System.assertEquals(false, result.success);
        System.assertEquals('NOT_FOUND', result.code);
    }

    @IsTest
    static void rejectsMalformedDeploymentPlanIdOnPersist() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.deploymentPlanId = 'not-a-valid-salesforce-id';
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(snapshot);
        System.assertEquals(false, result.success);
        System.assertEquals('INVALID_REQUEST', result.code);
    }

    @IsTest
    static void persistsAndMapsFourFields() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_COMPLETED;
        snapshot.completedAt = ApexMergeArtifactStatusService.nowIsoUtc();

        Test.startTest();
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(snapshot);
        Test.stopTest();

        System.assertEquals(
            true,
            result.success,
            'Persist should succeed'
        );

        Deployment_Plan__c stored = [
            SELECT
                Latest_Apex_Merge_Artifact_Status__c,
                Latest_Apex_Merge_Artifact_JSON__c,
                Latest_Apex_Merge_Artifact_Started_At__c,
                Latest_Apex_Merge_Artifact_Completed_At__c,
                Apex_Merge_Manifest_JSON__c,
                Selected_Count__c,
                Status__c
            FROM Deployment_Plan__c
            WHERE Id = :plan.Id
            LIMIT 1
        ];

        System.assertEquals(
            ApexMergeArtifactStatusService.OVERALL_COMPLETED,
            stored.Latest_Apex_Merge_Artifact_Status__c
        );
        System.assertNotEquals(null, stored.Latest_Apex_Merge_Artifact_JSON__c);
        System.assertNotEquals(
            null,
            stored.Latest_Apex_Merge_Artifact_Started_At__c
        );
        System.assertNotEquals(
            null,
            stored.Latest_Apex_Merge_Artifact_Completed_At__c
        );
        System.assertEquals(
            '{"manifestId":"m-1"}',
            stored.Apex_Merge_Manifest_JSON__c
        );
        System.assertEquals(2, stored.Selected_Count__c);
        System.assertEquals('Draft', stored.Status__c);
    }

    @IsTest
    static void clearsCompletedAtForActiveStates() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot queued =
            buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        queued.overallStatus = ApexMergeArtifactStatusService.OVERALL_QUEUED;
        queued.currentUnitIndex = -1;
        ApexMergeArtifactStatusService.persist(queued);

        ApexMergeArtifactStatusService.StatusSnapshot processing =
            buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        processing.statusRunId = queued.statusRunId;
        processing.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_PROCESSING;
        processing.completedAt = null;
        ApexMergeArtifactStatusService.persist(processing);

        update new Deployment_Plan__c(
            Id = plan.Id,
            Latest_Apex_Merge_Artifact_Completed_At__c = Datetime.now()
        );

        ApexMergeArtifactStatusService.StatusSnapshot progress =
            buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        progress.statusRunId = queued.statusRunId;
        progress.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_PROCESSING;
        progress.currentUnitIndex = 1;
        progress.completedAt = null;
        ApexMergeArtifactStatusService.persist(progress);

        Deployment_Plan__c stored = [
            SELECT
                Latest_Apex_Merge_Artifact_Completed_At__c,
                Latest_Apex_Merge_Artifact_JSON__c
            FROM Deployment_Plan__c
            WHERE Id = :plan.Id
            LIMIT 1
        ];
        System.assertEquals(null, stored.Latest_Apex_Merge_Artifact_Completed_At__c);

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
            stored.Latest_Apex_Merge_Artifact_JSON__c
        );
        if (payload.containsKey('completedAt')) {
            System.assertEquals(null, payload.get('completedAt'));
        }
    }

    @IsTest
    static void acceptsServiceGeneratedUtcIsoTimestamps() {
        Deployment_Plan__c plan = createDeploymentPlan();
        String timestamp = ApexMergeArtifactStatusService.nowIsoUtc();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.startedAt = timestamp;
        snapshot.updatedAt = timestamp;
        System.assertEquals(
            true,
            ApexMergeArtifactStatusService.validate(snapshot).success,
            'Service timestamps should satisfy validation'
        );
    }

    @IsTest
    static void rejectsMalformedUtcIsoTimestamps() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.startedAt = '2026-11-11 09:00:00';
        assertInvalid(snapshot, 'startedAt missing Z');

        snapshot = buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        snapshot.updatedAt = '2026-11-11T09:00:00';
        assertInvalid(snapshot, 'updatedAt missing Z');
    }

    @IsTest
    static void rejectsInvalidLifecycleTransition() {
        System.assertEquals(
            false,
            ApexMergeArtifactStatusService.validateTransition(
                    ApexMergeArtifactStatusService.OVERALL_QUEUED,
                    ApexMergeArtifactStatusService.OVERALL_COMPLETED
                )
                .success
        );
        System.assertEquals(
            false,
            ApexMergeArtifactStatusService.validateTransition(
                    ApexMergeArtifactStatusService.OVERALL_COMPLETED,
                    ApexMergeArtifactStatusService.OVERALL_PROCESSING
                )
                .success
        );
        System.assertEquals(
            true,
            ApexMergeArtifactStatusService.validateTransition(
                    ApexMergeArtifactStatusService.OVERALL_PROCESSING,
                    ApexMergeArtifactStatusService.OVERALL_PROCESSING
                )
                .success
        );
    }

    @IsTest
    static void persistRejectsInvalidTransitionFromPersistedStatus() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot queued =
            buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        queued.overallStatus = ApexMergeArtifactStatusService.OVERALL_QUEUED;
        queued.currentUnitIndex = -1;
        ApexMergeArtifactStatusService.persist(queued);

        ApexMergeArtifactStatusService.StatusSnapshot completed =
            buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        completed.statusRunId = queued.statusRunId;
        completed.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_COMPLETED;
        completed.completedAt = ApexMergeArtifactStatusService.nowIsoUtc();

        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(completed);
        System.assertEquals(false, result.success);
        System.assertEquals('INVALID_REQUEST', result.code);
    }

    @IsTest
    static void persistOverwritesStaleUpdatedAtInJson() {
        Deployment_Plan__c plan = createDeploymentPlan();
        String staleUpdatedAt = '2000-01-01T00:00:00Z';
        String startedAt = ApexMergeArtifactStatusService.nowIsoUtc();
        String completedAt = ApexMergeArtifactStatusService.nowIsoUtc();

        ApexMergeArtifactStatusService.StatusSnapshot snapshot = buildValidSnapshot(
            plan.Id,
            plan.Metadata_Comparison__c
        );
        snapshot.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_COMPLETED;
        snapshot.startedAt = startedAt;
        snapshot.completedAt = completedAt;
        snapshot.updatedAt = staleUpdatedAt;

        Test.startTest();
        System.assertEquals(
            true,
            ApexMergeArtifactStatusService.persist(snapshot).success
        );
        Test.stopTest();

        System.assertNotEquals(staleUpdatedAt, snapshot.updatedAt);
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
            [
                SELECT Latest_Apex_Merge_Artifact_JSON__c
                FROM Deployment_Plan__c
                WHERE Id = :plan.Id
                LIMIT 1
            ]
            .Latest_Apex_Merge_Artifact_JSON__c
        );
        String jsonUpdatedAt = String.valueOf(payload.get('updatedAt'));
        System.assertNotEquals(staleUpdatedAt, jsonUpdatedAt);
        System.assertEquals(startedAt, String.valueOf(payload.get('startedAt')));
        System.assertEquals(
            completedAt,
            String.valueOf(payload.get('completedAt'))
        );

        Deployment_Plan__c stored = [
            SELECT
                Latest_Apex_Merge_Artifact_Started_At__c,
                Latest_Apex_Merge_Artifact_Completed_At__c
            FROM Deployment_Plan__c
            WHERE Id = :plan.Id
            LIMIT 1
        ];
        System.assertEquals(
            startedAt,
            stored.Latest_Apex_Merge_Artifact_Started_At__c.formatGmt(
                'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
            )
        );
        System.assertEquals(
            completedAt,
            stored.Latest_Apex_Merge_Artifact_Completed_At__c.formatGmt(
                'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
            )
        );
    }

    @IsTest
    static void lockedPersist_rejectsBlankExpectedStatusRunId() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot queued =
            seedQueuedOnPlan(plan);
        Deployment_Plan__c locked = lockPlanForTest(plan.Id);
        ApexMergeArtifactStatusService.StatusSnapshot processing =
            ApexMergeArtifactStatusService.deserialize(
                locked.Latest_Apex_Merge_Artifact_JSON__c
            );
        processing.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_PROCESSING;
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(
                locked,
                processing,
                ' '
            );
        System.assertEquals(false, result.success);
        System.assertEquals(
            ApexMergeArtifactStatusService.CODE_OWNERSHIP_REQUIRED,
            result.code
        );
    }

    @IsTest
    static void lockedPersist_rejectsStoredStatusRunIdMismatch() {
        Deployment_Plan__c plan = createDeploymentPlan();
        seedQueuedOnPlan(plan);
        Deployment_Plan__c locked = lockPlanForTest(plan.Id);
        ApexMergeArtifactStatusService.StatusSnapshot processing =
            ApexMergeArtifactStatusService.deserialize(
                locked.Latest_Apex_Merge_Artifact_JSON__c
            );
        processing.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_PROCESSING;
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(
                locked,
                processing,
                'wrong-run-id'
            );
        System.assertEquals(false, result.success);
        System.assertEquals(
            ApexMergeArtifactStatusService.CODE_RUN_OWNERSHIP_LOST,
            result.code
        );
    }

    @IsTest
    static void lockedPersist_rejectsIncomingStatusRunIdMismatch() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot queued =
            seedQueuedOnPlan(plan);
        Deployment_Plan__c locked = lockPlanForTest(plan.Id);
        ApexMergeArtifactStatusService.StatusSnapshot processing =
            ApexMergeArtifactStatusService.deserialize(
                locked.Latest_Apex_Merge_Artifact_JSON__c
            );
        processing.statusRunId = 'incoming-mismatch';
        processing.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_PROCESSING;
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(
                locked,
                processing,
                queued.statusRunId
            );
        System.assertEquals(false, result.success);
        System.assertEquals(
            ApexMergeArtifactStatusService.CODE_RUN_OWNERSHIP_LOST,
            result.code
        );
    }

    @IsTest
    static void lockedPersist_rejectsLockedPlanIdMismatch() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot queued =
            seedQueuedOnPlan(plan);
        Deployment_Plan__c other = createDeploymentPlan();
        Deployment_Plan__c locked = lockPlanForTest(other.Id);
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(
                locked,
                queued,
                queued.statusRunId
            );
        System.assertEquals(false, result.success);
        System.assertEquals('INVALID_REQUEST', result.code);
    }

    @IsTest
    static void lockedPersist_succeedsForValidOwner() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot queued =
            seedQueuedOnPlan(plan);
        Deployment_Plan__c locked = lockPlanForTest(plan.Id);
        ApexMergeArtifactStatusService.StatusSnapshot processing =
            ApexMergeArtifactStatusService.deserialize(
                locked.Latest_Apex_Merge_Artifact_JSON__c
            );
        processing.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_PROCESSING;
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(
                locked,
                processing,
                queued.statusRunId
            );
        System.assertEquals(true, result.success);
    }

    @IsTest
    static void persistNewQueuedRun_requiresBlankDurableFields() {
        Deployment_Plan__c plan = createDeploymentPlan();
        seedQueuedOnPlan(plan);
        Deployment_Plan__c locked = lockPlanForTest(plan.Id);
        ApexMergeArtifactStatusService.StatusSnapshot next =
            ApexMergeArtifactStatusService.newQueuedSnapshot(
                'manifest-next',
                'session-next',
                plan.Metadata_Comparison__c,
                plan.Id,
                new List<String>{ 'Foo' }
            );
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persistNewQueuedRun(locked, next);
        System.assertEquals(false, result.success);
        System.assertEquals(
            ApexMergeArtifactStatusService.CODE_STATUS_STORE_AMBIGUOUS,
            result.code
        );
    }

    @IsTest
    static void lockedPersist_rejectsMalformedStoredJson() {
        Deployment_Plan__c plan = createDeploymentPlan();
        plan.Latest_Apex_Merge_Artifact_Status__c =
            ApexMergeArtifactStatusService.OVERALL_QUEUED;
        plan.Latest_Apex_Merge_Artifact_JSON__c = '{not-valid-status-json';
        update plan;
        Deployment_Plan__c locked = lockPlanForTest(plan.Id);
        ApexMergeArtifactStatusService.StatusSnapshot incoming =
            ApexMergeArtifactStatusService.newQueuedSnapshot(
                'manifest-x',
                'session-x',
                plan.Metadata_Comparison__c,
                plan.Id,
                new List<String>{ 'Foo' }
            );
        incoming.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_PROCESSING;
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(
                locked,
                incoming,
                incoming.statusRunId
            );
        System.assertEquals(false, result.success);
        System.assertEquals(
            ApexMergeArtifactStatusService.CODE_INVALID_STORED_STATUS,
            result.code
        );
    }

    @IsTest
    static void lockedPersist_rejectsPicklistJsonMismatch() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot queued =
            seedQueuedOnPlan(plan);
        Deployment_Plan__c locked = lockPlanForTest(plan.Id);
        locked.Latest_Apex_Merge_Artifact_Status__c =
            ApexMergeArtifactStatusService.OVERALL_PROCESSING;
        ApexMergeArtifactStatusService.StatusSnapshot processing =
            ApexMergeArtifactStatusService.deserialize(
                locked.Latest_Apex_Merge_Artifact_JSON__c
            );
        processing.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_PROCESSING;
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(
                locked,
                processing,
                queued.statusRunId
            );
        System.assertEquals(false, result.success);
        System.assertEquals(
            ApexMergeArtifactStatusService.CODE_STATUS_STORE_MISMATCH,
            result.code
        );
    }

    @IsTest
    static void lockedPersist_enforcesLifecycleTransition() {
        Deployment_Plan__c plan = createDeploymentPlan();
        ApexMergeArtifactStatusService.StatusSnapshot queued =
            seedQueuedOnPlan(plan);
        Deployment_Plan__c locked = lockPlanForTest(plan.Id);
        ApexMergeArtifactStatusService.StatusSnapshot completed =
            ApexMergeArtifactStatusService.deserialize(
                locked.Latest_Apex_Merge_Artifact_JSON__c
            );
        completed.overallStatus =
            ApexMergeArtifactStatusService.OVERALL_COMPLETED;
        completed.currentUnitIndex = 0;
        completed.completedAt = ApexMergeArtifactStatusService.nowIsoUtc();
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persist(
                locked,
                completed,
                queued.statusRunId
            );
        System.assertEquals(false, result.success);
        System.assertEquals('INVALID_REQUEST', result.code);
    }

    @IsTest
    static void persistNewQueuedRun_succeedsFromBlankState() {
        Deployment_Plan__c plan = createDeploymentPlan();
        Deployment_Plan__c locked = lockPlanForTest(plan.Id);
        ApexMergeArtifactStatusService.StatusSnapshot queued =
            ApexMergeArtifactStatusService.newQueuedSnapshot(
                'manifest-new',
                'session-new',
                plan.Metadata_Comparison__c,
                plan.Id,
                new List<String>{ 'Foo' }
            );
        ApexMergeArtifactStatusService.PersistResult result =
            ApexMergeArtifactStatusService.persistNewQueuedRun(
                locked,
                queued
            );
        System.assertEquals(true, result.success);
        System.assertEquals(
            ApexMergeArtifactStatusService.OVERALL_QUEUED,
            [
                SELECT Latest_Apex_Merge_Artifact_Status__c
                FROM Deployment_Plan__c
                WHERE Id = :plan.Id
                LIMIT 1
            ]
            .Latest_Apex_Merge_Artifact_Status__c
        );
    }

    private static Deployment_Plan__c lockPlanForTest(Id planId) {
        return [
            SELECT
                Id,
                Latest_Apex_Merge_Artifact_Status__c,
                Latest_Apex_Merge_Artifact_JSON__c
            FROM Deployment_Plan__c
            WHERE Id = :planId
            LIMIT 1
            FOR UPDATE
        ];
    }

    private static ApexMergeArtifactStatusService.StatusSnapshot seedQueuedOnPlan(
        Deployment_Plan__c plan
    ) {
        ApexMergeArtifactStatusService.StatusSnapshot snapshot =
            buildValidSnapshot(plan.Id, plan.Metadata_Comparison__c);
        snapshot.overallStatus = ApexMergeArtifactStatusService.OVERALL_QUEUED;
        snapshot.currentUnitIndex = -1;
        System.assertEquals(
            true,
            ApexMergeArtifactStatusService.persist(snapshot).success
        );
        return snapshot;
    }

    private static void assertInvalid(
        ApexMergeArtifactStatusService.StatusSnapshot snapshot,
        String validationHint
    ) {
        ApexMergeArtifactStatusService.ValidationResult result =
            ApexMergeArtifactStatusService.validate(snapshot);
        System.assertEquals(
            false,
            result.success,
            'Expected invalid snapshot (' +
                validationHint +
                '): ' +
                result.message
        );
        System.assertEquals('INVALID_REQUEST', result.code);
    }
}