@RestResource(urlMapping='/connectedOrg/*')
global with sharing class ConnectedOrgRest {

    @HttpPost
    global static String createOrg() {

        RestRequest req = RestContext.request;

        String body = req.requestBody.toString();

        Map<String,Object> data =
            (Map<String,Object>) JSON.deserializeUntyped(body);

        Connected_Org__c orgRec = new Connected_Org__c();

        orgRec.Name =
            (String)data.get('orgName');

        orgRec.Org_ID__c =
            (String)data.get('orgId');

        orgRec.Instance_URL__c =
            (String)data.get('instanceUrl');

        orgRec.Refresh_Token__c =
            (String)data.get('refreshToken');

        orgRec.Active__c = true;

        insert orgRec;

        return 'SUCCESS';
    }
}