public with sharing class SalesforceTokenService {

    public static String getAccessToken(
        String namedCredential
    ) {

        HttpRequest req =

            new HttpRequest();

        req.setEndpoint(
            'callout:' + namedCredential
        );

        req.setMethod('GET');

        Http http = new Http();

        HttpResponse res =
            http.send(req);

        System.debug(
            'STATUS CODE: ' +
            res.getStatusCode()
        );

        System.debug(
            'AUTH HEADER: ' +
            req.getHeader('Authorization')
        );

        System.debug(
            'RESPONSE HEADERS: ' +
            res.getHeaderKeys()
        );

        String authHeader =

            req.getHeader(
                'Authorization'
            );

        if (String.isBlank(authHeader)) {

            System.debug(
                'AUTH HEADER IS NULL'
            );

            return null;
        }

        return authHeader.replace(
            'Bearer ',
            ''
        );

    }

    
public static String getInstanceUrl(
    String namedCredential
) {

    return URL.getOrgDomainUrl()
        .toExternalForm();

}



}