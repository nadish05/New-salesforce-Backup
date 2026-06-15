public with sharing class BackendController {

    @AuraEnabled
    public static String checkBackendConnection() {

        Http http = new Http();

        HttpRequest request = new HttpRequest();

        request.setEndpoint(
            'https://metadata-backup-backend.onrender.com/api/health'
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
        'https://metadata-backup-backend.onrender.com/api/github/migration/status'
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
        'https://metadata-backup-backend.onrender.com/api/oauth/start?environment='
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
        'https://metadata-backup-backend.onrender.com/api/github/migrate'
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
        'https://metadata-backup-backend.onrender.com/api/github/migrate'
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
        'https://metadata-backup-backend.onrender.com/api/compare/files'
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
        'https://metadata-backup-backend.onrender.com/api/compare/report'
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
}