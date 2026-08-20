public with sharing class DeploymentValidationController {

    private static final Integer SHORT_CALLOUT_TIMEOUT_MS = 20000;

    /**
     * Legacy synchronous validation (still used by Deploy execution).
     * Long-running validate can hit the 120s Apex callout ceiling.
     */
    @AuraEnabled
    public static String validateDeployment(
        String refreshToken,
        String instanceUrl,
        String orgId,
        String deploymentPackage
    ) {

        Map<String, Object> payload =
            buildValidationPayload(
                refreshToken,
                instanceUrl,
                orgId,
                deploymentPackage
            );

        Http http = new Http();

        HttpRequest req = new HttpRequest();

        req.setEndpoint(
            System.Label.Backend_Base_URL +
            '/api/deployment/validate'
        );

        req.setMethod('POST');

        req.setHeader(
            'Content-Type',
            'application/json'
        );

        req.setBody(
            JSON.serialize(payload)
        );

        req.setTimeout(120000);

        HttpResponse res = http.send(req);

        return normalizeHttpBody(res);

    }

    /**
     * Async validation start — returns validationId immediately.
     * Must not use the 120s callout timeout.
     */
    @AuraEnabled
    public static String startValidation(
        String refreshToken,
        String instanceUrl,
        String orgId,
        String deploymentPackage
    ) {

        Map<String, Object> payload =
            buildValidationPayload(
                refreshToken,
                instanceUrl,
                orgId,
                deploymentPackage
            );

        Http http = new Http();

        HttpRequest req = new HttpRequest();

        req.setEndpoint(
            System.Label.Backend_Base_URL +
            '/api/deployment/validate/start'
        );

        req.setMethod('POST');

        req.setHeader(
            'Content-Type',
            'application/json'
        );

        req.setBody(
            JSON.serialize(payload)
        );

        req.setTimeout(SHORT_CALLOUT_TIMEOUT_MS);

        HttpResponse res = http.send(req);

        return normalizeHttpBody(res);

    }

    /**
     * Async validation status poll — short callout; Azure holds the long work.
     */
    @AuraEnabled
    public static String getValidationStatus(String validationId) {

        if (String.isBlank(validationId)) {
            return JSON.serialize(
                new Map<String, Object>{
                    'success' => false,
                    'error' => 'validationId is required.',
                    'statusCode' => 400
                }
            );
        }

        String encodedId = EncodingUtil.urlEncode(
            validationId.trim(),
            'UTF-8'
        );

        Http http = new Http();

        HttpRequest req = new HttpRequest();

        req.setEndpoint(
            System.Label.Backend_Base_URL +
            '/api/deployment/validate/status/' +
            encodedId
        );

        req.setMethod('GET');

        req.setTimeout(SHORT_CALLOUT_TIMEOUT_MS);

        HttpResponse res = http.send(req);

        return normalizeHttpBody(res);

    }

    private static Map<String, Object> buildValidationPayload(
        String refreshToken,
        String instanceUrl,
        String orgId,
        String deploymentPackage
    ) {

        Map<String, Object> payload =
            new Map<String, Object>();

        payload.put(
            'refreshToken',
            refreshToken
        );

        payload.put(
            'instanceUrl',
            instanceUrl
        );

        payload.put(
            'orgId',
            orgId
        );

        Object packageUntyped =
            JSON.deserializeUntyped(deploymentPackage);

        payload.put(
            'deploymentPackage',
            packageUntyped
        );

        // Optional top-level selections when present inside the package.
        if (packageUntyped instanceof Map<String, Object>) {
            Map<String, Object> packageMap =
                (Map<String, Object>) packageUntyped;
            if (packageMap.containsKey('deploymentSelections')) {
                payload.put(
                    'deploymentSelections',
                    packageMap.get('deploymentSelections')
                );
            }
        }

        return payload;

    }

    private static String normalizeHttpBody(HttpResponse res) {

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
                'error' => res.getStatus()
            }
        );

    }

}