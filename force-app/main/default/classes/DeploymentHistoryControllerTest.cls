/**
 * Rollback hydration read API — durable UI context from Deployment History + Snapshot.
 */
@IsTest
private class DeploymentHistoryControllerTest {

    private class Fixture {
        Connected_Org__c sourceOrg;
        Connected_Org__c destOrg;
        Connected_Org__c otherDestOrg;
        Metadata_Comparison__c comparisonA;
        Metadata_Comparison__c comparisonB;
        Deployment_Plan__c planA;
        Deployment_Plan__c planB;
        String destOrgKey;
        String otherDestOrgKey;
    }

    private static Fixture buildFixture() {
        Fixture fx = new Fixture();
        fx.sourceOrg = createOrg('SrcHydr', '00D000000000099');
        fx.destOrg = createOrg('DstHydr', '00D000000000001');
        fx.otherDestOrg = createOrg('DstOther', '00D000000000002');
        fx.destOrgKey = fx.destOrg.Org_ID__c;
        fx.otherDestOrgKey = fx.otherDestOrg.Org_ID__c;

        fx.comparisonA = createComparison(
            fx.sourceOrg.Id,
            fx.destOrg.Id,
            'Comparison A'
        );
        fx.comparisonB = createComparison(
            fx.sourceOrg.Id,
            fx.destOrg.Id,
            'Comparison B'
        );
        fx.planA = createPlan(
            fx.comparisonA.Id,
            fx.sourceOrg.Id,
            fx.destOrg.Id,
            'Plan A'
        );
        fx.planB = createPlan(
            fx.comparisonB.Id,
            fx.sourceOrg.Id,
            fx.destOrg.Id,
            'Plan B'
        );
        return fx;
    }

    private static Connected_Org__c createOrg(String suffix, String orgId) {
        Connected_Org__c orgRec = new Connected_Org__c(
            Name = 'Org ' + suffix,
            Display_Name__c = 'Org ' + suffix,
            Org_ID__c = orgId,
            Instance_URL__c = 'https://example' + suffix + '.my.salesforce.com',
            Refresh_Token__c = 'token-' + suffix,
            Active__c = true
        );
        insert orgRec;
        return orgRec;
    }

    private static Metadata_Comparison__c createComparison(
        Id sourceOrgId,
        Id destOrgId,
        String name
    ) {
        Metadata_Comparison__c comparison = new Metadata_Comparison__c(
            Name = name,
            Source_Org__c = sourceOrgId,
            Destination_Org__c = destOrgId
        );
        insert comparison;
        return comparison;
    }

    private static Deployment_Plan__c createPlan(
        Id comparisonId,
        Id sourceOrgId,
        Id destOrgId,
        String name
    ) {
        Deployment_Plan__c plan = new Deployment_Plan__c(
            Name = name,
            Metadata_Comparison__c = comparisonId,
            Source_Org__c = sourceOrgId,
            Destination_Org__c = destOrgId,
            Status__c = 'Draft',
            Selected_Count__c = 0,
            Dependency_Count__c = 0
        );
        insert plan;
        return plan;
    }

    private static void createSealedSnapshot(
        String snapshotId,
        Boolean rollbackEligible,
        String destinationOrgKey
    ) {
        DeploymentSnapshotService.createSnapshot(
            new Map<String, Object>{
                'snapshotId' => snapshotId,
                'deploymentId' => 'dep-' + snapshotId,
                'sourceOrgId' => '00D000000000099',
                'destinationOrgId' => destinationOrgKey,
                'sourceBranch' => 'feature/a',
                'destinationBranch' => 'uat',
                'schemaVersion' => '1',
                'snapshotVersion' => '1',
                'rollbackEligible' => rollbackEligible
            }
        );
        DeploymentSnapshotService.addMember(
            snapshotId,
            new Map<String, Object>{
                'metadataType' => 'ApexClass',
                'metadataName' => 'HydrateSvc',
                'filePath' => 'force-app/main/default/classes/HydrateSvc.cls',
                'changeClass' => 'MODIFIED',
                'existedBefore' => true
            }
        );
        DeploymentSnapshotService.sealSnapshot(snapshotId);
    }

    private static Deployment_History__c insertDeployHistory(
        Id comparisonId,
        Id planId,
        Id destinationOrgId,
        String snapshotId,
        String status,
        Datetime completedAt,
        String backendHistoryId
    ) {
        Deployment_History__c history = new Deployment_History__c(
            Metadata_Comparison__c = comparisonId,
            Deployment_Plan__c = planId,
            Destination_Org__c = destinationOrgId,
            Deployment_Mode__c = 'DEPLOY',
            Deployment_Status__c = status,
            Snapshot_Id__c = snapshotId,
            Backend_History_Id__c = backendHistoryId,
            Deployment_ID__c = '0Af' + snapshotId,
            Completed_At__c = completedAt
        );
        insert history;
        return history;
    }

    private static Map<String, Object> queryContext(
        Id comparisonId,
        Id planId,
        String destinationOrgKey
    ) {
        Test.startTest();
        Map<String, Object> result =
            DeploymentHistoryController.getLatestRollbackContext(
                comparisonId,
                planId,
                destinationOrgKey
            );
        Test.stopTest();
        return result;
    }

    @IsTest
    static void validRollbackContextAvailable() {
        Fixture fx = buildFixture();
        String snapshotId = 'snap-valid';
        createSealedSnapshot(snapshotId, true, fx.destOrgKey);
        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            snapshotId,
            'SUCCESS',
            Datetime.now(),
            'hist-valid'
        );

        Map<String, Object> ctx = queryContext(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrgKey
        );

        System.assertEquals(true, ctx.get('available'));
        System.assertEquals(true, ctx.get('deployCompleted'));
        System.assertEquals(true, ctx.get('rollbackSnapshotPersisted'));
        System.assertEquals(snapshotId, ctx.get('rollbackSnapshotId'));
        System.assertEquals('hist-valid', ctx.get('rollbackDeploymentId'));
        System.assertEquals(false, ctx.get('rollbackCompleted'));
    }

    @IsTest
    static void failedHistoryNotAvailable() {
        Fixture fx = buildFixture();
        String snapshotId = 'snap-failed';
        createSealedSnapshot(snapshotId, true, fx.destOrgKey);
        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            snapshotId,
            'FAILED',
            Datetime.now(),
            'hist-failed'
        );

        Map<String, Object> ctx = queryContext(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrgKey
        );
        System.assertEquals(false, ctx.get('available'));
    }

    @IsTest
    static void blockedHistoryNotAvailable() {
        Fixture fx = buildFixture();
        String snapshotId = 'snap-blocked';
        createSealedSnapshot(snapshotId, true, fx.destOrgKey);
        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            snapshotId,
            'BLOCKED',
            Datetime.now(),
            'hist-blocked'
        );

        Map<String, Object> ctx = queryContext(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrgKey
        );
        System.assertEquals(false, ctx.get('available'));
    }

    @IsTest
    static void missingSnapshotNotAvailable() {
        Fixture fx = buildFixture();
        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            'snap-missing-record',
            'SUCCESS',
            Datetime.now(),
            'hist-missing-snap'
        );

        Map<String, Object> ctx = queryContext(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrgKey
        );
        System.assertEquals(false, ctx.get('available'));
    }

    @IsTest
    static void unsealedSnapshotNotAvailable() {
        Fixture fx = buildFixture();
        String snapshotId = 'snap-unsealed';
        DeploymentSnapshotService.createSnapshot(
            new Map<String, Object>{
                'snapshotId' => snapshotId,
                'deploymentId' => 'dep-unsealed',
                'sourceOrgId' => '00D000000000099',
                'destinationOrgId' => fx.destOrgKey,
                'sourceBranch' => 'feature/a',
                'destinationBranch' => 'uat',
                'schemaVersion' => '1',
                'snapshotVersion' => '1',
                'rollbackEligible' => true
            }
        );
        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            snapshotId,
            'SUCCESS',
            Datetime.now(),
            'hist-unsealed'
        );

        Map<String, Object> ctx = queryContext(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrgKey
        );
        System.assertEquals(false, ctx.get('available'));
    }

    @IsTest
    static void notRollbackEligibleNotAvailable() {
        Fixture fx = buildFixture();
        String snapshotId = 'snap-ineligible';
        createSealedSnapshot(snapshotId, false, fx.destOrgKey);
        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            snapshotId,
            'SUCCESS',
            Datetime.now(),
            'hist-ineligible'
        );

        Map<String, Object> ctx = queryContext(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrgKey
        );
        System.assertEquals(false, ctx.get('available'));
    }

    @IsTest
    static void wrongComparisonNotAvailable() {
        Fixture fx = buildFixture();
        String snapshotId = 'snap-wrong-cmp';
        createSealedSnapshot(snapshotId, true, fx.destOrgKey);
        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            snapshotId,
            'SUCCESS',
            Datetime.now(),
            'hist-wrong-cmp'
        );

        Map<String, Object> ctx = queryContext(
            fx.comparisonB.Id,
            fx.planB.Id,
            fx.destOrgKey
        );
        System.assertEquals(false, ctx.get('available'));
    }

    @IsTest
    static void wrongPlanNotAvailable() {
        Fixture fx = buildFixture();
        Deployment_Plan__c otherPlan = createPlan(
            fx.comparisonA.Id,
            fx.sourceOrg.Id,
            fx.destOrg.Id,
            'Plan A2'
        );
        String snapshotId = 'snap-wrong-plan';
        createSealedSnapshot(snapshotId, true, fx.destOrgKey);
        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            snapshotId,
            'SUCCESS',
            Datetime.now(),
            'hist-wrong-plan'
        );

        Map<String, Object> ctx = queryContext(
            fx.comparisonA.Id,
            otherPlan.Id,
            fx.destOrgKey
        );
        System.assertEquals(false, ctx.get('available'));
    }

    @IsTest
    static void multipleDeploymentsReturnsLatest() {
        Fixture fx = buildFixture();
        String olderSnap = 'snap-older';
        String newerSnap = 'snap-newer';
        createSealedSnapshot(olderSnap, true, fx.destOrgKey);
        createSealedSnapshot(newerSnap, true, fx.destOrgKey);

        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            olderSnap,
            'SUCCESS',
            Datetime.now().addDays(-2),
            'hist-older'
        );
        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            newerSnap,
            'SUCCESS',
            Datetime.now(),
            'hist-newer'
        );

        Map<String, Object> ctx = queryContext(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrgKey
        );
        System.assertEquals(true, ctx.get('available'));
        System.assertEquals(newerSnap, ctx.get('rollbackSnapshotId'));
        System.assertEquals('hist-newer', ctx.get('rollbackDeploymentId'));
    }

    @IsTest
    static void rollbackAlreadySucceededHidesAction() {
        Fixture fx = buildFixture();
        String snapshotId = 'snap-rolled-back';
        createSealedSnapshot(snapshotId, true, fx.destOrgKey);
        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            snapshotId,
            'SUCCESS',
            Datetime.now(),
            'hist-rolled-back'
        );

        ControlPlaneResult createdOp = RollbackOperationService.createOperation(
            new Map<String, Object>{
                'operationId' => 'op-hydrate-done',
                'destinationOrgId' => fx.destOrgKey,
                'snapshotId' => snapshotId
            }
        );
        System.assertEquals(true, createdOp.success);

        ControlPlaneResult claimedOp =
            RollbackOperationService.claimOperation('op-hydrate-done');
        System.assertEquals(true, claimedOp.success);
        System.assertEquals(
            RollbackOperationService.IN_PROGRESS,
            ((Rollback_Operation__c) claimedOp.record).Status__c
        );

        ControlPlaneResult terminalOp = RollbackOperationService.markTerminal(
            'op-hydrate-done',
            RollbackOperationService.SUCCEEDED,
            RollbackOperationService.SUCCEEDED,
            'done'
        );
        System.assertEquals(true, terminalOp.success);
        System.assertEquals(
            RollbackOperationService.SUCCEEDED,
            ((Rollback_Operation__c) terminalOp.record).Status__c
        );

        Map<String, Object> ctx = queryContext(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrgKey
        );
        System.assertEquals(false, ctx.get('available'));
        System.assertEquals(true, ctx.get('deployCompleted'));
        System.assertEquals(true, ctx.get('rollbackCompleted'));
        System.assertEquals(true, ctx.get('rollbackSnapshotPersisted'));
        System.assertEquals(snapshotId, ctx.get('rollbackSnapshotId'));
        System.assertEquals('hist-rolled-back', ctx.get('rollbackDeploymentId'));
        System.assertNotEquals(null, ctx.get('rollbackCompletedAt'));
        System.assertEquals('done', ctx.get('rollbackSummaryMessage'));
        System.assertEquals(true, ((List<Object>) ctx.get('componentLabels')).size() > 0);
    }

    @IsTest
    static void differentDestinationNotAvailable() {
        Fixture fx = buildFixture();
        String snapshotId = 'snap-dest-scope';
        createSealedSnapshot(snapshotId, true, fx.destOrgKey);
        insertDeployHistory(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.destOrg.Id,
            snapshotId,
            'SUCCESS',
            Datetime.now(),
            'hist-dest-scope'
        );

        Map<String, Object> ctx = queryContext(
            fx.comparisonA.Id,
            fx.planA.Id,
            fx.otherDestOrgKey
        );
        System.assertEquals(false, ctx.get('available'));
    }
}