public with sharing class SourceValidationController {

    @AuraEnabled
    public static String validateDeployment(
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

        payload.put(
            'deploymentPackage',
            JSON.deserializeUntyped(
                deploymentPackage
            )
        );

        Http http = new Http();

        HttpRequest req = new HttpRequest();

        req.setEndpoint(
            System.Label.Backend_Base_URL +
            '/api/deployment/source-validation'
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