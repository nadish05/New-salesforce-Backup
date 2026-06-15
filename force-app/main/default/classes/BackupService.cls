public with sharing class BackupService {

    // ========================================
    // Connect Salesforce
    // ========================================

    @AuraEnabled
    public static String connectSalesforce(

        String clientId,

        String clientSecret,

        String environment

    ) {

        try {

            Http http =
                new Http();

            HttpRequest request =
                new HttpRequest();

            request.setEndpoint(
                'callout:Backup_API/connect-salesforce'
            );

            request.setMethod('POST');

            request.setHeader(
                'Content-Type',
                'application/json'
            );

            Map<String, String> body =
                new Map<String, String>{

                    'clientId' =>
                        clientId,

                    'clientSecret' =>
                        clientSecret,

                    'environment' =>
                        environment

                };

            request.setBody(
                JSON.serialize(body)
            );

            HttpResponse response =
                http.send(request);

            return response.getBody();

        } catch (Exception e) {

            throw new AuraHandledException(

                e.getMessage()

            );

        }

    }

    // ========================================
    // Start Backup
    // ========================================

    @AuraEnabled
    public static String startBackup(

        String sessionId,

        String repoUrl

    ) {

        try {

            Http http =
                new Http();

            HttpRequest request =
                new HttpRequest();

            request.setEndpoint(
                'callout:Backup_API/execute-backup'
            );

            request.setMethod('POST');

            request.setHeader(
                'Content-Type',
                'application/json'
            );

            Map<String, String> body =
                new Map<String, String>{

                    'sessionId' =>
                        sessionId,

                    'repoUrl' =>
                        repoUrl

                };

            request.setBody(
                JSON.serialize(body)
            );

            HttpResponse response =
                http.send(request);

            return response.getBody();

        } catch (Exception e) {

            throw new AuraHandledException(

                e.getMessage()

            );

        }

    }

    // ========================================
    // Get Logs
    // ========================================

    @AuraEnabled
    public static String getLogs(

        String jobId

    ) {

        try {

            Http http =
                new Http();

            HttpRequest request =
                new HttpRequest();

            request.setEndpoint(

                'callout:Backup_API/logs/' +

                jobId

            );

            request.setMethod('GET');

            HttpResponse response =
                http.send(request);

            return response.getBody();

        } catch (Exception e) {

            throw new AuraHandledException(

                e.getMessage()

            );

        }

    }

}