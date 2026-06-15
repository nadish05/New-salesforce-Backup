public with sharing class MetadataConnectionTest {

    @AuraEnabled
    public static String testMetadataAccess() {

        HttpRequest req =
            new HttpRequest();

        req.setEndpoint(

            'callout:MyOrg/' +

            'services/data/v66.0/tooling/query/?q=' +

            EncodingUtil.urlEncode(

                'SELECT Id, Name FROM ApexClass LIMIT 5',

                'UTF-8'

            )

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