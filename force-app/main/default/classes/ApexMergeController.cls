/**
 * Apex Merge backend proxy. Does not perform Git merge or expose credentials to LWC.
 */
public with sharing class ApexMergeController {

    private static final Integer SHORT_TIMEOUT_MS = 20000;
    private static final Integer LONG_TIMEOUT_MS = 120000;
    private static final String SESSIONS_PATH = '/api/merge/apex/sessions';

    @AuraEnabled
    public static String createMergeSession(
        Id comparisonId,
        Id deploymentPlanId,
        String eligibleClassesJson
    ) {
        try {
            validatePlanForComparison(comparisonId, deploymentPlanId);
            Map<String, Object> comparisonCtx = loadComparisonContext(comparisonId);

            List<Object> classRows = (List<Object>) parseJsonArray(
                eligibleClassesJson
            );
            Map<String, Object> payload = new Map<String, Object>{
                'comparisonId' => String.valueOf(comparisonId),
                'deploymentPlanId' => String.valueOf(deploymentPlanId),
                'repoUrl' => System.Label.GitHub_Repo_URL,
                'sourceBranch' => comparisonCtx.get('sourceBranch'),
                'destinationBranch' => comparisonCtx.get('destinationBranch'),
                'classes' => classRows,
                'eligibleClasses' => classRows
            };

            return sendJson(
                'POST',
                System.Label.Backend_Base_URL + SESSIONS_PATH,
                payload,
                LONG_TIMEOUT_MS
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            return failureJson('Unable to create merge session.');
        }
    }

    @AuraEnabled
    public static String getMergeSessionStatus(String mergeSessionId) {
        if (String.isBlank(mergeSessionId)) {
            return failureJson('mergeSessionId is required.');
        }
        try {
            String encoded = EncodingUtil.urlEncode(
                mergeSessionId.trim(),
                'UTF-8'
            );
            return sendJson(
                'GET',
                System.Label.Backend_Base_URL + SESSIONS_PATH + '/' + encoded,
                null,
                SHORT_TIMEOUT_MS
            );
        } catch (Exception e) {
            return failureJson('Unable to retrieve merge session status.');
        }
    }

    @AuraEnabled
    public static String previewClassMerge(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String requestJson
    ) {
        try {
            validatePlanForComparison(comparisonId, deploymentPlanId);
            return invokeSessionSubresource(
                comparisonId,
                deploymentPlanId,
                mergeSessionId,
                'preview',
                requestJson,
                LONG_TIMEOUT_MS,
                true
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            return failureJson('Unable to process merge preview request.');
        }
    }

    @AuraEnabled
    public static String resolveClassMerge(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String requestJson
    ) {
        try {
            validatePlanForComparison(comparisonId, deploymentPlanId);
            return invokeSessionSubresource(
                comparisonId,
                deploymentPlanId,
                mergeSessionId,
                'resolve',
                requestJson,
                LONG_TIMEOUT_MS,
                false
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            return failureJson('Unable to process merge resolve request.');
        }
    }

    @AuraEnabled
    public static String persistSealedMergeArtifacts(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String sealedManifestJson
    ) {
        try {
            validatePlanForComparison(comparisonId, deploymentPlanId);
            return ApexMergeArtifactRetrievalService.retrieveAndPersist(
                comparisonId,
                deploymentPlanId,
                mergeSessionId,
                sealedManifestJson
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            return failureJson('Unable to persist sealed merge artifacts.');
        }
    }

    @AuraEnabled
    public static String sealMergeManifest(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId
    ) {
        try {
            validatePlanForComparison(comparisonId, deploymentPlanId);
            if (String.isBlank(mergeSessionId)) {
                return failureJson('mergeSessionId is required.');
            }

            Map<String, Object> payload = new Map<String, Object>{
                'comparisonId' => String.valueOf(comparisonId),
                'deploymentPlanId' => String.valueOf(deploymentPlanId)
            };

            String encoded = EncodingUtil.urlEncode(
                mergeSessionId.trim(),
                'UTF-8'
            );
            return sendJson(
                'POST',
                System.Label.Backend_Base_URL +
                    SESSIONS_PATH +
                    '/' +
                    encoded +
                    '/seal',
                payload,
                LONG_TIMEOUT_MS
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            return failureJson('Unable to seal merge manifest.');
        }
    }

  @TestVisible
    private static void validatePlanForComparison(
        Id comparisonId,
        Id deploymentPlanId
    ) {
        if (comparisonId == null) {
            throw new AuraHandledException('comparisonId is required.');
        }
        if (deploymentPlanId == null) {
            throw new AuraHandledException('deploymentPlanId is required.');
        }

        List<Deployment_Plan__c> plans = [
            SELECT Id, Metadata_Comparison__c
            FROM Deployment_Plan__c
            WHERE Id = :deploymentPlanId
            LIMIT 1
        ];

        if (plans.isEmpty()) {
            throw new AuraHandledException('Deployment Plan was not found.');
        }

        if (plans[0].Metadata_Comparison__c != comparisonId) {
            throw new AuraHandledException(
                'Deployment Plan does not belong to the selected comparison.'
            );
        }
    }

    @TestVisible
    private static Map<String, Object> loadComparisonContext(Id comparisonId) {
        List<Metadata_Comparison__c> rows = [
            SELECT Source_Branch__c, Destination_Branch__c
            FROM Metadata_Comparison__c
            WHERE Id = :comparisonId
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            throw new AuraHandledException('Metadata Comparison was not found.');
        }

        return new Map<String, Object>{
            'sourceBranch' => rows[0].Source_Branch__c,
            'destinationBranch' => rows[0].Destination_Branch__c
        };
    }

    @TestVisible
    private static Map<String, String> loadDestinationOrgCredentials(
        Id comparisonId
    ) {
        List<Metadata_Comparison__c> rows = [
            SELECT
                Destination_Org__r.Refresh_Token__c,
                Destination_Org__r.Instance_URL__c
            FROM Metadata_Comparison__c
            WHERE Id = :comparisonId
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            throw new AuraHandledException('Metadata Comparison was not found.');
        }

        String refreshToken = rows[0].Destination_Org__r.Refresh_Token__c;
        String instanceUrl = rows[0].Destination_Org__r.Instance_URL__c;

        if (String.isBlank(refreshToken) || String.isBlank(instanceUrl)) {
            throw new AuraHandledException(
                'Destination org credentials are not available for drift checks.'
            );
        }

        return new Map<String, String>{
            'refreshToken' => refreshToken,
            'instanceUrl' => instanceUrl
        };
    }

    private static String invokeSessionSubresource(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String subresource,
        String requestJson,
        Integer timeoutMs,
        Boolean attachDestinationCredentials
    ) {
        if (String.isBlank(mergeSessionId)) {
            return failureJson('mergeSessionId is required.');
        }

        try {
            Map<String, Object> body = String.isBlank(requestJson)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(requestJson);

            body.put('comparisonId', String.valueOf(comparisonId));
            body.put('deploymentPlanId', String.valueOf(deploymentPlanId));

            if (attachDestinationCredentials == true) {
                Map<String, String> credentials =
                    loadDestinationOrgCredentials(comparisonId);
                body.put('refreshToken', credentials.get('refreshToken'));
                body.put('instanceUrl', credentials.get('instanceUrl'));
            }

            String encoded = EncodingUtil.urlEncode(
                mergeSessionId.trim(),
                'UTF-8'
            );
            return sendJson(
                'POST',
                System.Label.Backend_Base_URL +
                    SESSIONS_PATH +
                    '/' +
                    encoded +
                    '/' +
                    subresource,
                body,
                timeoutMs
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            return failureJson(
                'Unable to process merge ' + subresource + ' request.'
            );
        }
    }

    private static Object parseJsonArray(String jsonValue) {
        if (String.isBlank(jsonValue)) {
            return new List<Object>();
        }
        return JSON.deserializeUntyped(jsonValue);
    }

    private static String sendJson(
        String method,
        String endpoint,
        Map<String, Object> payload,
        Integer timeoutMs
    ) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(timeoutMs);

        if (payload != null && method != 'GET') {
            req.setBody(JSON.serialize(payload));
        }

        HttpResponse res = new Http().send(req);
        return normalizeHttpBody(res);
    }

    @TestVisible
    private static String normalizeHttpBody(HttpResponse res) {
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
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

    @TestVisible
    private static String failureJson(String message) {
        return JSON.serialize(
            new Map<String, Object>{
                'success' => false,
                'error' => message
            }
        );
    }
}