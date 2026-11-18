/**
 * HttpCalloutMock tests for ApexMergeController.
 */
@IsTest
private class ApexMergeControllerTest {

    private static final String MOCK_RT = 'must-never-appear-in-response';

    private virtual class MergeHttpMock implements HttpCalloutMock {
        String method;
        String endpoint;
        String body;
        Integer statusCode;
        String responseBody;

        MergeHttpMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HTTPResponse respond(HTTPRequest req) {
            this.method = req.getMethod();
            this.endpoint = req.getEndpoint();
            this.body = req.getBody();

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            res.setStatus(statusCode >= 200 && statusCode < 300 ? 'OK' : 'Error');
            return res;
        }
    }

    private class MergeCaptureMock extends MergeHttpMock {
        MergeCaptureMock(Integer statusCode, String responseBody) {
            super(statusCode, responseBody);
        }
    }

    @IsTest
    static void createMergeSession_validPlan_postsSessionsEndpoint() {
        Id comparisonId = seedComparisonAndPlan();
        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        MergeCaptureMock mock = new MergeCaptureMock(
            200,
            '{"success":true,"mergeSessionId":"sess_1"}'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = ApexMergeController.createMergeSession(
            comparisonId,
            plan.Id,
            '[{"metadataName":"Foo","classFilePath":"classes/Foo.cls"}]'
        );
        Test.stopTest();

        System.assert(result.contains('sess_1'), result);
        System.assert(
            mock.endpoint.contains('/api/merge/apex/sessions'),
            mock.endpoint
        );
        System.assertEquals('POST', mock.method);
        System.assert(
            !result.contains(MOCK_RT),
            'Response must not leak credentials'
        );
        Map<String, Object> req =
            (Map<String, Object>) JSON.deserializeUntyped(mock.body);
        System.assert(req.containsKey('comparisonId'));
        System.assert(req.containsKey('deploymentPlanId'));
        System.assert(req.containsKey('repoUrl'));
        System.assert(req.containsKey('classes'));
        System.assert(req.containsKey('eligibleClasses'));
    }

    @IsTest
    static void createMergeSession_wrongComparison_throws() {
        Id comparisonId = seedComparisonAndPlan();
        Id otherComparisonId = seedComparisonOnly();

        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        Boolean thrown = false;
        try {
            ApexMergeController.createMergeSession(
                otherComparisonId,
                plan.Id,
                '[]'
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Expected plan/comparison mismatch to throw');
    }

    @IsTest
    static void previewClassMerge_postsPreviewSubresource() {
        Id comparisonId = seedComparisonAndPlan();
        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        MergeCaptureMock mock = new MergeCaptureMock(
            200,
            '{"success":true,"status":"PREVIEWED"}'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = ApexMergeController.previewClassMerge(
            comparisonId,
            plan.Id,
            'sess_preview',
            '{"metadataName":"Foo","mode":"FULL"}'
        );
        Test.stopTest();

        System.assert(result.contains('PREVIEWED'), result);
        System.assert(
            mock.endpoint.endsWith('/sess_preview/preview'),
            mock.endpoint
        );
    }

    @IsTest
    static void resolveClassMerge_postsResolveSubresource() {
        Id comparisonId = seedComparisonAndPlan();
        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        MergeCaptureMock mock = new MergeCaptureMock(
            200,
            '{"success":true,"status":"RESOLVED"}'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = ApexMergeController.resolveClassMerge(
            comparisonId,
            plan.Id,
            'sess_resolve',
            '{"metadataName":"Foo","mode":"FULL","resolutionStrategy":"ACCEPT_SOURCE"}'
        );
        Test.stopTest();

        System.assert(result.contains('RESOLVED'), result);
        System.assert(
            mock.endpoint.endsWith('/sess_resolve/resolve'),
            mock.endpoint
        );
        System.assertEquals('POST', mock.method);
    }

    @IsTest
    static void publishClassMerge_success_postsPublishSubresource() {
        Id comparisonId = seedComparisonAndPlan();
        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        String backendResponse =
            '{"success":true,"publishState":"PUBLISHED","publishedCommitSha":"abc123def456",' +
            '"publishedAt":"2026-11-17T10:00:00.000Z",' +
            '"publishedClasses":[{"metadataName":"WeatherService","filePath":"force-app/main/default/classes/WeatherService.cls"}],' +
            '"inputMergePins":{"sourceHeadSha":"abc123def456","destinationHeadSha":"dst000"}}';

        MergeCaptureMock mock = new MergeCaptureMock(200, backendResponse);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = ApexMergeController.publishClassMerge(
            comparisonId,
            plan.Id,
            'sess_publish',
            '{"metadataNames":["WeatherService"]}'
        );
        Test.stopTest();

        System.assert(
            mock.endpoint.endsWith('/sess_publish/publish'),
            'Publish endpoint: ' + mock.endpoint
        );
        System.assertEquals('POST', mock.method);

        Map<String, Object> req =
            (Map<String, Object>) JSON.deserializeUntyped(mock.body);
        System.assertEquals(String.valueOf(comparisonId), req.get('comparisonId'));
        System.assertEquals(String.valueOf(plan.Id), req.get('deploymentPlanId'));
        List<Object> names = (List<Object>) req.get('metadataNames');
        System.assertEquals(1, names.size());
        System.assertEquals('WeatherService', names[0]);
        System.assert(
            !req.containsKey('refreshToken'),
            'Publish must not attach destination credentials'
        );
        System.assert(
            !req.containsKey('repoUrl'),
            'Publish must not accept client repoUrl'
        );

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(true, parsed.get('success'));
        System.assertEquals('PUBLISHED', parsed.get('publishState'));
        System.assertEquals(
            'abc123def456',
            parsed.get('publishedCommitSha'),
            'publishedCommitSha must reach caller'
        );
        System.assert(
            result.contains('WeatherService'),
            'publishedClasses must be preserved'
        );
    }

    @IsTest
    static void publishClassMerge_staleSourceHead_returnsBackendErrorBody() {
        Id comparisonId = seedComparisonAndPlan();
        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        String errorBody =
            '{"success":false,"code":"STALE_GIT_PINS","error":"Git branch HEAD SHAs changed since session creation."}';
        MergeCaptureMock mock = new MergeCaptureMock(409, errorBody);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = ApexMergeController.publishClassMerge(
            comparisonId,
            plan.Id,
            'sess_stale',
            '{"metadataNames":["WeatherService"]}'
        );
        Test.stopTest();

        System.assert(result.contains('STALE_GIT_PINS'), result);
        System.assert(result.contains('HEAD SHAs changed'), result);
        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertNotEquals(true, parsed.get('success'));
    }

    @IsTest
    static void publishClassMerge_unresolvedConflict_returnsBackendErrorBody() {
        Id comparisonId = seedComparisonAndPlan();
        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        String errorBody =
            '{"success":false,"code":"UNRESOLVED_CONFLICT","error":"Missing resolution for WeatherService."}';
        MergeCaptureMock mock = new MergeCaptureMock(400, errorBody);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = ApexMergeController.publishClassMerge(
            comparisonId,
            plan.Id,
            'sess_unresolved',
            '{"metadataNames":["WeatherService"]}'
        );
        Test.stopTest();

        System.assert(result.contains('UNRESOLVED_CONFLICT'), result);
        System.assert(
            !result.contains('"success":true'),
            'Must not report success on unresolved conflict'
        );
    }

    @IsTest
    static void publishClassMerge_backendHttpError_preservesStatus() {
        Id comparisonId = seedComparisonAndPlan();
        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        MergeCaptureMock mock = new MergeCaptureMock(
            503,
            '{"success":false,"error":"Backend unavailable"}'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = ApexMergeController.publishClassMerge(
            comparisonId,
            plan.Id,
            'sess_503',
            '{"metadataNames":["WeatherService"]}'
        );
        Test.stopTest();

        System.assert(result.contains('Backend unavailable'), result);
    }

    @IsTest
    static void publishClassMerge_backendHttpError_emptyBody_returnsFallbackJson() {
        Id comparisonId = seedComparisonAndPlan();
        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        MergeCaptureMock mock = new MergeCaptureMock(502, '');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = ApexMergeController.publishClassMerge(
            comparisonId,
            plan.Id,
            'sess_502',
            '{"metadataNames":["WeatherService"]}'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals(502, parsed.get('statusCode'));
    }

    @IsTest
    static void publishClassMerge_wrongComparison_throws() {
        Id comparisonId = seedComparisonAndPlan();
        Id otherComparisonId = seedComparisonOnly();
        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        Boolean thrown = false;
        try {
            ApexMergeController.publishClassMerge(
                otherComparisonId,
                plan.Id,
                'sess_bad',
                '{"metadataNames":["WeatherService"]}'
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Expected plan/comparison mismatch to throw');
    }

    @IsTest
    static void publishClassMerge_blankSessionId_returnsFailureJson() {
        Id comparisonId = seedComparisonAndPlan();
        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        Test.startTest();
        String result = ApexMergeController.publishClassMerge(
            comparisonId,
            plan.Id,
            '',
            '{"metadataNames":["WeatherService"]}'
        );
        Test.stopTest();

        System.assert(result.contains('mergeSessionId is required'), result);
    }

    @IsTest
    static void sealMergeManifest_postsSealSubresource() {
        Id comparisonId = seedComparisonAndPlan();
        Deployment_Plan__c plan = [
            SELECT Id
            FROM Deployment_Plan__c
            WHERE Metadata_Comparison__c = :comparisonId
            LIMIT 1
        ];

        MergeCaptureMock mock = new MergeCaptureMock(
            200,
            '{"success":true,"apexMergeManifest":{"mergeManifestId":"man_1"},"mergeManifestId":"man_1"}'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = ApexMergeController.sealMergeManifest(
            comparisonId,
            plan.Id,
            'sess_seal'
        );
        Test.stopTest();

        System.assert(result.contains('man_1'), result);
        System.assert(
            mock.endpoint.endsWith('/sess_seal/seal'),
            mock.endpoint
        );
    }

    private static Id seedComparisonOnly() {
        Connected_Org__c src = new Connected_Org__c(
            Name = 'Src',
            Org_ID__c = '00Dsrc0000000099',
            Instance_URL__c = 'https://src.example.com',
            Refresh_Token__c = MOCK_RT,
            Active__c = true
        );
        Connected_Org__c dst = new Connected_Org__c(
            Name = 'Dst',
            Org_ID__c = '00Ddst0000000098',
            Instance_URL__c = 'https://dst.example.com',
            Refresh_Token__c = MOCK_RT,
            Active__c = true
        );
        insert new List<Connected_Org__c>{ src, dst };

        Metadata_Comparison__c comparison = new Metadata_Comparison__c(
            Name = 'Cmp Other',
            Source_Org__c = src.Id,
            Destination_Org__c = dst.Id,
            Source_Branch__c = 'gym',
            Destination_Branch__c = 'agent'
        );
        insert comparison;
        return comparison.Id;
    }

    private static Id seedComparisonAndPlan() {
        Connected_Org__c src = new Connected_Org__c(
            Name = 'Src',
            Org_ID__c = '00Dsrc0000000001',
            Instance_URL__c = 'https://src.example.com',
            Refresh_Token__c = MOCK_RT,
            Active__c = true
        );
        Connected_Org__c dst = new Connected_Org__c(
            Name = 'Dst',
            Org_ID__c = '00Ddst0000000002',
            Instance_URL__c = 'https://dst.example.com',
            Refresh_Token__c = MOCK_RT,
            Active__c = true
        );
        insert new List<Connected_Org__c>{ src, dst };

        Metadata_Comparison__c comparison = new Metadata_Comparison__c(
            Name = 'Cmp Merge',
            Source_Org__c = src.Id,
            Destination_Org__c = dst.Id,
            Source_Branch__c = 'gym',
            Destination_Branch__c = 'agent'
        );
        insert comparison;

        insert new Deployment_Plan__c(
            Name = 'DP-Merge-Test',
            Metadata_Comparison__c = comparison.Id,
            Source_Org__c = src.Id,
            Destination_Org__c = dst.Id,
            Status__c = 'Draft'
        );

        return comparison.Id;
    }
}