public with sharing class DeploymentReviewController {

    @AuraEnabled
    public static String getDeploymentReview(
        Id comparisonId,
        String selectedMetadataJson
    ) {

        Metadata_Comparison__c comparison = [

            SELECT
                Source_Branch__c,
                Destination_Branch__c

            FROM Metadata_Comparison__c

            WHERE Id = :comparisonId

            LIMIT 1
        ];

        Map<String, Object> payload =
            new Map<String, Object>();

        payload.put(
            'comparisonId',
            comparisonId
        );

        payload.put(
            'repoUrl',
            System.Label.GitHub_Repo_URL
        );

        payload.put(
            'sourceBranch',
            comparison.Source_Branch__c
        );

        payload.put(
            'destinationBranch',
            comparison.Destination_Branch__c
        );

        payload.put(
            'selectedMetadata',
            JSON.deserializeUntyped(
                selectedMetadataJson
            )
        );

        Http http = new Http();

        HttpRequest req = new HttpRequest();

        req.setEndpoint(
            System.Label.Backend_Base_URL +
            '/api/deployment/review'
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