/**
 * Unit tests for DeploymentSupportBundleService / Controller (Phase 18.3).
 */
@IsTest
private class DeploymentSupportBundleServiceTest {

    private class SupportBundleMock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        String capturedEndpoint;
        String capturedBody;

        SupportBundleMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            this.capturedEndpoint = req.getEndpoint();
            this.capturedBody = req.getBody();

            System.assert(
                req.getEndpoint().contains('/api/deployment/support-bundle'),
                'Expected support-bundle endpoint'
            );
            System.assertEquals('POST', req.getMethod());
            System.assert(
                !req.getEndpoint().contains('/ai-resolution'),
                'Must not call AI endpoint'
            );
            System.assert(
                !req.getEndpoint().contains('/api/deployment/validate'),
                'Must not call validate endpoint'
            );

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody(body);
            res.setStatus(statusCode == 200 ? 'OK' : 'Error');
            return res;
        }
    }

    private static String validRequestJson() {
        return JSON.serialize(
            new Map<String, Object>{
                'validationId' => 'hist-123',
                'validationContext' => new Map<String, Object>{
                    'failureClassification' => new Map<String, Object>{
                        'failures' => new List<Object>()
                    },
                    'enterpriseDeploymentReport' => new Map<String, Object>{
                        'overallStatus' => 'FAILED'
                    },
                    'safeSkipReport' => new Map<String, Object>(),
                    'apiKey' => 'should-not-forward',
                    'refreshToken' => 'should-not-forward',
                    'email' => 'should-not-forward'
                },
                'issueSelection' => new Map<String, Object>{
                    'scope' => 'ENTIRE_DEPLOYMENT',
                    'failures' => new List<Object>()
                },
                'recipient' => 'hacker@example.com',
                'apiKey' => 'top-secret'
            }
        );
    }

    private static String successBody() {
        return JSON.serialize(
            new Map<String, Object>{
                'success' => true,
                'supportBundle' => new Map<String, Object>{
                    'bundleId' => 'SUP-ABC123',
                    'version' => 1
                },
                'delivery' => new Map<String, Object>{
                    'mode' => 'DOWNLOAD',
                    'filename' => 'SUP-ABC123.json'
                }
            }
        );
    }

    @IsTest
    static void testCreateSupportBundleSuccess() {
        SupportBundleMock mock = new SupportBundleMock(200, successBody());
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentSupportBundleController.createSupportBundle(
            validRequestJson()
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(true, parsed.get('success'));

        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('hist-123', request.get('validationId'));
        System.assert(
            !request.containsKey('apiKey'),
            'apiKey must not be forwarded'
        );
        System.assert(
            !request.containsKey('recipient'),
            'email recipient must not be forwarded'
        );
        System.assert(
            !request.containsKey('email'),
            'email must not be forwarded'
        );

        Map<String, Object> context =
            (Map<String, Object>) request.get('validationContext');
        System.assert(context.containsKey('failureClassification'));
        System.assert(context.containsKey('safeSkipReport'));
        System.assert(!context.containsKey('apiKey'));
        System.assert(!context.containsKey('refreshToken'));
        System.assert(!context.containsKey('email'));

        Map<String, Object> selection =
            (Map<String, Object>) request.get('issueSelection');
        System.assertEquals('ENTIRE_DEPLOYMENT', selection.get('scope'));

        Map<String, Object> delivery =
            (Map<String, Object>) parsed.get('delivery');
        System.assertEquals('DOWNLOAD', delivery.get('mode'));
    }

    @IsTest
    static void testMissingValidationId() {
        Test.startTest();
        String result = DeploymentSupportBundleController.createSupportBundle(
            JSON.serialize(
                new Map<String, Object>{
                    'validationContext' => new Map<String, Object>{
                        'failureClassification' => new Map<String, Object>()
                    }
                }
            )
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
    }

    @IsTest
    static void testBackend400Passthrough() {
        String errorBody = JSON.serialize(
            new Map<String, Object>{
                'success' => false,
                'error' => 'validationId is required.'
            }
        );
        Test.setMock(HttpCalloutMock.class, new SupportBundleMock(400, errorBody));

        Test.startTest();
        String result = DeploymentSupportBundleController.createSupportBundle(
            validRequestJson()
        );
        Test.stopTest();

        System.assertEquals(errorBody, result);
    }

    @IsTest
    static void testBackend404Passthrough() {
        String errorBody = JSON.serialize(
            new Map<String, Object>{
                'success' => false,
                'error' => 'Validation context was not found.'
            }
        );
        Test.setMock(HttpCalloutMock.class, new SupportBundleMock(404, errorBody));

        Test.startTest();
        String result = DeploymentSupportBundleController.createSupportBundle(
            validRequestJson()
        );
        Test.stopTest();

        System.assertEquals(errorBody, result);
    }

    @IsTest
    static void testBackend500WithoutBody() {
        Test.setMock(HttpCalloutMock.class, new SupportBundleMock(500, ''));

        Test.startTest();
        String result = DeploymentSupportBundleController.createSupportBundle(
            validRequestJson()
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals(500, parsed.get('statusCode'));
    }

    @IsTest
    static void testSanitizeContextDropsSecrets() {
        Map<String, Object> sanitized =
            DeploymentSupportBundleService.sanitizeContext(
                new Map<String, Object>{
                    'failureClassification' => new Map<String, Object>(),
                    'apiKey' => 'x',
                    'refreshToken' => 'y',
                    'unexpected' => 'z'
                }
            );

        System.assert(sanitized.containsKey('failureClassification'));
        System.assert(!sanitized.containsKey('apiKey'));
        System.assert(!sanitized.containsKey('refreshToken'));
        System.assert(!sanitized.containsKey('unexpected'));
    }
}