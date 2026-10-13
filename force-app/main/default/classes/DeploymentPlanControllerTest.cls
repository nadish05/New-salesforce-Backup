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

    private static Comparison_Result__c createComparisonResult(
        Id comparisonId,
        String fileName,
        String filePath,
        String metadataType,
        Boolean selected
    ) {
        Comparison_Result__c result = new Comparison_Result__c(
            Name = fileName,
            Metadata_Comparison__c = comparisonId,
            Metadata_Type__c = metadataType,
            File_Name__c = fileName,
            File_Path__c = filePath,
            Change_Type__c = 'MODIFIED',
            Selected_For_Deployment__c = selected
        );
        insert result;
        return result;
    }

    private static Deployment_Item__c createDeploymentItem(
        Id planId,
        Id comparisonResultId,
        String fileName,
        String filePath,
        String metadataType,
        String status
    ) {
        Deployment_Item__c item = new Deployment_Item__c(
            Deployment_Plan__c = planId,
            Comparison_Result__c = comparisonResultId,
            Metadata_Type__c = metadataType,
            File_Name__c = fileName,
            File_Path__c = filePath,
            Required__c = false,
            Selected_By_User__c = true,
            Deployment_Status__c = status
        );
        insert item;
        return item;
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
    static void testLargeDeploymentValidationPersistsAndHydrates() {
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

        // Valid JSON larger than Long Text inline limit (131072)
        String filler = '';
        while (filler.length() < 140000) {
            filler += 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
        }
        String largeJson =
            '{"deploymentReadiness":{"overallStatus":"READY"},"bulk":"' +
            filler +
            '"}';

        System.assert(
            largeJson.length() > 131072,
            'Test payload must exceed inline Long Text limit'
        );

        Test.startTest();
        Map<String, Object> saveResult =
            DeploymentPlanController.saveLatestDeploymentValidationSnapshot(
                plan.Id,
                largeJson,
                'READY'
            );
        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparison.Id
            );
        Test.stopTest();

        System.assertEquals(true, saveResult.get('success'));
        System.assertEquals('CHUNKED', saveResult.get('storageMode'));
        System.assertEquals(largeJson, state.latestDeploymentValidationJson);
        System.assertEquals('READY', state.latestDeploymentValidationStatus);
        System.assertNotEquals(
            null,
            state.latestDeploymentValidationCompletedAt
        );

        Deployment_Plan__c planAfter = [
            SELECT Latest_Deployment_Validation_JSON__c
            FROM Deployment_Plan__c
            WHERE Id = :plan.Id
        ];
        System.assertEquals(
            null,
            planAfter.Latest_Deployment_Validation_JSON__c,
            'Large payloads must not be truncated into the inline Long Text field'
        );

        Integer chunkCount = [
            SELECT COUNT()
            FROM Deployment_Plan_Snapshot__c
            WHERE Deployment_Plan__c = :plan.Id
            AND Snapshot_Type__c = 'DEPLOYMENT_VALIDATION'
            AND Snapshot_Status__c = 'COMPLETE'
        ];
        System.assert(chunkCount > 1, 'Large payload must create multiple chunks');
    }

    @IsTest
    static void testChunkedReplaceKeepsLatestOnly() {
        Connected_Org__c sourceOrg = createOrg('J1');
        Connected_Org__c destOrg = createOrg('J2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp ReplaceLarge');
        Deployment_Plan__c plan = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-ReplaceLarge'
        );

        String fillerA = '';
        while (fillerA.length() < 140000) {
            fillerA += 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
        }
        String jsonA = '{"run":1,"bulk":"' + fillerA + '"}';

        String fillerB = '';
        while (fillerB.length() < 140000) {
            fillerB += 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
        }
        String jsonB = '{"run":2,"bulk":"' + fillerB + '"}';

        DeploymentPlanController.saveLatestDeploymentValidationSnapshot(
            plan.Id,
            jsonA,
            'READY'
        );
        DeploymentPlanController.saveLatestDeploymentValidationSnapshot(
            plan.Id,
            jsonB,
            'READY'
        );

        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparison.Id
            );

        System.assertEquals(jsonB, state.latestDeploymentValidationJson);
        System.assert(
            state.latestDeploymentValidationJson.contains('"run":2'),
            'Latest execution must win'
        );
        System.assert(
            !state.latestDeploymentValidationJson.contains('"run":1'),
            'Prior large snapshot must not remain after replace'
        );
    }

    @IsTest
    static void testIncompleteChunksAreNotHydrated() {
        Connected_Org__c sourceOrg = createOrg('K1');
        Connected_Org__c destOrg = createOrg('K2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Incomplete');
        Deployment_Plan__c plan = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Incomplete'
        );

        insert new Deployment_Plan_Snapshot__c(
            Deployment_Plan__c = plan.Id,
            Snapshot_Type__c = 'DEPLOYMENT_VALIDATION',
            Snapshot_Status__c = 'COMPLETE',
            Snapshot_Key__c = 'partial-key-0001',
            Chunk_Number__c = 1,
            Total_Chunks__c = 2,
            Payload_Chunk__c = '{"incomplete":true',
            Completed_At__c = Datetime.now()
        );

        plan.Latest_Deployment_Validation_Status__c = 'READY';
        plan.Latest_Deploy_Val_Completed_At__c = Datetime.now();
        update plan;

        DeploymentPlanController.DeploymentPlanState state =
            DeploymentPlanController.getLatestDeploymentPlanState(
                comparison.Id
            );

        System.assertEquals(
            null,
            state.latestDeploymentValidationJson,
            'Partial chunk sets must never hydrate'
        );
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

    @IsTest
    static void testCreatePlanItemsStartPending() {
        Connected_Org__c sourceOrg = createOrg('L1');
        Connected_Org__c destOrg = createOrg('L2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Pending');
        Comparison_Result__c selected = createComparisonResult(
            comparison.Id,
            'AccountController.cls',
            'force-app/main/default/classes/AccountController.cls',
            'ApexClass',
            true
        );
        createComparisonResult(
            comparison.Id,
            'Ignored.cls',
            'force-app/main/default/classes/Ignored.cls',
            'ApexClass',
            false
        );

        Test.startTest();
        Id planId =
            DeploymentPlanController.createDeploymentPlan(comparison.Id);
        List<Deployment_Item__c> items =
            DeploymentPlanController.getLatestDeploymentItems(comparison.Id);
        Test.stopTest();

        System.assertEquals(1, items.size());
        System.assertEquals(planId, items[0].Deployment_Plan__c);
        System.assertEquals(selected.Id, items[0].Comparison_Result__c);
        System.assertEquals('Pending', items[0].Deployment_Status__c);
    }

    @IsTest
    static void testLatestPlanItemReadIsIsolated() {
        Connected_Org__c sourceOrg = createOrg('M1');
        Connected_Org__c destOrg = createOrg('M2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Plan Isolation');
        Comparison_Result__c result = createComparisonResult(
            comparison.Id,
            'Isolated.cls',
            'force-app/main/default/classes/Isolated.cls',
            'ApexClass',
            true
        );
        Deployment_Plan__c planA = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-A-Lifecycle'
        );
        Test.setCreatedDate(planA.Id, Datetime.now().addMinutes(-5));
        createDeploymentItem(
            planA.Id,
            result.Id,
            result.File_Name__c,
            result.File_Path__c,
            result.Metadata_Type__c,
            'Validated'
        );
        Deployment_Plan__c planB = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-B-Lifecycle'
        );
        createDeploymentItem(
            planB.Id,
            result.Id,
            result.File_Name__c,
            result.File_Path__c,
            result.Metadata_Type__c,
            'Pending'
        );

        List<Deployment_Item__c> items =
            DeploymentPlanController.getLatestDeploymentItems(comparison.Id);

        System.assertEquals(1, items.size());
        System.assertEquals(planB.Id, items[0].Deployment_Plan__c);
        System.assertEquals('Pending', items[0].Deployment_Status__c);
    }

    @IsTest
    static void testComparisonWideLifecycleRead() {
        Connected_Org__c sourceOrg = createOrg('M5');
        Connected_Org__c destOrg = createOrg('M6');
        Metadata_Comparison__c comparisonA =
            createComparison(sourceOrg, destOrg, 'Cmp Lifecycle A');
        Metadata_Comparison__c comparisonB =
            createComparison(sourceOrg, destOrg, 'Cmp Lifecycle B');

        Comparison_Result__c account = createComparisonResult(
            comparisonA.Id,
            'Account.cls',
            'force-app/main/default/classes/Account.cls',
            'ApexClass',
            true
        );
        Comparison_Result__c contact = createComparisonResult(
            comparisonA.Id,
            'Contact.cls',
            'force-app/main/default/classes/Contact.cls',
            'ApexClass',
            true
        );
        Comparison_Result__c opportunity = createComparisonResult(
            comparisonA.Id,
            'Opportunity.cls',
            'force-app/main/default/classes/Opportunity.cls',
            'ApexClass',
            true
        );
        Comparison_Result__c sourceFile = createComparisonResult(
            comparisonA.Id,
            'Foo.cls',
            'force-app/main/default/classes/Foo.cls',
            'ApexClass',
            true
        );
        Comparison_Result__c metaFile = createComparisonResult(
            comparisonA.Id,
            'Foo.cls-meta.xml',
            'force-app/main/default/classes/Foo.cls-meta.xml',
            'ApexClass',
            true
        );
        Comparison_Result__c otherComparisonAccount = createComparisonResult(
            comparisonB.Id,
            'Account.cls',
            account.File_Path__c,
            'ApexClass',
            true
        );

        Deployment_Plan__c planA1 = createPlan(
            comparisonA.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-A-1'
        );
        Deployment_Item__c accountValidated = createDeploymentItem(
            planA1.Id,
            account.Id,
            account.File_Name__c,
            account.File_Path__c,
            account.Metadata_Type__c,
            'Validated'
        );
        Deployment_Item__c contactValidated = createDeploymentItem(
            planA1.Id,
            contact.Id,
            contact.File_Name__c,
            contact.File_Path__c,
            contact.Metadata_Type__c,
            'Validated'
        );
        Deployment_Item__c sourceValidated = createDeploymentItem(
            planA1.Id,
            sourceFile.Id,
            sourceFile.File_Name__c,
            sourceFile.File_Path__c,
            sourceFile.Metadata_Type__c,
            'Validated'
        );

        Deployment_Plan__c planA2 = createPlan(
            comparisonA.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-A-2'
        );
        Deployment_Item__c accountDeployed = createDeploymentItem(
            planA2.Id,
            account.Id,
            account.File_Name__c,
            account.File_Path__c,
            account.Metadata_Type__c,
            'Deployed'
        );
        Deployment_Item__c opportunityValidated = createDeploymentItem(
            planA2.Id,
            opportunity.Id,
            opportunity.File_Name__c,
            opportunity.File_Path__c,
            opportunity.Metadata_Type__c,
            'Validated'
        );
        Deployment_Item__c metaPending = createDeploymentItem(
            planA2.Id,
            metaFile.Id,
            metaFile.File_Name__c,
            metaFile.File_Path__c,
            metaFile.Metadata_Type__c,
            'Pending'
        );

        Deployment_Plan__c planB = createPlan(
            comparisonB.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-B-1'
        );
        Deployment_Item__c otherComparisonDeployed = createDeploymentItem(
            planB.Id,
            otherComparisonAccount.Id,
            otherComparisonAccount.File_Name__c,
            otherComparisonAccount.File_Path__c,
            otherComparisonAccount.Metadata_Type__c,
            'Deployed'
        );

        Test.startTest();
        List<Deployment_Item__c> lifecycleItems =
            DeploymentPlanController.getDeploymentLifecycleItems(
                comparisonA.Id
            );
        Test.stopTest();

        Set<Id> returnedIds = new Set<Id>();
        Set<String> returnedPaths = new Set<String>();
        for (Deployment_Item__c item : lifecycleItems) {
            returnedIds.add(item.Id);
            returnedPaths.add(item.File_Path__c);
        }

        System.assertEquals(5, lifecycleItems.size());
        System.assert(returnedIds.contains(accountValidated.Id));
        System.assert(returnedIds.contains(contactValidated.Id));
        System.assert(returnedIds.contains(sourceValidated.Id));
        System.assert(returnedIds.contains(accountDeployed.Id));
        System.assert(returnedIds.contains(opportunityValidated.Id));
        System.assert(
            !returnedIds.contains(metaPending.Id),
            'Pending source metadata must not produce a lifecycle badge'
        );
        System.assert(
            !returnedIds.contains(otherComparisonDeployed.Id),
            'Successful items from another comparison must not leak'
        );
        System.assert(
            returnedPaths.contains(contact.File_Path__c),
            'A newer plan must not hide an older successful file'
        );
        System.assert(
            !returnedPaths.contains(metaFile.File_Path__c),
            'The .meta.xml path remains independent'
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Deployment_Item__c
                WHERE Id IN :returnedIds
                AND Deployment_Plan__r.Metadata_Comparison__c != :comparisonA.Id
            ],
            'Items from another comparison must never leak'
        );
    }

    @IsTest
    static void testOlderPlanCannotReceiveLifecycleUpdate() {
        Connected_Org__c sourceOrg = createOrg('M3');
        Connected_Org__c destOrg = createOrg('M4');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Stale Plan');
        Comparison_Result__c result = createComparisonResult(
            comparison.Id,
            'Stale.cls',
            'force-app/main/default/classes/Stale.cls',
            'ApexClass',
            true
        );
        Deployment_Plan__c planA = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Stale-A'
        );
        Test.setCreatedDate(planA.Id, Datetime.now().addMinutes(-5));
        createDeploymentItem(
            planA.Id,
            result.Id,
            result.File_Name__c,
            result.File_Path__c,
            result.Metadata_Type__c,
            'Pending'
        );
        Deployment_Plan__c planB = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Stale-B'
        );
        createDeploymentItem(
            planB.Id,
            result.Id,
            result.File_Name__c,
            result.File_Path__c,
            result.Metadata_Type__c,
            'Pending'
        );

        Boolean rejected = false;
        Test.startTest();
        try {
            DeploymentPlanController.updateLatestDeploymentItemStatuses(
                comparison.Id,
                planA.Id,
                JSON.serialize(new List<Object>{
                    new Map<String, Object>{
                        'filePath' => result.File_Path__c
                    }
                }),
                'Validated'
            );
        } catch (AuraHandledException error) {
            rejected = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            rejected,
            'A response for an older plan must be rejected'
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Deployment_Item__c
                WHERE Deployment_Status__c = 'Validated'
            ]
        );
    }

    @IsTest
    static void testValidatedUpdateUsesPathAndIgnoresUnmatchedMembers() {
        Connected_Org__c sourceOrg = createOrg('N1');
        Connected_Org__c destOrg = createOrg('N2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Validate Match');
        Comparison_Result__c jsResult = createComparisonResult(
            comparison.Id,
            'sample.js',
            'force-app/main/default/lwc/sample/sample.js',
            'LWC',
            true
        );
        Comparison_Result__c htmlResult = createComparisonResult(
            comparison.Id,
            'sample.html',
            'force-app/main/default/lwc/sample/sample.html',
            'LWC',
            true
        );
        Deployment_Plan__c plan = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Validate-Match'
        );
        createDeploymentItem(
            plan.Id,
            jsResult.Id,
            jsResult.File_Name__c,
            jsResult.File_Path__c,
            jsResult.Metadata_Type__c,
            'Pending'
        );
        createDeploymentItem(
            plan.Id,
            htmlResult.Id,
            htmlResult.File_Name__c,
            htmlResult.File_Path__c,
            htmlResult.Metadata_Type__c,
            'Pending'
        );

        String membersJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'filePath' => jsResult.File_Path__c,
                'name' => jsResult.File_Name__c,
                'metadataType' => jsResult.Metadata_Type__c
            },
            new Map<String, Object>{
                'filePath' => 'force-app/main/default/classes/Unmatched.cls',
                'name' => 'Unmatched.cls',
                'metadataType' => 'ApexClass'
            }
        });

        Test.startTest();
        List<Deployment_Item__c> items =
            DeploymentPlanController.updateLatestDeploymentItemStatuses(
                comparison.Id,
                plan.Id,
                membersJson,
                'Validated'
            );
        Test.stopTest();

        Map<String, String> statusByPath = new Map<String, String>();
        for (Deployment_Item__c item : items) {
            statusByPath.put(item.File_Path__c, item.Deployment_Status__c);
        }
        System.assertEquals(
            'Validated',
            statusByPath.get(jsResult.File_Path__c)
        );
        System.assertEquals(
            'Pending',
            statusByPath.get(htmlResult.File_Path__c),
            'LWC files must remain independently matched'
        );
    }

    @IsTest
    static void testFileNameAndTypeFallbackDoesNotConfuseMetaFile() {
        Connected_Org__c sourceOrg = createOrg('O1');
        Connected_Org__c destOrg = createOrg('O2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Fallback');
        Comparison_Result__c classResult = createComparisonResult(
            comparison.Id,
            'Foo.cls',
            'force-app/main/default/classes/Foo.cls',
            'ApexClass',
            true
        );
        Comparison_Result__c metaResult = createComparisonResult(
            comparison.Id,
            'Foo.cls-meta.xml',
            'force-app/main/default/classes/Foo.cls-meta.xml',
            'ApexClass',
            true
        );
        Deployment_Plan__c plan = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Fallback'
        );
        createDeploymentItem(
            plan.Id,
            classResult.Id,
            classResult.File_Name__c,
            classResult.File_Path__c,
            classResult.Metadata_Type__c,
            'Pending'
        );
        createDeploymentItem(
            plan.Id,
            metaResult.Id,
            metaResult.File_Name__c,
            metaResult.File_Path__c,
            metaResult.Metadata_Type__c,
            'Pending'
        );

        String membersJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'name' => classResult.File_Name__c,
                'metadataType' => classResult.Metadata_Type__c
            }
        });

        List<Deployment_Item__c> items =
            DeploymentPlanController.updateLatestDeploymentItemStatuses(
                comparison.Id,
                plan.Id,
                membersJson,
                'Validated'
            );

        Map<String, String> statusByName = new Map<String, String>();
        for (Deployment_Item__c item : items) {
            statusByName.put(item.File_Name__c, item.Deployment_Status__c);
        }
        System.assertEquals('Validated', statusByName.get('Foo.cls'));
        System.assertEquals('Pending', statusByName.get('Foo.cls-meta.xml'));
    }

    @IsTest
    static void testFailedValidationResetsValidatedButPreservesDeployed() {
        Connected_Org__c sourceOrg = createOrg('P1');
        Connected_Org__c destOrg = createOrg('P2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Reset');
        Comparison_Result__c validatedResult = createComparisonResult(
            comparison.Id,
            'Validated.cls',
            'force-app/main/default/classes/Validated.cls',
            'ApexClass',
            true
        );
        Comparison_Result__c deployedResult = createComparisonResult(
            comparison.Id,
            'Deployed.cls',
            'force-app/main/default/classes/Deployed.cls',
            'ApexClass',
            true
        );
        Deployment_Plan__c plan = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Reset'
        );
        createDeploymentItem(
            plan.Id,
            validatedResult.Id,
            validatedResult.File_Name__c,
            validatedResult.File_Path__c,
            validatedResult.Metadata_Type__c,
            'Validated'
        );
        createDeploymentItem(
            plan.Id,
            deployedResult.Id,
            deployedResult.File_Name__c,
            deployedResult.File_Path__c,
            deployedResult.Metadata_Type__c,
            'Deployed'
        );
        String membersJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'filePath' => validatedResult.File_Path__c
            },
            new Map<String, Object>{
                'filePath' => deployedResult.File_Path__c
            }
        });

        List<Deployment_Item__c> items =
            DeploymentPlanController.updateLatestDeploymentItemStatuses(
                comparison.Id,
                plan.Id,
                membersJson,
                'Pending'
            );

        Map<String, String> statusByPath = new Map<String, String>();
        for (Deployment_Item__c item : items) {
            statusByPath.put(item.File_Path__c, item.Deployment_Status__c);
        }
        System.assertEquals(
            'Pending',
            statusByPath.get(validatedResult.File_Path__c)
        );
        System.assertEquals(
            'Deployed',
            statusByPath.get(deployedResult.File_Path__c)
        );
    }

    @IsTest
    static void testSuccessfulDeploymentMarksOnlyMatchingLatestPlanItem() {
        Connected_Org__c sourceOrg = createOrg('Q1');
        Connected_Org__c destOrg = createOrg('Q2');
        Metadata_Comparison__c comparison =
            createComparison(sourceOrg, destOrg, 'Cmp Deploy');
        Comparison_Result__c included = createComparisonResult(
            comparison.Id,
            'Included.cls',
            'force-app/main/default/classes/Included.cls',
            'ApexClass',
            true
        );
        Comparison_Result__c excluded = createComparisonResult(
            comparison.Id,
            'Excluded.cls',
            'force-app/main/default/classes/Excluded.cls',
            'ApexClass',
            true
        );
        Deployment_Plan__c plan = createPlan(
            comparison.Id,
            sourceOrg.Id,
            destOrg.Id,
            'DP-Deploy'
        );
        createDeploymentItem(
            plan.Id,
            included.Id,
            included.File_Name__c,
            included.File_Path__c,
            included.Metadata_Type__c,
            'Validated'
        );
        createDeploymentItem(
            plan.Id,
            excluded.Id,
            excluded.File_Name__c,
            excluded.File_Path__c,
            excluded.Metadata_Type__c,
            'Validated'
        );

        List<Deployment_Item__c> items =
            DeploymentPlanController.updateLatestDeploymentItemStatuses(
                comparison.Id,
                plan.Id,
                JSON.serialize(new List<Object>{
                    new Map<String, Object>{
                        'filePath' => included.File_Path__c
                    }
                }),
                'Deployed'
            );

        Map<String, String> statusByPath = new Map<String, String>();
        for (Deployment_Item__c item : items) {
            statusByPath.put(item.File_Path__c, item.Deployment_Status__c);
        }
        System.assertEquals(
            'Deployed',
            statusByPath.get(included.File_Path__c)
        );
        System.assertEquals(
            'Validated',
            statusByPath.get(excluded.File_Path__c)
        );
    }
}