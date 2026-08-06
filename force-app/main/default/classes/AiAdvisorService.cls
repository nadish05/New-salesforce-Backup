/**
 * Phase 10F — Backend AI Advisor callout proxy.
 * Reuses the standard Backend_Base_URL HTTP pattern.
 * Does not implement planner logic.
 */
public with sharing class AiAdvisorService {

    private static final String ADVISOR_PATH = '/api/ai/advisor';
    private static final Integer TIMEOUT_MS = 120000;

    /**
     * POST the provided planner/review payload to the AI Advisor API.
     * Returns the raw response body (success or structured error JSON).
     *
     * @param requestJson JSON body already shaped for POST /api/ai/advisor
     * @return Response body string
     */
    public static String requestAdvisor(String requestJson) {

        Object payload;

        if (String.isBlank(requestJson)) {
            payload = new Map<String, Object>();
        } else {
            payload = JSON.deserializeUntyped(requestJson);
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            System.Label.Backend_Base_URL + ADVISOR_PATH
        );
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(TIMEOUT_MS);

        HttpResponse res = new Http().send(req);

        if (
            res.getStatusCode() >= 200 &&
            res.getStatusCode() < 300
        ) {
            return res.getBody();
        }

        String body = res.getBody();

        if (String.isNotBlank(body)) {
            return body;
        }

        return JSON.serialize(
            new Map<String, Object>{
                'success' => false,
                'advisorStatus' => mapStatusFromHttp(res.getStatusCode()),
                'groundingScore' => 0,
                'semanticResponse' => null,
                'validationWarnings' => new List<String>{
                    'AI Advisor unavailable.'
                },
                'diagnostics' => new Map<String, Object>{
                    'stage' => 'CALLOUT',
                    'errorCode' => mapStatusFromHttp(res.getStatusCode()),
                    'errorMessage' => res.getStatus(),
                    'latencyMs' => 0,
                    'provider' => null,
                    'tokenUsage' => null
                },
                'statusCode' => res.getStatusCode(),
                'error' => res.getStatus()
            }
        );
    }

    @TestVisible
    private static String mapStatusFromHttp(Integer statusCode) {

        if (statusCode == 401) {
            return 'AUTH_FAILURE';
        }

        if (statusCode == 429) {
            return 'RATE_LIMITED';
        }

        if (statusCode == 408 || statusCode == 504) {
            return 'TIMEOUT';
        }

        if (statusCode == 422) {
            return 'INVALID_RESPONSE';
        }

        if (statusCode == 503) {
            return 'UNAVAILABLE';
        }

        return 'UNAVAILABLE';
    }

}