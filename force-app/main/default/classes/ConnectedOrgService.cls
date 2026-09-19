public with sharing class ConnectedOrgService {

    // =========================================
    // SAVE CONNECTED ORG
    // =========================================

    @AuraEnabled
    public static Id saveConnectedOrg(

        String orgId,

        String orgName,

        String instanceUrl,

        String refreshToken,

        String environment

    ) {

        List<Connected_Org__c> existing = [

            SELECT Id

            FROM Connected_Org__c

            WHERE Org_Id__c = :orgId

            LIMIT 1

        ];

        Connected_Org__c orgRecord;

        if (!existing.isEmpty()) {

            orgRecord = existing[0];

        } else {

            orgRecord =
                new Connected_Org__c();

        }

        orgRecord.Name =
            orgName;

        orgRecord.Org_Id__c =
            orgId;

        orgRecord.Instance_Url__c =
            instanceUrl;

        orgRecord.Refresh_Token__c =
            refreshToken;

        orgRecord.Environment__c =
            environment;

        orgRecord.Active__c =
            true;

        upsert orgRecord;

        return orgRecord.Id;

    }

    // =========================================
    // GET CONNECTED ORGS
    // =========================================

    @AuraEnabled(cacheable=true)
    public static List<Connected_Org__c>
    getConnectedOrgs() {

        return [

            SELECT

                Id,

                Name,

                Org_Id__c,

                Instance_Url__c,

                Refresh_Token__c,

                Environment__c,

                Active__c,

                Last_Backup__c

            FROM Connected_Org__c

            ORDER BY CreatedDate DESC

        ];

    }

    // =========================================
    // GET SINGLE CONNECTED ORG
    // =========================================

    @AuraEnabled(cacheable=true)
    public static Connected_Org__c
    getConnectedOrg(

        Id connectedOrgId

    ) {

        return [

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

    }

    
@AuraEnabled
public static Id saveOAuthOrg(

    String orgId,

    String orgName,

    String instanceUrl,

    String refreshToken,

    String environment

) {

    return saveConnectedOrg(

        orgId,

        orgName,

        instanceUrl,

        refreshToken,

        environment

    );

}



}