public with sharing class DeploymentValidationController {

    private static final Integer SHORT_CALLOUT_TIMEOUT_MS = 20000;

    /**
     * Legacy synchronous validation endpoint (retained for compatibility).
     * Deploy uses async start/status transport to avoid the 120s callout ceiling.
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

        return SnapshotPersistenceService.applyToDeploymentResponse(
            normalizeHttpBody(res)
        );

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

        return enrichCompletedValidationStatus(normalizeHttpBody(res));

    }

    /**
     * Deploy using a prior successful Profile-only check-only validation artifact.
     * Synchronous callout — may run Salesforce deploy on the backend (120s ceiling).
     */
    @AuraEnabled
    public static String deployBoundValidation(
        String boundValidationId,
        String refreshToken,
        String instanceUrl,
        String orgId
    ) {
        if (String.isBlank(boundValidationId)) {
            return JSON.serialize(
                new Map<String, Object>{
                    'success' => false,
                    'boundDeploy' => new Map<String, Object>{
                        'status' => 'BLOCKED',
                        'code' => 'BOUND_VALIDATION_ID_REQUIRED',
                        'message' => 'boundValidationId is required.'
                    }
                }
            );
        }

        Map<String, Object> payload = new Map<String, Object>();
        payload.put('boundValidationId', boundValidationId.trim());
        payload.put('refreshToken', refreshToken);
        payload.put('instanceUrl', instanceUrl);
        payload.put('orgId', orgId);

        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            System.Label.Backend_Base_URL + '/api/deployment/deploy/bound'
        );
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(120000);

        HttpResponse res = http.send(req);
        return normalizeHttpBody(res);
    }

    private static String enrichCompletedValidationStatus(String responseBody) {
        if (String.isBlank(responseBody)) {
            return responseBody;
        }

        Map<String, Object> parsed;

        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        } catch (Exception e) {
            return responseBody;
        }

        if (
            parsed == null ||
            parsed.get('status') != 'COMPLETED' ||
            !parsed.containsKey('result') ||
            parsed.get('result') == null
        ) {
            return responseBody;
        }

        Object resultObject = parsed.get('result');
        if (!(resultObject instanceof Map<String, Object>)) {
            return responseBody;
        }

        Map<String, Object> resultMap = (Map<String, Object>) resultObject;
        if (
            !resultMap.containsKey('snapshotExport') ||
            resultMap.get('snapshotExport') == null
        ) {
            // No snapshot persistence work — avoid re-serializing a large result.
            return responseBody;
        }

        String enrichedResult = SnapshotPersistenceService.applyToDeploymentResponse(
            JSON.serialize(resultObject)
        );
        parsed.put('result', JSON.deserializeUntyped(enrichedResult));
        return JSON.serialize(parsed);
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
            if (packageMap.containsKey('autoExcludeShapeFormulaConflicts')) {
                payload.put(
                    'autoExcludeShapeFormulaConflicts',
                    packageMap.get('autoExcludeShapeFormulaConflicts') == true
                );
            }
            if (packageMap.containsKey('profileOnlyMinimalPackage')) {
                payload.put(
                    'profileOnlyMinimalPackage',
                    packageMap.get('profileOnlyMinimalPackage') == true
                );
            }
            if (packageMap.containsKey('explicitPrimarySelectedMetadata')) {
                payload.put(
                    'explicitPrimarySelectedMetadata',
                    packageMap.get('explicitPrimarySelectedMetadata')
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