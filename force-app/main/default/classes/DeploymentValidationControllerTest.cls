/**
 * Unit tests for async Deployment Validation transport
 * (startValidation / getValidationStatus) and retained sync validateDeployment.
 */
@IsTest
private class DeploymentValidationControllerTest {

    private class ValidationTransportMock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        String expectedPathFragment;
        String expectedMethod;
        String capturedEndpoint;
        String capturedBody;

        ValidationTransportMock(
            Integer statusCode,
            String body,
            String expectedPathFragment,
            String expectedMethod
        ) {
            this.statusCode = statusCode;
            this.body = body;
            this.expectedPathFragment = expectedPathFragment;
            this.expectedMethod = expectedMethod;
        }

        public HTTPResponse respond(HTTPRequest req) {
            this.capturedEndpoint = req.getEndpoint();
            this.capturedBody = req.getBody();

            System.assert(
                req.getEndpoint().contains(expectedPathFragment),
                'Expected endpoint containing ' + expectedPathFragment
            );
            System.assertEquals(expectedMethod, req.getMethod());

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody(body);
            res.setStatus(statusCode == 200 ? 'OK' : 'Error');
            return res;
        }
    }

    private static String samplePackageJson() {
        return JSON.serialize(
            new Map<String, Object>{
                'repoUrl' => 'https://example.com/repo.git',
                'sourceBranch' => 'src',
                'destinationBranch' => 'dst',
                'selectedMetadata' => new List<Object>(),
                'requiredDependencies' => new List<Object>(),
                'selectedTestClasses' => new List<Object>(),
                'deploymentSelections' => new List<Object>{
                    new Map<String, Object>{
                        'metadataType' => 'ApexClass',
                        'metadataName' => 'Foo',
                        'choice' => 'Deploy'
                    }
                }
            }
        );
    }

    @IsTest
    static void testStartValidationReturnsRunningAndValidationId() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'success' => true,
                'accepted' => true,
                'status' => 'RUNNING',
                'validationId' => 'validation_abc123'
            }
        );

        ValidationTransportMock mock = new ValidationTransportMock(
            200,
            responseBody,
            '/api/deployment/validate/start',
            'POST'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentValidationController.startValidation(
            'rt',
            'https://example.my.salesforce.com',
            '00Dxx0000000001',
            samplePackageJson()
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(true, parsed.get('success'));
        System.assertEquals(true, parsed.get('accepted'));
        System.assertEquals('RUNNING', parsed.get('status'));
        System.assertEquals('validation_abc123', parsed.get('validationId'));

        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('rt', request.get('refreshToken'));
        System.assert(request.containsKey('deploymentPackage'));
        System.assert(request.containsKey('deploymentSelections'));
        System.assert(
            mock.capturedEndpoint.contains('/api/deployment/validate/start'),
            'START must call /api/deployment/validate/start'
        );
    }

    @IsTest
    static void testGetValidationStatusRunning() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'success' => true,
                'status' => 'RUNNING',
                'validationId' => 'validation_abc123'
            }
        );

        ValidationTransportMock mock = new ValidationTransportMock(
            200,
            responseBody,
            '/api/deployment/validate/status/validation_abc123',
            'GET'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentValidationController.getValidationStatus(
            'validation_abc123'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals('RUNNING', parsed.get('status'));
        System.assertEquals('validation_abc123', parsed.get('validationId'));
        System.assertEquals(null, parsed.get('result'));
    }

    @IsTest
    static void testGetValidationStatusCompletedPreservesResult() {
        Map<String, Object> existingResult = new Map<String, Object>{
            'deploymentReadiness' => new Map<String, Object>{
                'canDeploy' => false,
                'readyForDeployment' => false,
                'overallStatus' => 'BLOCKED'
            },
            'checkOnlyDeployment' => new Map<String, Object>{
                'success' => false
            },
            'enterpriseDeploymentReport' => new Map<String, Object>{
                'overallStatus' => 'FAILED'
            },
            'dependencyValidation' => new Map<String, Object>{
                'overallStatus' => 'FAIL'
            }
        };

        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'success' => true,
                'status' => 'COMPLETED',
                'validationId' => 'validation_abc123',
                'result' => existingResult
            }
        );

        ValidationTransportMock mock = new ValidationTransportMock(
            200,
            responseBody,
            '/api/deployment/validate/status/',
            'GET'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentValidationController.getValidationStatus(
            'validation_abc123'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals('COMPLETED', parsed.get('status'));

        Map<String, Object> preserved =
            (Map<String, Object>) parsed.get('result');
        System.assertNotEquals(null, preserved);
        System.assert(
            preserved.containsKey('deploymentReadiness'),
            'COMPLETED must preserve existing validation result shape'
        );
        System.assert(
            preserved.containsKey('checkOnlyDeployment'),
            'COMPLETED must preserve checkOnlyDeployment'
        );
        System.assert(
            preserved.containsKey('enterpriseDeploymentReport'),
            'COMPLETED must preserve enterpriseDeploymentReport'
        );
    }

    @IsTest
    static void testGetValidationStatusFailed() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'success' => true,
                'status' => 'FAILED',
                'validationId' => 'validation_abc123',
                'error' => 'Validation engine crashed',
                'result' => new Map<String, Object>{
                    'deploymentReadiness' => new Map<String, Object>{
                        'canDeploy' => false
                    }
                }
            }
        );

        ValidationTransportMock mock = new ValidationTransportMock(
            200,
            responseBody,
            '/api/deployment/validate/status/',
            'GET'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentValidationController.getValidationStatus(
            'validation_abc123'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals('FAILED', parsed.get('status'));
        System.assertEquals('Validation engine crashed', parsed.get('error'));
        System.assertNotEquals(null, parsed.get('result'));
    }

    @IsTest
    static void testGetValidationStatusNotFound404() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'success' => false,
                'error' => 'Validation job not found.',
                'validationId' => 'validation_missing'
            }
        );

        ValidationTransportMock mock = new ValidationTransportMock(
            404,
            responseBody,
            '/api/deployment/validate/status/',
            'GET'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentValidationController.getValidationStatus(
            'validation_missing'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals(
            'Validation job not found.',
            parsed.get('error')
        );
    }

    @IsTest
    static void testGetValidationStatusBlankId() {
        Test.startTest();
        String result = DeploymentValidationController.getValidationStatus('');
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals(400, parsed.get('statusCode'));
    }

    @IsTest
    static void testSyncValidateDeploymentRemainsIntact() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'deploymentReadiness' => new Map<String, Object>{
                    'canDeploy' => true
                }
            }
        );

        ValidationTransportMock mock = new ValidationTransportMock(
            200,
            responseBody,
            '/api/deployment/validate',
            'POST'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentValidationController.validateDeployment(
            'rt',
            'https://example.my.salesforce.com',
            '00Dxx0000000001',
            samplePackageJson()
        );
        Test.stopTest();

        System.assert(
            mock.capturedEndpoint.contains('/api/deployment/validate')
        );
        System.assert(
            !mock.capturedEndpoint.contains('/start'),
            'Sync method must call legacy /validate'
        );
        System.assert(
            !mock.capturedEndpoint.contains('/status/'),
            'Sync method must not call status endpoint'
        );

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertNotEquals(null, parsed.get('deploymentReadiness'));
    }
}