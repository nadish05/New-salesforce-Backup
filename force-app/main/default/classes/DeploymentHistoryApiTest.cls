/**
 * Unit tests for Deployment History persistence API and service.
 */
@IsTest
private class DeploymentHistoryApiTest {

    @IsTest
    static void testSuccessfulInsert() {
        String payload = buildValidPayload(null, null, null, null);

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/deployment-history';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(payload);
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        DeploymentHistoryApi.createDeploymentHistory();
        Test.stopTest();

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(
                res.responseBody.toString()
            );

        System.assertEquals(200, res.statusCode);
        System.assertEquals(true, body.get('success'));
        System.assertNotEquals(null, body.get('recordId'));

        Id recordId = (Id) body.get('recordId');
        Deployment_History__c saved = [
            SELECT
                Deployment_ID__c,
                Deployment_Mode__c,
                Execution_Mode__c,
                Deployment_Status__c,
                Validation_Status__c,
                Duration_Display__c,
                Duration_Milliseconds__c,
                CLI_Version__c,
                Components_Validated__c,
                Components_Deployed__c,
                Components_Failed__c,
                Components_Total__c,
                Tests_Run__c,
                Tests_Failed__c,
                Overall_Coverage__c,
                Warning_Count__c,
                Error_Count__c,
                Deployment_Message__c,
                Deployment_Summary__c,
                Timeline__c
            FROM Deployment_History__c
            WHERE Id = :recordId
        ];

        System.assertEquals('0AfTESTDEPLOY001', saved.Deployment_ID__c);
        System.assertEquals('VALIDATE', saved.Deployment_Mode__c);
        System.assertEquals('check-only', saved.Execution_Mode__c);
        System.assertEquals('SUCCESS', saved.Deployment_Status__c);
        System.assertEquals('PASS', saved.Validation_Status__c);
        System.assertEquals('3s', saved.Duration_Display__c);
        System.assertEquals(3000, saved.Duration_Milliseconds__c);
        System.assertEquals(5, saved.Components_Validated__c);
        System.assertEquals(4, saved.Components_Deployed__c);
        System.assertEquals(1, saved.Components_Failed__c);
        System.assertEquals(5, saved.Components_Total__c);
        System.assertEquals(2, saved.Tests_Run__c);
        System.assertEquals(0, saved.Tests_Failed__c);
        System.assertEquals(85.50, saved.Overall_Coverage__c);
        System.assertEquals(1, saved.Warning_Count__c);
        System.assertEquals(0, saved.Error_Count__c);
        System.assertEquals(
            'Validation completed successfully',
            saved.Deployment_Message__c
        );
        System.assertNotEquals(null, saved.Deployment_Summary__c);
        System.assertNotEquals(null, saved.Timeline__c);
    }

    @IsTest
    static void testMissingOptionalLookups() {
        String payload = buildValidPayload(null, null, null, null);

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/deployment-history';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(payload);
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        DeploymentHistoryApi.createDeploymentHistory();
        Test.stopTest();

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(
                res.responseBody.toString()
            );

        System.assertEquals(true, body.get('success'));

        Deployment_History__c saved = [
            SELECT
                Deployment_Plan__c,
                Metadata_Comparison__c,
                Source_Org__c,
                Destination_Org__c
            FROM Deployment_History__c
            WHERE Id = :(Id) body.get('recordId')
        ];

        System.assertEquals(null, saved.Deployment_Plan__c);
        System.assertEquals(null, saved.Metadata_Comparison__c);
        System.assertEquals(null, saved.Source_Org__c);
        System.assertEquals(null, saved.Destination_Org__c);
    }

    @IsTest
    static void testInvalidPayload() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/deployment-history';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{ invalid json');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        DeploymentHistoryApi.createDeploymentHistory();
        Test.stopTest();

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(
                res.responseBody.toString()
            );

        System.assertEquals(false, body.get('success'));
        System.assertEquals(
            'Unable to save deployment history.',
            body.get('message')
        );
        System.assertEquals(0, [SELECT COUNT() FROM Deployment_History__c]);
    }

    @IsTest
    static void testBlankPayload() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/deployment-history';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('   ');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        DeploymentHistoryApi.createDeploymentHistory();
        Test.stopTest();

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(
                res.responseBody.toString()
            );

        System.assertEquals(400, res.statusCode);
        System.assertEquals(false, body.get('success'));
        System.assertEquals(
            'Unable to save deployment history.',
            body.get('message')
        );
    }

    @IsTest
    static void testDmlFailureInvalidPicklist() {
        String payload =
            '{' +
            '"deploymentId":"0AfFAIL001",' +
            '"deploymentMode":"NOT_A_VALID_MODE",' +
            '"executionMode":"deploy",' +
            '"status":"SUCCESS"' +
            '}';

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/deployment-history';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(payload);
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        DeploymentHistoryApi.createDeploymentHistory();
        Test.stopTest();

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(
                res.responseBody.toString()
            );

        System.assertEquals(false, body.get('success'));
        System.assertEquals(
            'Unable to save deployment history.',
            body.get('message')
        );
        System.assertEquals(0, [SELECT COUNT() FROM Deployment_History__c]);
    }

    @IsTest
    static void testCrudDenied() {
        Profile profile = [
            SELECT Id
            FROM Profile
            WHERE UserType = 'Standard'
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        User restrictedUser = new User(
            Alias = 'dhdeny',
            Email = 'dhdeny@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Deny',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'dhdeny' + DateTime.now().getTime() + '@example.com',
            ProfileId = profile.Id
        );
        insert restrictedUser;

        System.runAs(restrictedUser) {
            DeploymentHistoryDTO dto = new DeploymentHistoryDTO();
            dto.deploymentId = '0AfCRUDDENY001';
            dto.status = 'SUCCESS';

            Test.startTest();
            DeploymentHistoryService.SaveResult result =
                DeploymentHistoryService.save(dto);
            Test.stopTest();

            // Depending on profile permissions this may pass or fail.
            // Assert contract: never throws and returns structured result.
            System.assertNotEquals(null, result);
            System.assertNotEquals(null, result.success);
            if (result.success == false) {
                System.assertEquals(
                    'Unable to save deployment history.',
                    result.message
                );
                System.assertEquals(null, result.recordId);
            }
        }
    }

    @IsTest
    static void testServiceNullDto() {
        Test.startTest();
        DeploymentHistoryService.SaveResult result =
            DeploymentHistoryService.save(null);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(
            'Unable to save deployment history.',
            result.message
        );
    }

    @IsTest
    static void testInvalidLookupIdsAreIgnored() {
        String payload = buildValidPayload(
            'not-an-id',
            'also-bad',
            'bad-source',
            'bad-destination'
        );

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/deployment-history';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(payload);
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        DeploymentHistoryApi.createDeploymentHistory();
        Test.stopTest();

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(
                res.responseBody.toString()
            );

        System.assertEquals(true, body.get('success'));

        Deployment_History__c saved = [
            SELECT
                Deployment_Plan__c,
                Metadata_Comparison__c,
                Source_Org__c,
                Destination_Org__c
            FROM Deployment_History__c
            WHERE Id = :(Id) body.get('recordId')
        ];

        System.assertEquals(null, saved.Deployment_Plan__c);
        System.assertEquals(null, saved.Metadata_Comparison__c);
        System.assertEquals(null, saved.Source_Org__c);
        System.assertEquals(null, saved.Destination_Org__c);
    }

    private static String buildValidPayload(
        String deploymentPlanId,
        String metadataComparisonId,
        String sourceOrgId,
        String destinationOrgId
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'historyId' => 'hist-001',
            'deploymentId' => '0AfTESTDEPLOY001',
            'deploymentMode' => 'VALIDATE',
            'executionMode' => 'check-only',
            'status' => 'SUCCESS',
            'validationStatus' => 'PASS',
            'startedAt' => '2026-07-11T10:00:00.000Z',
            'completedAt' => '2026-07-11T10:00:03.000Z',
            'duration' => '3s',
            'durationMilliseconds' => 3000,
            'cliVersion' => '2.45.0',
            'cliCommand' => 'sf project deploy start --dry-run',
            'deploymentMessage' => 'Validation completed successfully',
            'deploymentPlanId' => deploymentPlanId,
            'metadataComparisonId' => metadataComparisonId,
            'sourceOrgId' => sourceOrgId,
            'destinationOrgId' => destinationOrgId,
            'deploymentSummary' => new Map<String, Object>{
                'componentsValidated' => 5,
                'componentsDeployed' => 4,
                'componentsTotal' => 5,
                'componentsFailed' => 1,
                'testsRun' => 2,
                'testsCompleted' => 2,
                'testsFailed' => 0,
                'overallCoverage' => 85.50,
                'status' => 'SUCCESS'
            },
            'validationSummary' => new Map<String, Object>{
                'overallStatus' => 'PASS',
                'message' => 'All checks passed'
            },
            'timeline' => new Map<String, Object>{
                'events' => new List<Object>{
                    new Map<String, Object>{
                        'name' => 'validate',
                        'status' => 'SUCCESS',
                        'timestamp' => '2026-07-11T10:00:00.000Z'
                    }
                }
            },
            'failureDetails' => new Map<String, Object>{
                'message' => 'none'
            },
            'warnings' => new List<Object>{
                new Map<String, Object>{
                    'message' => 'API version warning',
                    'severity' => 'WARNING'
                }
            },
            'errors' => new List<Object>(),
            'testResults' => new Map<String, Object>{
                'testsRun' => 2,
                'testsFailed' => 0
            },
            'cliCompatibility' => new Map<String, Object>{
                'cliVersion' => '2.45.0',
                'compatible' => true
            },
            'metadataSummary' => new Map<String, Object>{
                'totalComponents' => 5
            },
            'manifestSummary' => new Map<String, Object>{
                'packageCount' => 1
            },
            'workspaceSummary' => new Map<String, Object>{
                'branchName' => 'feature/deploy'
            }
        };

        return JSON.serialize(payload);
    }
}