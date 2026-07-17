@RestResource(urlMapping='/migrationjob/*')
global with sharing class MigrationJobApi {

    @HttpPost
    global static void updateJob() {

        RestRequest req = RestContext.request;

        Map<String,Object> body =
            (Map<String,Object>)
            JSON.deserializeUntyped(
                req.requestBody.toString()
            );

        String jobId =
            (String) body.get('jobId');

        String status =
            (String) body.get('status');

        String errorMessage =
            (String) body.get('errorMessage');

        Migration_Job__c job = [

            SELECT
                Id,
                Status__c,
                Error_Message__c

            FROM Migration_Job__c

            WHERE Id = :jobId

            LIMIT 1
        ];

        job.Status__c = status;

        if(errorMessage != null) {

            job.Error_Message__c =
                errorMessage;

        }

        update job;

        RestContext.response.statusCode = 200;
    }
}