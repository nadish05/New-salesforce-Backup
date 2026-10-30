public with sharing class TestNamedCredential {

    @AuraEnabled
    public static String testConnection() {

        HttpRequest req =
            new HttpRequest();

        req.setEndpoint(
            'callout:MyOrg/services/data/v66.0/'
        );

        req.setMethod('GET');

        Http http =
            new Http();

        HttpResponse res =
            http.send(req);

        System.debug(
            res.getBody()
        );

        return res.getBody();

    }

}