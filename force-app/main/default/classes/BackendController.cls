public with sharing class BackendController {

    @AuraEnabled
    public static String checkBackendConnection() {

        Http http = new Http();

        HttpRequest request = new HttpRequest();

        request.setEndpoint(
            System.Label.Backend_Base_URL + '/api/health'
        );

        request.setMethod('GET');

        HttpResponse response = http.send(request);

        return response.getBody();
    }
//status
@AuraEnabled
public static String getMigrationStatus() {

    Http http = new Http();

    HttpRequest request = new HttpRequest();

    request.setEndpoint(
        System.Label.Backend_Base_URL + '/api/github/migration/status'
    );

    request.setMethod('GET');

    HttpResponse response = http.send(request);

    return response.getBody();
}

@AuraEnabled
public static String getOAuthUrl(
    String environment
) {

    Http http = new Http();

    HttpRequest request =
        new HttpRequest();

    request.setEndpoint(
        System.Label.Backend_Base_URL + '/api/oauth/start?environment='
        +
        EncodingUtil.urlEncode(
            environment,
            'UTF-8'
        )
    );

    request.setMethod('GET');

    HttpResponse response =
        http.send(request);

    return response.getBody();

}

@AuraEnabled
public static String startMigration(
    String refreshToken,
    String instanceUrl,
    String repoUrl,
    String branchName
) {

    Http http = new Http();

    HttpRequest req = new HttpRequest();

    req.setTimeout(120000);

    req.setEndpoint(
        System.Label.Backend_Base_URL + '/api/github/migrate'
    );

    req.setMethod('POST');

    req.setHeader(
        'Content-Type',
        'application/json'
    );

    Map<String,Object> payload =
        new Map<String,Object>();

    payload.put(
        'refreshToken',
        refreshToken
    );

    payload.put(
        'instanceUrl',
        instanceUrl
    );

    payload.put(
        'repoUrl',
        repoUrl
    );
    payload.put(
        'branchName',
        branchName
    );

    req.setBody(
        JSON.serialize(payload)
    );

    req.setTimeout(
        120000
    );

    HttpResponse res =
        http.send(req);

    return res.getBody();

}
@AuraEnabled
public static String startComparisonMigration(
    String refreshToken,
    String instanceUrl,
    String branchName
) {

    Http http = new Http();

    HttpRequest req = new HttpRequest();

    req.setEndpoint(
        System.Label.Backend_Base_URL + '/api/github/migrate'
    );

    req.setMethod('POST');

    req.setHeader(
        'Content-Type',
        'application/json'
    );

    Map<String,Object> payload =
        new Map<String,Object>();

    payload.put(
        'refreshToken',
        refreshToken
    );

    payload.put(
        'instanceUrl',
        instanceUrl
    );

    payload.put(
        'repoUrl',
        System.Label.GitHub_Repo_URL
    );

    payload.put(
        'branchName',
        branchName
    );

    req.setBody(
        JSON.serialize(payload)
    );

    HttpResponse res =
        http.send(req);

    return res.getBody();

}

@AuraEnabled
public static String compareBranches(
    String sourceBranch,
    String destinationBranch
) {

    Http http = new Http();

    HttpRequest req =
        new HttpRequest();

    req.setEndpoint(
        System.Label.Backend_Base_URL + '/api/compare/files'
    );

    req.setMethod('POST');

    req.setHeader(
        'Content-Type',
        'application/json'
    );

    Map<String,Object> payload =
        new Map<String,Object>();

    payload.put(
        'repoUrl',
        System.Label.GitHub_Repo_URL
    );

    payload.put(
        'sourceBranch',
        sourceBranch
    );

    payload.put(
        'destinationBranch',
        destinationBranch
    );

    req.setBody(
        JSON.serialize(payload)
    );

    HttpResponse res =
        http.send(req);

    return res.getBody();

}

@AuraEnabled
public static String getDifferenceReport(
    String sourceBranch,
    String destinationBranch,
    String filePath
) {

    Http http = new Http();

    HttpRequest req =
        new HttpRequest();

    req.setEndpoint(
        System.Label.Backend_Base_URL + '/api/compare/report'
    );

    req.setMethod('POST');

    req.setHeader(
        'Content-Type',
        'application/json'
    );

    Map<String, Object> payload =
        new Map<String, Object>();

    payload.put(
        'repoUrl',
        System.Label.GitHub_Repo_URL
    );

    payload.put(
        'sourceBranch',
        sourceBranch
    );

    payload.put(
        'destinationBranch',
        destinationBranch
    );

    payload.put(
        'filePath',
        filePath
    );

    req.setBody(
        JSON.serialize(payload)
    );

    HttpResponse response =
        http.send(req);

    return response.getBody();
}

    /**
     * Compares User Licenses between source and destination connected orgs
     * via backend POST /api/org/licenses/compare.
     */
    @AuraEnabled
    public static String compareUserLicenses(
        String sourceRefreshToken,
        String sourceInstanceUrl,
        String sourceOrgId,
        String destinationRefreshToken,
        String destinationInstanceUrl,
        String destinationOrgId
    ) {
        if (
            String.isBlank(sourceRefreshToken) ||
            String.isBlank(sourceInstanceUrl) ||
            String.isBlank(sourceOrgId) ||
            String.isBlank(destinationRefreshToken) ||
            String.isBlank(destinationInstanceUrl) ||
            String.isBlank(destinationOrgId)
        ) {
            return JSON.serialize(
                new Map<String, Object>{
                    'success' => false,
                    'statusCode' => 400,
                    'error' =>
                        'Source and destination org connection details are required.'
                }
            );
        }

        Map<String, Object> payload = new Map<String, Object>{
            'source' => new Map<String, Object>{
                'refreshToken' => sourceRefreshToken,
                'instanceUrl' => sourceInstanceUrl,
                'orgId' => sourceOrgId
            },
            'destination' => new Map<String, Object>{
                'refreshToken' => destinationRefreshToken,
                'instanceUrl' => destinationInstanceUrl,
                'orgId' => destinationOrgId
            }
        };

        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            System.Label.Backend_Base_URL + '/api/org/licenses/compare'
        );
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(120000);

        HttpResponse res = http.send(req);

        if (
            res.getStatusCode() >= 200 &&
            res.getStatusCode() < 300
        ) {
            return res.getBody();
        }

        String body = res.getBody();

        if (String.isNotBlank(body)) {
            return body;
        }

        return JSON.serialize(
            new Map<String, Object>{
                'success' => false,
                'statusCode' => res.getStatusCode(),
                'error' => res.getStatus()
            }
        );
    }
}