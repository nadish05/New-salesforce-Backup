/**
 * HttpCalloutMock tests for BackendController license comparison transport.
 */
@IsTest
private class BackendControllerTest {

    private static final String SOURCE_RT = 'source-refresh-token-test';
    private static final String DEST_RT = 'destination-refresh-token-test';

    private class LicenseCompareMock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        String capturedEndpoint;
        String capturedBody;

        LicenseCompareMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            this.capturedEndpoint = req.getEndpoint();
            this.capturedBody = req.getBody();

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody(body);
            res.setStatus(statusCode >= 200 && statusCode < 300 ? 'OK' : 'Error');
            return res;
        }
    }

    private static void assertRequestContract(String capturedBody) {
        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(capturedBody);

        System.assert(request.containsKey('source'));
        System.assert(request.containsKey('destination'));

        Map<String, Object> source =
            (Map<String, Object>) request.get('source');
        Map<String, Object> destination =
            (Map<String, Object>) request.get('destination');

        System.assertEquals(SOURCE_RT, source.get('refreshToken'));
        System.assertEquals(
            'https://source.example.my.salesforce.com',
            source.get('instanceUrl')
        );
        System.assertEquals('00Dsource000000001', source.get('orgId'));

        System.assertEquals(DEST_RT, destination.get('refreshToken'));
        System.assertEquals(
            'https://dest.example.my.salesforce.com',
            destination.get('instanceUrl')
        );
        System.assertEquals('00Ddest0000000002', destination.get('orgId'));
    }

    private static void assertNoCredentialsInResponse(String result) {
        System.assert(
            !result.contains(SOURCE_RT),
            'Response must not include source refresh token'
        );
        System.assert(
            !result.contains(DEST_RT),
            'Response must not include destination refresh token'
        );
    }

    private static String invokeCompareUserLicenses() {
        return BackendController.compareUserLicenses(
            SOURCE_RT,
            'https://source.example.my.salesforce.com',
            '00Dsource000000001',
            DEST_RT,
            'https://dest.example.my.salesforce.com',
            '00Ddest0000000002'
        );
    }

    @IsTest
    static void testCompareUserLicensesSuccess() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'success' => true,
                'sourceOrgId' => '00Dsource000000001',
                'destinationOrgId' => '00Ddest0000000002',
                'source' => new Map<String, Object>{
                    'licenses' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'Salesforce',
                            'totalLicenses' => 10,
                            'usedLicenses' => 5
                        }
                    }
                },
                'destination' => new Map<String, Object>{
                    'licenses' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'Salesforce',
                            'totalLicenses' => 8,
                            'usedLicenses' => 4
                        }
                    }
                },
                'both' => new List<Object>(),
                'sourceOnly' => new List<Object>(),
                'destinationOnly' => new List<Object>(),
                'unmatched' => new List<Object>(),
                'warnings' => new List<Object>()
            }
        );

        LicenseCompareMock mock = new LicenseCompareMock(200, responseBody);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = invokeCompareUserLicenses();
        Test.stopTest();

        assertNoCredentialsInResponse(result);
        System.assert(
            mock.capturedEndpoint.contains('/api/org/licenses/compare'),
            'Must call license compare endpoint'
        );
        assertRequestContract(mock.capturedBody);

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(true, parsed.get('success'));
        System.assert(parsed.containsKey('source'));
        System.assert(parsed.containsKey('destination'));
        System.assert(parsed.containsKey('both'));
        System.assert(parsed.containsKey('warnings'));
    }

    @IsTest
    static void testCompareUserLicensesSourceOnlyAndDestinationOnly() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'success' => true,
                'sourceOrgId' => '00Dsource000000001',
                'destinationOrgId' => '00Ddest0000000002',
                'source' => new Map<String, Object>{
                    'licenses' => new List<Object>()
                },
                'destination' => new Map<String, Object>{
                    'licenses' => new List<Object>()
                },
                'both' => new List<Object>(),
                'sourceOnly' => new List<Object>{
                    new Map<String, Object>{ 'name' => 'Chatter Only' }
                },
                'destinationOnly' => new List<Object>{
                    new Map<String, Object>{ 'name' => 'Platform' }
                },
                'unmatched' => new List<Object>(),
                'warnings' => new List<Object>()
            }
        );

        LicenseCompareMock mock = new LicenseCompareMock(200, responseBody);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = invokeCompareUserLicenses();
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        List<Object> sourceOnly = (List<Object>) parsed.get('sourceOnly');
        List<Object> destinationOnly = (List<Object>) parsed.get('destinationOnly');

        System.assertEquals(1, sourceOnly.size());
        System.assertEquals(1, destinationOnly.size());
        assertNoCredentialsInResponse(result);
    }

    @IsTest
    static void testCompareUserLicensesBackendErrorBodyPreserved() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'success' => false,
                'failedSide' => 'source',
                'code' => 'AUTH_QUERY_FAILED',
                'error' => 'Unable to query licenses for source org.'
            }
        );

        LicenseCompareMock mock = new LicenseCompareMock(502, responseBody);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = invokeCompareUserLicenses();
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals('source', parsed.get('failedSide'));
        System.assertEquals('AUTH_QUERY_FAILED', parsed.get('code'));
        assertNoCredentialsInResponse(result);
    }

    @IsTest
    static void testCompareUserLicensesMissingArguments() {
        Test.startTest();
        String result = BackendController.compareUserLicenses(
            '',
            'https://source.example.my.salesforce.com',
            '00Dsource000000001',
            DEST_RT,
            'https://dest.example.my.salesforce.com',
            '00Ddest0000000002'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals(400, parsed.get('statusCode'));
        System.assertNotEquals(null, parsed.get('error'));
        assertNoCredentialsInResponse(result);
    }

    @IsTest
    static void testCompareBranchesUnchanged() {
        LicenseCompareMock mock = new LicenseCompareMock(
            200,
            JSON.serialize(new Map<String, Object>{ 'files' => new List<Object>() })
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = BackendController.compareBranches('src-branch', 'dst-branch');
        Test.stopTest();

        System.assert(
            mock.capturedEndpoint.contains('/api/compare/files'),
            'compareBranches must still target file compare endpoint'
        );
        System.assertNotEquals(null, result);

        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('src-branch', request.get('sourceBranch'));
        System.assertEquals('dst-branch', request.get('destinationBranch'));
        System.assert(!request.containsKey('source'));
    }
}