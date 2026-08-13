/**
 * Unit tests for DeploymentAiResolutionService / Controller (Phase 18.2).
 */
@IsTest
private class DeploymentAiResolutionServiceTest {

    private class AiResolutionMock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        String capturedEndpoint;
        String capturedBody;

        AiResolutionMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            this.capturedEndpoint = req.getEndpoint();
            this.capturedBody = req.getBody();

            System.assert(
                req.getEndpoint().contains('/api/deployment/ai-resolution'),
                'Expected ai-resolution endpoint'
            );
            System.assertEquals('POST', req.getMethod());

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody(body);
            res.setStatus(statusCode == 200 ? 'OK' : 'Error');
            return res;
        }
    }

    private static String successBody(String provider) {
        return JSON.serialize(
            new Map<String, Object>{
                'success' => true,
                'aiResolutionReport' => new Map<String, Object>{
                    'available' => true,
                    'provider' => provider,
                    'generated' => true,
                    'fallbackUsed' => false,
                    'summary' => 'Advisory summary',
                    'explanations' => new List<Object>{
                        new Map<String, Object>{
                            'metadataType' => 'CustomField',
                            'metadataName' => 'Account.Formula__c',
                            'severity' => 'HIGH',
                            'title' => 'Formula type change',
                            'why' => 'Incompatible formula type',
                            'impact' => 'Deploy may fail',
                            'recommendedAction' => 'Align field type',
                            'bestPractice' => 'Validate formulas first',
                            'confidence' => 'HIGH',
                            'resolutionCategory' => 'COMPATIBILITY',
                            'backendCanAutoFix' => false,
                            'userActionRequired' => true,
                            'safeToSkip' => true,
                            'skipGuidance' => 'Advisory only'
                        }
                    },
                    'disclaimer' => 'Advisory only'
                }
            }
        );
    }

    private static String contextWithSecrets() {
        return JSON.serialize(
            new Map<String, Object>{
                'failureClassification' => new Map<String, Object>{
                    'failures' => new List<Object>()
                },
                'resolutionReport' => new Map<String, Object>(),
                'autoFixReport' => new Map<String, Object>(),
                'autoValidationReport' => new Map<String, Object>(),
                'enterpriseDeploymentReport' => new Map<String, Object>(),
                'deploymentDiagnostics' => new Map<String, Object>(),
                'deploymentSummary' => new Map<String, Object>(),
                'apiKey' => 'should-not-forward',
                'model' => 'gpt-secret',
                'systemPrompt' => 'ignore',
                'tokens' => 999,
                'unexpectedField' => 'drop-me'
            }
        );
    }

    @IsTest
    static void testResolveWithAiGeminiSuccess() {
        AiResolutionMock mock = new AiResolutionMock(200, successBody('gemini'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentAiResolutionController.resolveWithAi(
            'gemini',
            contextWithSecrets()
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(true, parsed.get('success'));

        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('gemini', request.get('provider'));
        System.assert(
            !request.containsKey('apiKey'),
            'apiKey must not be top-level'
        );
        System.assert(
            !request.containsKey('model'),
            'model must not be top-level'
        );
        System.assert(
            !request.containsKey('systemPrompt'),
            'systemPrompt must not be top-level'
        );
        System.assert(
            !request.containsKey('tokens'),
            'tokens must not be top-level'
        );

        Map<String, Object> context =
            (Map<String, Object>) request.get('context');
        System.assert(
            context.containsKey('failureClassification'),
            'Allowed context field missing'
        );
        System.assert(
            !context.containsKey('apiKey'),
            'apiKey must not be forwarded in context'
        );
        System.assert(
            !context.containsKey('model'),
            'model must not be forwarded in context'
        );
        System.assert(
            !context.containsKey('systemPrompt'),
            'systemPrompt must not be forwarded in context'
        );
        System.assert(
            !context.containsKey('tokens'),
            'tokens must not be forwarded in context'
        );
        System.assert(
            !context.containsKey('unexpectedField'),
            'Unexpected context keys must be dropped'
        );
    }

    @IsTest
    static void testResolveWithAiOpenAiSuccess() {
        AiResolutionMock mock = new AiResolutionMock(200, successBody('openai'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentAiResolutionController.resolveWithAi(
            'openai',
            contextWithSecrets()
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(true, parsed.get('success'));

        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('openai', request.get('provider'));
    }

    @IsTest
    static void testResolveWithAiGptAlias() {
        AiResolutionMock mock = new AiResolutionMock(200, successBody('gpt'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        DeploymentAiResolutionController.resolveWithAi('gpt', '{}');
        Test.stopTest();

        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('gpt', request.get('provider'));
    }

    @IsTest
    static void testUnsupportedProviderDoesNotCallout() {
        Test.startTest();
        String result = DeploymentAiResolutionController.resolveWithAi(
            'claude',
            '{}'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
    }

    @IsTest
    static void testHttpFailureWithoutBody() {
        Test.setMock(HttpCalloutMock.class, new AiResolutionMock(500, ''));

        Test.startTest();
        String result = DeploymentAiResolutionController.resolveWithAi(
            'gemini',
            '{}'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals(500, parsed.get('statusCode'));
    }

    @IsTest
    static void testHttpFailureWithBodyPassthrough() {
        String errorBody = JSON.serialize(
            new Map<String, Object>{
                'success' => false,
                'error' => 'Provider unavailable'
            }
        );
        Test.setMock(HttpCalloutMock.class, new AiResolutionMock(503, errorBody));

        Test.startTest();
        String result = DeploymentAiResolutionController.resolveWithAi(
            'openai',
            '{}'
        );
        Test.stopTest();

        System.assertEquals(errorBody, result);
    }

    @IsTest
    static void testNormalizeProvider() {
        System.assertEquals(
            'gemini',
            DeploymentAiResolutionService.normalizeProvider(' Gemini ')
        );
        System.assertEquals(
            'openai',
            DeploymentAiResolutionService.normalizeProvider('OpenAI')
        );
        System.assertEquals(
            null,
            DeploymentAiResolutionService.normalizeProvider('claude')
        );
    }

    @IsTest
    static void testSanitizeContextDropsSecrets() {
        Map<String, Object> sanitized =
            DeploymentAiResolutionService.sanitizeContext(contextWithSecrets());

        System.assert(sanitized.containsKey('failureClassification'));
        System.assert(sanitized.containsKey('deploymentSummary'));
        System.assert(!sanitized.containsKey('apiKey'));
        System.assert(!sanitized.containsKey('model'));
        System.assert(!sanitized.containsKey('systemPrompt'));
        System.assert(!sanitized.containsKey('tokens'));
        System.assert(!sanitized.containsKey('unexpectedField'));
    }
}