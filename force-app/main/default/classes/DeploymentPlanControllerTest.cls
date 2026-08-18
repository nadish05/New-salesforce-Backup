/**
 * Unit tests for Deployment Plan create/read and Stage 4/5 snapshot persistence.
 */
@IsTest
private class DeploymentPlanControllerTest {

    private static Connected_Org__c createOrg(String nameSuffix) {
        Connected_Org__c orgRec = new Connected_Org__c(
            Name = 'Org ' + nameSuffix,
            Display_Name__c = 'Org ' + nameSuffix,
            Org_ID__c = '00D' + nameSuffix,
            Instance_URL__c = 'https://example' + nameSuffix + '.my.salesforce.com',
            Refresh_Token__c = 'token-' + nameSuffix,
            Active__c = true
        );
        insert orgRec;
        return orgRec;
    }

    private static Metadata_Comparison__c createComparison(
        Connected_Org__c sourceOrg,
        Connected_Org__c destOrg,
        String name
    ) {
        Metadata_Comparison__c comparison = new Metadata_Comparison__c(
            Name = name,
            Source_Org__c = sourceOrg.Id,
            Destination_Org__c = destOrg.Id
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

    @IsTest
    static void testGetLatestDeploymentPlanState_NoPlan() {
        Connected_Org__c sourceOrg = createOrg('A1');
        Connected_Org__c destOrg = createOrg('A2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Empty');

        Test.startTest();
        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparison.Id
            );
        Test.stopTest();

        System.assertEquals(null, state.deploymentPlanId);
        System.assertEquals(null, state.latestReviewJson);
        System.assertEquals(null, state.latestSourceValidationJson);
        System.assertEquals(null, state.latestDeploymentValidationJson);
    }

    @IsTest
    static void testGetLatestDeploymentPlanState_NullComparison() {
        Test.startTest();
        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(null);
        Id planId = DeploymentPlanController.getLatestDeploymentPlanId(null);
        Test.stopTest();

        System.assertEquals(null, state.deploymentPlanId);
        System.assertEquals(null, planId);
    }

    @IsTest
    static void testLatestPlanSelectedByCreatedDateDesc() {
        Connected_Org__c sourceOrg = createOrg('B1');
        Connected_Org__c destOrg = createOrg('B2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Multi');

        Deployment_Plan__c older = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Older'
        );
        // Ensure distinct CreatedDate ordering in the same transaction when possible
        Deployment_Plan__c newer = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Newer'
        );

        Test.startTest();
        Id latestId =
            DeploymentPlanController.getLatestDeploymentPlanId(comparison.Id);
        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparison.Id
            );
        Test.stopTest();

        System.assertEquals(newer.Id, latestId);
        System.assertEquals(newer.Id, state.deploymentPlanId);
        System.assertNotEquals(older.Id, state.deploymentPlanId);
    }

    @IsTest
    static void testComparisonsDoNotCrossContaminate() {
        Connected_Org__c sourceOrg = createOrg('C1');
        Connected_Org__c destOrg = createOrg('C2');
        Metadata_Comparison__c comparisonA =
            createComparison(sourceOrg, destOrg, 'Cmp A');
        Metadata_Comparison__c comparisonB =
            createComparison(sourceOrg, destOrg, 'Cmp B');

        Deployment_Plan__c planA = createPlan(
            comparisonA.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-A'
        );
        Deployment_Plan__c planB = createPlan(
            comparisonB.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-B'
        );

        Map<String, Object> saveA =
            DeploymentPlanController.saveLatestReviewSnapshot(
                planA.Id,
                '{"comparison":"A","deploymentReview":[]}',
                'READY'
            );
        Map<String, Object> saveB =
            DeploymentPlanController.saveLatestReviewSnapshot(
                planB.Id,
                '{"comparison":"B","deploymentReview":[]}',
                'READY'
            );

        System.assertEquals(true, saveA.get('success'));
        System.assertEquals(true, saveB.get('success'));

        Test.startTest();
        DeploymentPlanController.DeploymentPlanState stateA =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparisonA.Id
            );
        DeploymentPlanController.DeploymentPlanState stateB =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparisonB.Id
            );
        Test.stopTest();

        System.assertEquals(planA.Id, stateA.deploymentPlanId);
        System.assertEquals(planB.Id, stateB.deploymentPlanId);
        System.assert(
            stateA.latestReviewJson.contains('"comparison":"A"'),
            'Comparison A must not receive B review JSON'
        );
        System.assert(
            stateB.latestReviewJson.contains('"comparison":"B"'),
            'Comparison B must not receive A review JSON'
        );
    }

    @IsTest
    static void testSaveAndReadReviewSnapshot() {
        Connected_Org__c sourceOrg = createOrg('D1');
        Connected_Org__c destOrg = createOrg('D2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Review');
        Deployment_Plan__c plan = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Review'
        );

        String reviewJson =
            '{"success":true,"deploymentReview":[{"metadataName":"Foo","status":"Ready"}]}';

        Test.startTest();
        Map<String, Object> saveResult =
            DeploymentPlanController.saveLatestReviewSnapshot(
                plan.Id,
                reviewJson,
                'Ready'
            );
        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparison.Id
            );
        Test.stopTest();

        System.assertEquals(true, saveResult.get('success'));
        System.assertEquals(reviewJson, state.latestReviewJson);
        System.assertEquals('Ready', state.latestReviewStatus);
        System.assertNotEquals(null, state.latestReviewCompletedAt);
        System.assertEquals(null, state.latestSourceValidationJson);
        System.assertEquals(null, state.latestDeploymentValidationJson);
    }

    @IsTest
    static void testSaveAndReadSourceValidationSnapshot() {
        Connected_Org__c sourceOrg = createOrg('E1');
        Connected_Org__c destOrg = createOrg('E2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Source');
        Deployment_Plan__c plan = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Source'
        );

        String sourceJson =
            '{"sourceValidation":{"overallStatus":"PASS"},"coverageValidation":{"overallStatus":"PASS"}}';

        Test.startTest();
        Map<String, Object> saveResult =
            DeploymentPlanController.saveLatestSourceValidationSnapshot(
                plan.Id,
                sourceJson,
                'PASS'
            );
        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparison.Id
            );
        Test.stopTest();

        System.assertEquals(true, saveResult.get('success'));
        System.assertEquals(sourceJson, state.latestSourceValidationJson);
        System.assertEquals('PASS', state.latestSourceValidationStatus);
        System.assertNotEquals(null, state.latestSourceValidationCompletedAt);
    }

    @IsTest
    static void testSaveAndReadDeploymentValidationSnapshot() {
        Connected_Org__c sourceOrg = createOrg('F1');
        Connected_Org__c destOrg = createOrg('F2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp DeployVal');
        Deployment_Plan__c plan = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-DeployVal'
        );

        String validationJson =
            '{"deploymentReadiness":{"overallStatus":"READY","canDeploy":true}}';

        Test.startTest();
        Map<String, Object> saveResult =
            DeploymentPlanController.saveLatestDeploymentValidationSnapshot(
                plan.Id,
                validationJson,
                'READY'
            );
        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparison.Id
            );
        Test.stopTest();

        System.assertEquals(true, saveResult.get('success'));
        System.assertEquals(
            validationJson,
            state.latestDeploymentValidationJson
        );
        System.assertEquals('READY', state.latestDeploymentValidationStatus);
        System.assertNotEquals(
            null,
            state.latestDeploymentValidationCompletedAt
        );
    }

    @IsTest
    static void testOverwriteKeepsLatestExecutionOnly() {
        Connected_Org__c sourceOrg = createOrg('G1');
        Connected_Org__c destOrg = createOrg('G2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Overwrite');
        Deployment_Plan__c plan = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Overwrite'
        );

        DeploymentPlanController.saveLatestReviewSnapshot(
            plan.Id,
            '{"run":1}',
            'Ready'
        );
        DeploymentPlanController.saveLatestReviewSnapshot(
            plan.Id,
            '{"run":2}',
            'Ready'
        );

        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparison.Id
            );

        System.assertEquals('{"run":2}', state.latestReviewJson);
    }

    @IsTest
    static void testNewerPlanDoesNotInheritOlderSnapshots() {
        Connected_Org__c sourceOrg = createOrg('H1');
        Connected_Org__c destOrg = createOrg('H2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Isolate');

        Deployment_Plan__c plan1 = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-1'
        );
        DeploymentPlanController.saveLatestReviewSnapshot(
            plan1.Id,
            '{"plan":1,"review":true}',
            'Ready'
        );
        DeploymentPlanController.saveLatestDeploymentValidationSnapshot(
            plan1.Id,
            '{"plan":1,"validation":true}',
            'READY'
        );

        Deployment_Plan__c plan2 = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-2'
        );

        Test.startTest();
        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparison.Id
            );
        Test.stopTest();

        System.assertEquals(plan2.Id, state.deploymentPlanId);
        System.assertEquals(
            null,
            state.latestReviewJson,
            'New plan must start with empty Review snapshot'
        );
        System.assertEquals(
            null,
            state.latestDeploymentValidationJson,
            'New plan must not inherit older Validation snapshot'
        );
    }

    @IsTest
    static void testSaveRejectsOversizedJsonWithoutTruncation() {
        Connected_Org__c sourceOrg = createOrg('I1');
        Connected_Org__c destOrg = createOrg('I2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Size');
        Deployment_Plan__c plan = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Size'
        );

        // Build > 131072 chars without String.repeat for broad API compatibility
        String oversized = '';
        while (oversized.length() <= 131072) {
            oversized += 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
        }

        Test.startTest();
        Map<String, Object> saveResult =
            DeploymentPlanController.saveLatestReviewSnapshot(
                plan.Id,
                oversized,
                'Ready'
            );
        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparison.Id
            );
        Test.stopTest();

        System.assertEquals(false, saveResult.get('success'));
        System.assert(
            String.valueOf(saveResult.get('message')).contains('131072'),
            'Must report Long Text limit without saving'
        );
        System.assertEquals(null, state.latestReviewJson);
    }

    @IsTest
    static void testSaveRequiresPlanIdAndJson() {
        Map<String, Object> missingPlan =
            DeploymentPlanController.saveLatestReviewSnapshot(
                null,
                '{"ok":true}',
                'Ready'
            );
        Map<String, Object> missingJson =
            DeploymentPlanController.saveLatestSourceValidationSnapshot(
                UserInfo.getUserId(),
                '',
                'PASS'
            );

        System.assertEquals(false, missingPlan.get('success'));
        System.assertEquals(false, missingJson.get('success'));
    }
}