/**
 * Phase 18.2 / 17.7 — Backend AI Resolution callout proxy.
 * POST /api/deployment/ai-resolution
 * Never forwards apiKey, model, systemPrompt, or tokens.
 */
public with sharing class DeploymentAiResolutionService {

    private static final String AI_RESOLUTION_PATH = '/api/deployment/ai-resolution';
    private static final Integer TIMEOUT_MS = 120000;

    private static final Set<String> ALLOWED_PROVIDERS = new Set<String>{
        'gemini',
        'openai',
        'gpt'
    };

    private static final Set<String> ALLOWED_CONTEXT_KEYS = new Set<String>{
        'failureClassification',
        'resolutionReport',
        'autoFixReport',
        'autoValidationReport',
        'enterpriseDeploymentReport',
        'deploymentDiagnostics',
        'deploymentSummary',
        'aiResolutionFactPack'
    };

    private static final Set<String> FORBIDDEN_KEYS = new Set<String>{
        'apiKey',
        'apikey',
        'API_KEY',
        'model',
        'systemPrompt',
        'prompt',
        'tokens',
        'credentials',
        'token',
        'authorization',
        'Authorization'
    };

    /**
     * Build a sanitized provider+context payload and POST to the backend.
     * Returns the raw response body (success or structured error JSON).
     */
    public static String requestAiResolution(
        String provider,
        String contextJson
    ) {
        String normalizedProvider = normalizeProvider(provider);

        if (String.isBlank(normalizedProvider)) {
            return JSON.serialize(
                new Map<String, Object>{
                    'success' => false,
                    'error' =>
                        'Unsupported AI provider. Supported providers: gemini, openai, gpt.',
                    'aiResolutionReport' => new Map<String, Object>{
                        'available' => false,
                        'generated' => false,
                        'explanations' => new List<Object>(),
                        'disclaimer' =>
                            'AI Resolution is currently unavailable.'
                    }
                }
            );
        }

        Map<String, Object> contextMap = sanitizeContext(contextJson);

        Map<String, Object> payload = new Map<String, Object>{
            'provider' => normalizedProvider,
            'context' => contextMap
        };

        String payloadBody = JSON.serialize(payload);
        logTransportSizeDiagnostics(payloadBody, contextMap);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            System.Label.Backend_Base_URL + AI_RESOLUTION_PATH
        );
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(payloadBody);
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
                'error' => res.getStatus(),
                'aiResolutionReport' => new Map<String, Object>{
                    'available' => false,
                    'generated' => false,
                    'provider' => normalizedProvider,
                    'explanations' => new List<Object>(),
                    'disclaimer' =>
                        'AI Resolution is currently unavailable.'
                }
            }
        );
    }

    @TestVisible
    private static String normalizeProvider(String provider) {
        if (String.isBlank(provider)) {
            return null;
        }
        String normalized = provider.trim().toLowerCase();
        if (!ALLOWED_PROVIDERS.contains(normalized)) {
            return null;
        }
        return normalized;
    }

    @TestVisible
    private static Map<String, Object> sanitizeContext(String contextJson) {
        Map<String, Object> sanitized = new Map<String, Object>();

        if (String.isBlank(contextJson)) {
            return sanitized;
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(contextJson);
        } catch (Exception e) {
            return sanitized;
        }

        if (!(parsed instanceof Map<String, Object>)) {
            return sanitized;
        }

        Map<String, Object> raw = (Map<String, Object>) parsed;

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

    /**
     * DEBUG-ONLY size diagnostic. Never logs tokens, Authorization, or full body.
     */
    @TestVisible
    private static void logTransportSizeDiagnostics(
        String payloadBody,
        Map<String, Object> contextMap
    ) {
        Integer payloadBytes =
            String.isBlank(payloadBody)
                ? 0
                : Blob.valueOf(payloadBody).size();
        Integer contextBytes =
            contextMap == null
                ? 0
                : Blob.valueOf(JSON.serialize(contextMap)).size();

        Integer factPackComponentCount = 0;
        if (
            contextMap != null &&
            contextMap.get('aiResolutionFactPack') instanceof Map<String, Object>
        ) {
            Map<String, Object> pack =
                (Map<String, Object>) contextMap.get('aiResolutionFactPack');
            if (pack.get('components') instanceof List<Object>) {
                factPackComponentCount =
                    ((List<Object>) pack.get('components')).size();
            }
        }

        System.debug(
            LoggingLevel.DEBUG,
            'AI Resolution transport size payloadBytes=' +
                payloadBytes +
                ' contextBytes=' +
                contextBytes +
                ' factPackComponents=' +
                factPackComponentCount
        );
    }
}