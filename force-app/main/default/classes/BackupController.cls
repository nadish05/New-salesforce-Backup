public with sharing class BackupController {

    // ========================================
    // Start Backup
    // ========================================

    @AuraEnabled
    public static String startBackup(

        String connectedOrgId,
        String repoUrl

    ) {

        try {

            // ====================================
            // Fetch Connected Org
            // ====================================

            Connected_Org__c orgRecord = [

                SELECT
                    Id,
                    Name,
                    Environment__c,
                    Named_Credential__c,
                    Instance_URL__c

                FROM Connected_Org__c

                WHERE Id = :connectedOrgId

                LIMIT 1

            ];

            // ====================================
            // Get Access Token
            // ====================================

            String accessToken =

                SalesforceTokenService.getAccessToken(

                    orgRecord.Named_Credential__c

                );

            System.debug(

                'ACCESS TOKEN VALUE: ' +

                accessToken

            );

            // ====================================
            // Build Payload
            // ====================================

            Map<String, Object> payload =

                new Map<String, Object>{

                    'connectedOrgId' =>
                        orgRecord.Id,

                    'orgName' =>
                        orgRecord.Name,

                    'environment' =>
                        orgRecord.Environment__c,

                    'namedCredential' =>
                        orgRecord.Named_Credential__c,

                    'instanceUrl' =>
                        orgRecord.Instance_URL__c,

                    'accessToken' =>
                        accessToken,

                    'repoUrl' =>
                        repoUrl

                };

            // ====================================
            // HTTP Request
            // ====================================

            HttpRequest req =
                new HttpRequest();

            req.setEndpoint(
                'callout:Backup_API/execute-backup'
            );

            req.setMethod('POST');

            req.setHeader(
                'Content-Type',
                'application/json'
            );

            System.debug(

                'FINAL PAYLOAD: ' +

                JSON.serializePretty(payload)

            );

            req.setBody(
                JSON.serialize(payload)
            );

            Http http =
                new Http();

            HttpResponse res =
                http.send(req);

            return res.getBody();

        } catch (Exception e) {

            System.debug(
                e.getMessage()
            );

            System.debug(
                e.getStackTraceString()
            );

            return JSON.serialize(

                new Map<String, Object>{

                    'success' => false,

                    'message' => e.getMessage()

                }

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

        return BackupService.getLogs(
            jobId
        );

    }

}