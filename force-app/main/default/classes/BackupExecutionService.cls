public with sharing class BackupExecutionService {

    // =========================================
    // EXECUTE BACKUP
    // =========================================

    @AuraEnabled
    public static String executeBackup(

        Id connectedOrgId,

        String repoUrl,

        String clientId,

        String clientSecret

    ) {

        try {

            // =====================================
            // Get Connected Org
            // =====================================

            
Connected_Org__c orgRecord = [

    SELECT

        Id,

        Name,

        Org_Id__c,

        Instance_Url__c,

        Refresh_Token__c,

        Environment__c,

        Active__c

    FROM Connected_Org__c

    WHERE Id = :connectedOrgId

    LIMIT 1

];



            // =====================================
            // Backend Request Body
            // =====================================

            Map<String, Object> payload =

                new Map<String, Object>{

                    'connectedOrgId' =>
                        orgRecord.Id,

                    'orgName' =>
                        orgRecord.Name,

                    'environment' =>
                        orgRecord.Environment__c,

                    'instanceUrl' =>
                        orgRecord.Instance_Url__c,

                    'refreshToken' =>
                        orgRecord.Refresh_Token__c,

                    'clientId' =>
                        clientId,

                    'clientSecret' =>
                        clientSecret,

                    'repoUrl' =>
                        repoUrl

                };

            // =====================================
            // HTTP Request
            // =====================================

            HttpRequest req =
                new HttpRequest();

            req.setEndpoint(

                'https://salesforce-backup-backend-1.onrender.com/execute-backup'

            );

            req.setMethod('POST');

            req.setHeader(

                'Content-Type',

                'application/json'

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

            throw new AuraHandledException(

                e.getMessage()

            );

        }

    }

}