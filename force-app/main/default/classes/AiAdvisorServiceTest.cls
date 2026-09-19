/**
 * Unit tests for AiAdvisorService / AiAdvisorController callout proxy.
 */
@IsTest
private class AiAdvisorServiceTest {

    private class AdvisorMock implements HttpCalloutMock {
        Integer statusCode;
        String body;

        AdvisorMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            System.assert(
                req.getEndpoint().contains('/api/ai/advisor'),
                'Expected advisor endpoint'
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

    @IsTest
    static void testGetAiAdvisorSuccess() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'success' => true,
                'advisorStatus' => 'OK',
                'groundingScore' => 95,
                'semanticResponse' => new Map<String, Object>{
                    'executiveSummary' => 'Summary'
                },
                'validationWarnings' => new List<String>(),
                'diagnostics' => new Map<String, Object>()
            }
        );

        Test.setMock(
            HttpCalloutMock.class,
            new AdvisorMock(200, responseBody)
        );

        String requestJson = JSON.serialize(
            new Map<String, Object>{
                'packageSummary' => new Map<String, Object>{
                    'metadataCount' => 1,
                    'dependencyCount' => 0,
                    'testClassCount' => 0,
                    'totalComponents' => 1
                }
            }
        );

        Test.startTest();
        String result = AiAdvisorController.getAiAdvisor(requestJson);
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);

        System.assertEquals(true, parsed.get('success'));
        System.assertEquals('OK', parsed.get('advisorStatus'));
        System.assertEquals(95, parsed.get('groundingScore'));
    }

    @IsTest
    static void testGetAiAdvisorHttpFailureWithoutBody() {
        Test.setMock(
            HttpCalloutMock.class,
            new AdvisorMock(503, '')
        );

        Test.startTest();
        String result = AiAdvisorController.getAiAdvisor('{}');
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);

        System.assertEquals(false, parsed.get('success'));
        System.assertEquals('UNAVAILABLE', parsed.get('advisorStatus'));
    }

    @IsTest
    static void testMapStatusFromHttp() {
        System.assertEquals(
            'AUTH_FAILURE',
            AiAdvisorService.mapStatusFromHttp(401)
        );
        System.assertEquals(
            'RATE_LIMITED',
            AiAdvisorService.mapStatusFromHttp(429)
        );
        System.assertEquals(
            'TIMEOUT',
            AiAdvisorService.mapStatusFromHttp(408)
        );
        System.assertEquals(
            'INVALID_RESPONSE',
            AiAdvisorService.mapStatusFromHttp(422)
        );
        System.assertEquals(
            'UNAVAILABLE',
            AiAdvisorService.mapStatusFromHttp(500)
        );
    }

}