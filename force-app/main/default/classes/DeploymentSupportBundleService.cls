/**
 * Phase 18.3 / 17.8 — Backend Support Bundle callout proxy.
 * POST /api/deployment/support-bundle
 * DOWNLOAD-only. Never forwards email, credentials, or forbidden keys.
 */
public with sharing class DeploymentSupportBundleService {

    private static final String SUPPORT_BUNDLE_PATH = '/api/deployment/support-bundle';
    private static final Integer TIMEOUT_MS = 120000;

    private static final Set<String> ALLOWED_CONTEXT_KEYS = new Set<String>{
        'historyId',
        'deploymentId',
        'validationCorrelationId',
        'correlationId',
        'requestId',
        'deploymentMode',
        'executionMode',
        'status',
        'overallStatus',
        'success',
        'deploymentReadiness',
        'deploymentReadinessAnalysis',
        'deploymentSummary',
        'packageSummary',
        'selectionSummary',
        'manifestSummary',
        'metadataCount',
        'dependencyCount',
        'membersByType',
        'metadata',
        'dependencies',
        'failureClassification',
        'resolutionReport',
        'autoFixReport',
        'autoValidationReport',
        'enterpriseDeploymentReport',
        'safeSkipReport',
        'deploymentDiagnostics',
        'checkOnlyDeployment',
        'deploymentExecution',
        'salesforceOutcome',
        'aiResolutionReport',
        'aiResolution',
        'dependencyValidation'
    };

    private static final Set<String> FORBIDDEN_KEYS = new Set<String>{
        'apiKey',
        'apikey',
        'API_KEY',
        'accessToken',
        'refreshToken',
        'password',
        'authorization',
        'Authorization',
        'clientSecret',
        'cookie',
        'privateKey',
        'recipient',
        'email',
        'to',
        'cc',
        'bcc',
        'smtp',
        'sendgrid',
        'model',
        'systemPrompt',
        'prompt',
        'tokens',
        'credentials'
    };

    /**
     * Sanitize client JSON and POST to the Support Bundle API.
     * Returns raw backend body (success or structured error JSON).
     */
    public static String requestSupportBundle(String requestJson) {
        Map<String, Object> payload = buildSanitizedPayload(requestJson);

        if (payload == null) {
            return JSON.serialize(
                new Map<String, Object>{
                    'success' => false,
                    'error' =>
                        'Unable to generate the Support Bundle. Validation context is incomplete.'
                }
            );
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            System.Label.Backend_Base_URL + SUPPORT_BUNDLE_PATH
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
                'statusCode' => res.getStatusCode(),
                'error' =>
                    'Support Bundle generation failed. No deployment was changed.'
            }
        );
    }

    @TestVisible
    private static Map<String, Object> buildSanitizedPayload(String requestJson) {
        if (String.isBlank(requestJson)) {
            return null;
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(requestJson);
        } catch (Exception e) {
            return null;
        }

        if (!(parsed instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> raw = (Map<String, Object>) parsed;

        for (String forbidden : FORBIDDEN_KEYS) {
            if (raw.containsKey(forbidden)) {
                raw.remove(forbidden);
            }
        }

        String validationId = null;
        if (raw.get('validationId') instanceof String) {
            validationId = ((String) raw.get('validationId')).trim();
        } else if (raw.get('historyId') instanceof String) {
            validationId = ((String) raw.get('historyId')).trim();
        }

        if (String.isBlank(validationId)) {
            return null;
        }

        Object contextRaw = raw.containsKey('validationContext')
            ? raw.get('validationContext')
            : raw.get('context');

        Map<String, Object> context = sanitizeContext(contextRaw);
        if (context == null || context.isEmpty()) {
            return null;
        }

        Map<String, Object> issueSelection = new Map<String, Object>{
            'scope' => 'ENTIRE_DEPLOYMENT',
            'failures' => new List<Object>()
        };

        if (raw.get('issueSelection') instanceof Map<String, Object>) {
            Map<String, Object> incoming =
                (Map<String, Object>) raw.get('issueSelection');
            String scope = incoming.get('scope') instanceof String
                ? ((String) incoming.get('scope')).trim().toUpperCase()
                : 'ENTIRE_DEPLOYMENT';
            if (scope == 'ENTIRE_DEPLOYMENT') {
                issueSelection.put('scope', 'ENTIRE_DEPLOYMENT');
            }
            // Phase 18.3: ENTIRE_DEPLOYMENT only — ignore SELECTED_FAILURES.
        }

        Map<String, Object> payload = new Map<String, Object>{
            'validationId' => validationId,
            'validationContext' => context,
            'issueSelection' => issueSelection
        };

        // Optional: pass through already-generated AI report if present (allowlisted).
        if (raw.get('aiResolutionReport') instanceof Map<String, Object>) {
            payload.put('aiResolutionReport', raw.get('aiResolutionReport'));
        }

        return payload;
    }

    @TestVisible
    private static Map<String, Object> sanitizeContext(Object contextRaw) {
        if (!(contextRaw instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> raw = (Map<String, Object>) contextRaw;
        Map<String, Object> sanitized = new Map<String, Object>();

        for (String key : raw.keySet()) {
            if (FORBIDDEN_KEYS.contains(key)) {
                continue;
            }
            if (!ALLOWED_CONTEXT_KEYS.contains(key)) {
                continue;
            }
            sanitized.put(key, raw.get(key));
        }

        return sanitized;
    }
}