public with sharing class ConnectedOrgController {

    @AuraEnabled(cacheable=true)
    public static List<Connected_Org__c> getConnectedOrgs() {

        return [
            SELECT
                Id,
                Name,
                Display_Name__c,
                Org_ID__c,
                Instance_URL__c,
                Environment__c,
                Active__c,
                Last_Backup__c
            FROM Connected_Org__c
            ORDER BY Name
        ];
    }

    @AuraEnabled
public static void saveConnectedOrg(
    String orgId,
    String instanceUrl,
    String refreshToken,
    String displayName
) {

    Connected_Org__c orgRec =
        new Connected_Org__c();

    orgRec.Name = displayName;

    orgRec.Display_Name__c = displayName;

    orgRec.Org_ID__c = orgId;

    orgRec.Instance_URL__c = instanceUrl;

    orgRec.Refresh_Token__c = refreshToken;

    orgRec.Active__c = true;

    insert orgRec;
}

@AuraEnabled
public static String getLatestOAuthResult() {

    Http http = new Http();

    HttpRequest req = new HttpRequest();

    req.setEndpoint(
        'https://metadata-backup-backend.onrender.com/api/oauth/latest'
    );

    req.setMethod('GET');

    HttpResponse res = http.send(req);

    return res.getBody();
}

@AuraEnabled
public static Connected_Org__c getOrgDetails(
    Id orgRecordId
) {

    return [
        SELECT
            Id,
            Org_ID__c,
            Instance_URL__c,
            Refresh_Token__c
        FROM Connected_Org__c
        WHERE Id = :orgRecordId
        LIMIT 1
    ];

}

}