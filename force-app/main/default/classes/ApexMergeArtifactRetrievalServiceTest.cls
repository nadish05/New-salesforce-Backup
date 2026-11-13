/**
 * HttpCalloutMock tests for ApexMergeArtifactRetrievalService.
 */
@IsTest
private class ApexMergeArtifactRetrievalServiceTest {

    private static final String MOCK_RT = 'must-never-appear-in-response';
    private static final String SESSION_ID = 'sess_retrieval_1';
    private static final String MANIFEST_ID = 'mfm_retrieval_1';
    private static final String DST_ORG_ID = '00Ddst0000007777';
    private static final String CLS_ARTIFACT =
        'merge/mfm_retrieval_1/classes/Foo/ApexClass/cls';
    private static final String META_ARTIFACT =
        'merge/mfm_retrieval_1/classes/Foo/ApexClass/metaXml';

    private static final String FIXTURE_PLAN_DEFAULT = 'DP-Retrieval';
    private static final String FIXTURE_PLAN_CONFLICT = 'DP-Conflict';
    private static final String FIXTURE_PLAN_RETRY = 'DP-Retry-Idempotent';
    private static final String FIXTURE_PLAN_MISSING_CREDS = 'DP-Missing-Credentials';
    private static final String FIXTURE_CMP_OTHER = 'Cmp Other Retrieval';

    @TestSetup
    static void seedRetrievalFixtures() {
        Connected_Org__c src = new Connected_Org__c(
            Name = 'Src Retrieval',
            Org_ID__c = '00Dsrc0000008881',
            Instance_URL__c = 'https://src-retrieval.example.com',
            Refresh_Token__c = MOCK_RT,
            Active__c = true
        );
        Connected_Org__c dst = new Connected_Org__c(
            Name = 'Dst Retrieval',
            Org_ID__c = DST_ORG_ID,
            Instance_URL__c = 'https://dst-retrieval.example.com',
            Refresh_Token__c = MOCK_RT,
            Active__c = true
        );
        Connected_Org__c dstMissing = new Connected_Org__c(
            Name = 'Dst Missing Creds',
            Instance_URL__c = 'https://dst-missing.example.com',
            Refresh_Token__c = null,
            Active__c = true
        );
        insert new List<Connected_Org__c>{ src, dst, dstMissing };

        Metadata_Comparison__c cmpDefault = new Metadata_Comparison__c(
            Name = 'Cmp Retrieval',
            Source_Org__c = src.Id,
            Destination_Org__c = dst.Id,
            Source_Branch__c = 'gym',
            Destination_Branch__c = 'agent'
        );
        Metadata_Comparison__c cmpOther = new Metadata_Comparison__c(
            Name = FIXTURE_CMP_OTHER,
            Source_Org__c = src.Id,
            Destination_Org__c = dst.Id,
            Source_Branch__c = 'gym',
            Destination_Branch__c = 'agent'
        );
        Metadata_Comparison__c cmpMissing = new Metadata_Comparison__c(
            Name = 'Cmp Missing Credentials',
            Source_Org__c = src.Id,
            Destination_Org__c = dstMissing.Id,
            Source_Branch__c = 'gym',
            Destination_Branch__c = 'agent'
        );
        insert new List<Metadata_Comparison__c>{ cmpDefault, cmpOther, cmpMissing };

        Deployment_Plan__c planDefault = new Deployment_Plan__c(
            Name = FIXTURE_PLAN_DEFAULT,
            Metadata_Comparison__c = cmpDefault.Id,
            Source_Org__c = src.Id,
            Destination_Org__c = dst.Id,
            Status__c = 'Draft'
        );
        Deployment_Plan__c planConflict = new Deployment_Plan__c(
            Name = FIXTURE_PLAN_CONFLICT,
            Metadata_Comparison__c = cmpDefault.Id,
            Source_Org__c = src.Id,
            Destination_Org__c = dst.Id,
            Status__c = 'Draft'
        );
        Deployment_Plan__c planRetry = new Deployment_Plan__c(
            Name = FIXTURE_PLAN_RETRY,
            Metadata_Comparison__c = cmpDefault.Id,
            Source_Org__c = src.Id,
            Destination_Org__c = dst.Id,
            Status__c = 'Draft'
        );
        Deployment_Plan__c planMissing = new Deployment_Plan__c(
            Name = FIXTURE_PLAN_MISSING_CREDS,
            Metadata_Comparison__c = cmpMissing.Id,
            Source_Org__c = src.Id,
            Destination_Org__c = dstMissing.Id,
            Status__c = 'Draft'
        );
        insert new List<Deployment_Plan__c>{
            planDefault,
            planConflict,
            planRetry,
            planMissing
        };

        insertConflictDuplicateMeta(
            planConflict.Id,
            Blob.valueOf('different')
        );

        Blob clsRetry = Blob.valueOf('class Retry {}');
        Blob metaRetry = Blob.valueOf('<ApexClass/>');
        insertStoredArtifact(
            planRetry.Id,
            'Foo',
            'cls',
            CLS_ARTIFACT,
            clsRetry
        );
        insertStoredArtifact(
            planRetry.Id,
            'Foo',
            'metaXml',
            META_ARTIFACT,
            metaRetry
        );
    }

    @IsTest
    static void retrieve_success_clsAndMetaXml() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('public with sharing class Foo {}');
        Blob metaBytes = Blob.valueOf('<?xml version="1.0"?><ApexClass/>');

        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );

        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(true, payload.get('success'), json);
        List<Object> persisted = (List<Object>) payload.get('persistedArtifacts');
        System.assertEquals(2, persisted.size());
        assertNoSecrets(json);
    }

    @IsTest
    static void authorize_httpError_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(503, '{"success":false,"error":"Unavailable"}', null, null)
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('BACKEND_UNAVAILABLE', payload.get('code'));
    }

    @IsTest
    static void binary_emptyResponse_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Test.setMock(
            HttpCalloutMock.class,
            new RoutingMock(
                authBody(true),
                new Map<String, Integer>{ CLS_ARTIFACT => 200, META_ARTIFACT => 200 },
                new Map<String, Blob>{ CLS_ARTIFACT => Blob.valueOf(''), META_ARTIFACT => metaBytes }
            )
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('ARTIFACT_EMPTY', payload.get('code'));
    }

    @IsTest
    static void authorize_failure_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');

        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(401, '{"success":false,"error":"Unauthorized"}', null, null)
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('UNAUTHORIZED', payload.get('code'));
    }

    @IsTest
    static void authorize_mismatchedVerifiedOrgId_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');

        Map<String, Object> auth = authBody(true);
        auth.put('verifiedOrgId', '00Dwrong0000000001');
        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(200, JSON.serialize(auth), null, null)
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('INVALID_RESPONSE', payload.get('code'));
    }

    @IsTest
    static void authorize_mismatchedMergeSessionId_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Map<String, Object> auth = authBody(true);
        auth.put('mergeSessionId', 'sess_other');
        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(200, JSON.serialize(auth), null, null)
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('INVALID_RESPONSE', payload.get('code'));
    }

    @IsTest
    static void authorize_mismatchedMergeManifestId_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Map<String, Object> auth = authBody(true);
        auth.put('mergeManifestId', 'other_manifest');
        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(200, JSON.serialize(auth), null, null)
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('INVALID_RESPONSE', payload.get('code'));
    }

    @IsTest
    static void authorize_unsuccessfulBody_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(
                200,
                '{"success":false,"authorized":false,"error":"Grant denied"}',
                null,
                null
            )
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertNotEquals(null, payload.get('code'));
    }

    @IsTest
    static void binary_sha256Mismatch_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class One {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Blob wrongBytes = Blob.valueOf('class Two {}');

        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(wrongBytes, metaBytes)
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('INTEGRITY_MISMATCH', payload.get('code'));
    }

    @IsTest
    static void binary_byteLengthMismatch_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Test.setMock(
            HttpCalloutMock.class,
            new RoutingMock(
                authBody(true),
                new Map<String, Integer>{
                    CLS_ARTIFACT => 200,
                    META_ARTIFACT => 200
                },
                new Map<String, Blob>{
                    CLS_ARTIFACT => clsBytes,
                    META_ARTIFACT => metaBytes
                },
                null,
                new Map<String, Integer>{
                    CLS_ARTIFACT => clsBytes.size() + 9
                }
            )
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('INTEGRITY_MISMATCH', payload.get('code'));
    }

    @IsTest
    static void missingArtifact_notFound_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Test.setMock(
            HttpCalloutMock.class,
            new RoutingMock(
                authBody(true),
                new Map<String, Integer>{
                    CLS_ARTIFACT => 404,
                    META_ARTIFACT => 200
                },
                new Map<String, Blob>{
                    META_ARTIFACT => metaBytes
                }
            )
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('NOT_FOUND', payload.get('code'));
    }

    @IsTest
    static void expiredHandoff_unauthorized_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Test.setMock(
            HttpCalloutMock.class,
            new RoutingMock(
                authBody(true),
                new Map<String, Integer>{ CLS_ARTIFACT => 403, META_ARTIFACT => 403 },
                new Map<String, Blob>()
            )
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('UNAUTHORIZED', payload.get('code'));
    }

    @IsTest
    static void backendJsonError_parsedWithoutSecrets() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Test.setMock(
            HttpCalloutMock.class,
            new RoutingMock(
                authBody(true),
                new Map<String, Integer>{ CLS_ARTIFACT => 400 },
                new Map<String, Blob>(),
                '{"error":"Artifact not eligible","code":"INVALID_REQUEST"}'
            )
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        assertNoSecrets(json);
    }

    @IsTest
    static void persistenceFailure_returnsPartialReferences() {
        SeedContext ctx = loadConflictSeedContext();
        Blob clsBytes = Blob.valueOf('class PersistFail {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');

        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('CONFLICT', payload.get('code'));
        List<Object> persisted = (List<Object>) payload.get('persistedArtifacts');
        System.assertEquals(1, persisted.size());
    }

    @IsTest
    static void canonical_units_parsing_success() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class Canonical {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        String manifest = buildManifestJson(clsBytes, metaBytes, true);

        ApexMergeArtifactRetrievalService.ManifestParseResult parsed =
            ApexMergeArtifactRetrievalService.parseCanonicalManifest(
                (Map<String, Object>) JSON.deserializeUntyped(manifest)
            );
        System.assertEquals(true, parsed.success);
        System.assertEquals(1, parsed.units.size());
        System.assertEquals(2, parsed.units[0].descriptors.size());
    }

    @IsTest
    static void unsupported_rootArtifacts_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob bytes = Blob.valueOf('class X {}');
        String manifest = JSON.serialize(
            new Map<String, Object>{
                'mergeManifestId' => MANIFEST_ID,
                'artifacts' => new List<Object>{
                    roleDescriptor(CLS_ARTIFACT, bytes)
                }
            }
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('UNSUPPORTED_MANIFEST', payload.get('code'));
    }

    @IsTest
    static void multipleUnits_enqueueAsyncAccepted() {
        Blob clsBytes = Blob.valueOf('class A {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Blob clsBytesB = Blob.valueOf('class B {}');
        Blob metaBytesB = Blob.valueOf('<ApexClass status="B"/>');
        String manifestJson = buildTwoUnitManifest(
            clsBytes,
            metaBytes,
            clsBytesB,
            metaBytesB
        );
        List<ApexMergeArtifactRetrievalService.ManifestUnit> units =
            parseManifestUnits(manifestJson);

        System.assertEquals(
            true,
            ApexMergeArtifactRetrievalService.requiresAsyncProcessing(units),
            'Multi-unit manifests must route to async processing.'
        );
        System.assertEquals(2, units.size());

        SeedContext ctx = loadDefaultSeedContext();
        Map<String, Object> manifest = (Map<String, Object>) JSON.deserializeUntyped(
            manifestJson
        );
        assertAsyncAcceptedPayload(
            parsePayload(
                ApexMergeArtifactRetrievalService.asyncAcceptedEnvelope(
                    SESSION_ID,
                    MANIFEST_ID,
                    ctx.planId,
                    units.size(),
                    manifest,
                    'status_run_fixture'
                )
            ),
            ctx.planId,
            2
        );

        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(401, '{"success":false,"error":"Unauthorized"}', null, null)
        );
        Test.startTest();
        Integer queueablesBefore = Limits.getQueueableJobs();
        String json = ApexMergeArtifactRetrievalService.retrieveAndPersist(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );
        System.assertEquals(
            1,
            Limits.getQueueableJobs() - queueablesBefore,
            'retrieveAndPersist must enqueue exactly one starter queueable.'
        );
        assertAsyncAcceptedPayload(parsePayload(json), ctx.planId, 2);

        Map<String, Object> acceptance = parsePayload(json);
        String statusRunId = String.valueOf(acceptance.get('statusRunId'));
        System.assert(String.isNotBlank(statusRunId));
        System.assertEquals(
            statusRunId,
            ApexMergeArtifactRetrievalService.lastEnqueuedStatusRunId
        );
        assertQueuedStatusPersisted(
            ctx.planId,
            statusRunId,
            new List<String>{ 'Foo', 'Bar' },
            ctx.comparisonId
        );
    }

    @IsTest
    static void asyncAcceptance_persistsQueuedStatusSnapshot() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class A {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Blob clsBytesB = Blob.valueOf('class B {}');
        Blob metaBytesB = Blob.valueOf('<ApexClass status="B"/>');
        String manifestJson = buildTwoUnitManifest(
            clsBytes,
            metaBytes,
            clsBytesB,
            metaBytesB
        );

        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(401, '{"success":false,"error":"Unauthorized"}', null, null)
        );
        Test.startTest();
        String json = ApexMergeArtifactRetrievalService.retrieveAndPersist(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );

        Map<String, Object> acceptance = parsePayload(json);
        assertQueuedStatusPersisted(
            ctx.planId,
            String.valueOf(acceptance.get('statusRunId')),
            new List<String>{ 'Foo', 'Bar' },
            ctx.comparisonId
        );
        Test.stopTest();
    }

    @IsTest
    static void asyncAcceptance_statusPersistBlocked_throwsAndLeavesNoQueuedSnapshot() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class A {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Blob clsBytesB = Blob.valueOf('class B {}');
        Blob metaBytesB = Blob.valueOf('<ApexClass status="B"/>');
        String manifestJson = buildTwoUnitManifest(
            clsBytes,
            metaBytes,
            clsBytesB,
            metaBytesB
        );

        ApexMergeArtifactRetrievalService.blockQueuedStatusPersistForTest = true;
        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(401, '{"success":false,"error":"Unauthorized"}', null, null)
        );

        Integer queueablesBefore = Limits.getQueueableJobs();
        Boolean threw = false;
        try {
            ApexMergeArtifactRetrievalService.retrieveAndPersist(
                ctx.comparisonId,
                ctx.planId,
                SESSION_ID,
                manifestJson
            );
        } catch (AuraHandledException e) {
            threw = true;
        } finally {
            ApexMergeArtifactRetrievalService.blockQueuedStatusPersistForTest = false;
        }

        System.assertEquals(
            true,
            threw,
            'Blocked status persistence must throw from async acceptance.'
        );

        Deployment_Plan__c plan = [
            SELECT
                Latest_Apex_Merge_Artifact_Status__c,
                Latest_Apex_Merge_Artifact_JSON__c
            FROM Deployment_Plan__c
            WHERE Id = :ctx.planId
            LIMIT 1
        ];
        System.assertEquals(null, plan.Latest_Apex_Merge_Artifact_Status__c);
        System.assertEquals(null, plan.Latest_Apex_Merge_Artifact_JSON__c);
        System.assertEquals(
            0,
            Limits.getQueueableJobs() - queueablesBefore,
            'Failed QUEUED persistence must not enqueue a starter queueable.'
        );
    }

    @IsTest
    static void asyncAcceptance_blankDurableState_startsNewRun() {
        SeedContext ctx = loadRetryIdempotentSeedContext();
        String manifestJson = buildTwoUnitManifest(
            Blob.valueOf('class A {}'),
            Blob.valueOf('<ApexClass/>'),
            Blob.valueOf('class B {}'),
            Blob.valueOf('<ApexClass status="B"/>')
        );
        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(401, '{"success":false,"error":"Unauthorized"}', null, null)
        );
        Test.startTest();
        Integer queueablesBefore = Limits.getQueueableJobs();
        String json = ApexMergeArtifactRetrievalService.retrieveAndPersist(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );
        System.assertEquals(
            1,
            Limits.getQueueableJobs() - queueablesBefore,
            'New async acceptance must enqueue exactly one starter job.'
        );
        Map<String, Object> payload = parsePayload(json);
        assertAsyncAcceptedPayload(payload, ctx.planId, 2);
        assertQueuedStatusPersisted(
            ctx.planId,
            String.valueOf(payload.get('statusRunId')),
            new List<String>{ 'Foo', 'Bar' },
            ctx.comparisonId
        );
    }

    @IsTest
    static void asyncAcceptance_idempotentRetry_returnsExistingRun() {
        SeedContext ctx = loadRetryIdempotentSeedContext();
        String manifestJson = buildTwoUnitManifest(
            Blob.valueOf('class A {}'),
            Blob.valueOf('<ApexClass/>'),
            Blob.valueOf('class B {}'),
            Blob.valueOf('<ApexClass status="B"/>')
        );
        String existingRunId = seedQueuedArtifactStatus(ctx, manifestJson);
        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(401, '{"success":false,"error":"Unauthorized"}', null, null)
        );
        Integer queueablesBefore = Limits.getQueueableJobs();
        String json = ApexMergeArtifactRetrievalService.retrieveAndPersist(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );
        Map<String, Object> payload = parsePayload(json);
        assertAsyncAcceptedPayload(payload, ctx.planId, 2);
        System.assertEquals(existingRunId, String.valueOf(payload.get('statusRunId')));
        System.assertEquals(
            0,
            Limits.getQueueableJobs() - queueablesBefore,
            'Idempotent retry must not enqueue another queueable.'
        );
    }

    @IsTest
    static void asyncAcceptance_activeRunDifferentIdentity_returnsRunInProgress() {
        SeedContext ctx = loadConflictSeedContext();
        String manifestJson = buildTwoUnitManifest(
            Blob.valueOf('class A {}'),
            Blob.valueOf('<ApexClass/>'),
            Blob.valueOf('class B {}'),
            Blob.valueOf('<ApexClass status="B"/>')
        );
        seedQueuedArtifactStatus(ctx, manifestJson);
        String otherSessionManifest = manifestJson.replace(
            SESSION_ID,
            'sess_other_active'
        );
        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(401, '{"success":false,"error":"Unauthorized"}', null, null)
        );
        Integer queueablesBefore = Limits.getQueueableJobs();
        String json = ApexMergeArtifactRetrievalService.retrieveAndPersist(
            ctx.comparisonId,
            ctx.planId,
            'sess_other_active',
            otherSessionManifest
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals(
            ApexMergeArtifactRetrievalService.CODE_RUN_IN_PROGRESS,
            payload.get('code')
        );
        System.assertEquals(
            0,
            Limits.getQueueableJobs() - queueablesBefore,
            'Conflicting accept must not enqueue.'
        );
    }

    @IsTest
    static void asyncAcceptance_terminalCompleted_returnsRunTerminated() {
        assertAsyncAcceptanceRejectsTerminal(
            ApexMergeArtifactStatusService.OVERALL_COMPLETED
        );
    }

    @IsTest
    static void asyncAcceptance_terminalFailed_returnsRunTerminated() {
        assertAsyncAcceptanceRejectsTerminal(
            ApexMergeArtifactStatusService.OVERALL_FAILED
        );
    }

    @IsTest
    static void asyncAcceptance_terminalPartiallyFailed_returnsRunTerminated() {
        assertAsyncAcceptanceRejectsTerminal(
            ApexMergeArtifactStatusService.OVERALL_PARTIALLY_FAILED
        );
    }

    @IsTest
    static void asyncAcceptance_malformedStoredJson_failsClosed() {
        SeedContext ctx = loadConflictSeedContext();
        Deployment_Plan__c plan = new Deployment_Plan__c(
            Id = ctx.planId,
            Latest_Apex_Merge_Artifact_Status__c =
                ApexMergeArtifactStatusService.OVERALL_QUEUED,
            Latest_Apex_Merge_Artifact_JSON__c = '{not-valid-status-json'
        );
        update plan;
        String manifestJson = buildTwoUnitManifest(
            Blob.valueOf('class A {}'),
            Blob.valueOf('<ApexClass/>'),
            Blob.valueOf('class B {}'),
            Blob.valueOf('<ApexClass status="B"/>')
        );
        String json = ApexMergeArtifactRetrievalService.retrieveAndPersist(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals(
            ApexMergeArtifactRetrievalService.CODE_INVALID_STORED_STATUS,
            payload.get('code')
        );
    }

    @IsTest
    static void asyncAcceptance_splitDurableFields_failsClosed() {
        SeedContext ctx = loadConflictSeedContext();
        update new Deployment_Plan__c(
            Id = ctx.planId,
            Latest_Apex_Merge_Artifact_Status__c =
                ApexMergeArtifactStatusService.OVERALL_QUEUED,
            Latest_Apex_Merge_Artifact_JSON__c = null
        );
        String manifestJson = buildTwoUnitManifest(
            Blob.valueOf('class A {}'),
            Blob.valueOf('<ApexClass/>'),
            Blob.valueOf('class B {}'),
            Blob.valueOf('<ApexClass status="B"/>')
        );
        String json = ApexMergeArtifactRetrievalService.retrieveAndPersist(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals(
            ApexMergeArtifactRetrievalService.CODE_STATUS_STORE_AMBIGUOUS,
            payload.get('code')
        );
    }

    @IsTest
    static void asyncAcceptance_statusPicklistJsonMismatch_failsClosed() {
        SeedContext ctx = loadConflictSeedContext();
        String manifestJson = buildTwoUnitManifest(
            Blob.valueOf('class A {}'),
            Blob.valueOf('<ApexClass/>'),
            Blob.valueOf('class B {}'),
            Blob.valueOf('<ApexClass status="B"/>')
        );
        String statusRunId = seedQueuedArtifactStatus(ctx, manifestJson);
        Deployment_Plan__c plan = new Deployment_Plan__c(
            Id = ctx.planId,
            Latest_Apex_Merge_Artifact_Status__c =
                ApexMergeArtifactStatusService.OVERALL_PROCESSING
        );
        update plan;
        String json = ApexMergeArtifactRetrievalService.retrieveAndPersist(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals(
            ApexMergeArtifactRetrievalService.CODE_STATUS_STORE_MISMATCH,
            payload.get('code')
        );
        System.assertEquals(
            statusRunId,
            loadStoredStatusSnapshot(ctx.planId).statusRunId,
            'Mismatch inspection must not mutate stored status.'
        );
    }

    @IsTest
    static void queueable_staleStatusRunId_preCallout_noCallouts() {
        SeedContext ctx = loadConflictSeedContext();
        String manifest = buildManifestJson(
            Blob.valueOf('class Stale {}'),
            Blob.valueOf('<ApexClass/>'),
            true
        );
        String activeRunId = seedQueuedArtifactStatus(ctx, manifest);
        String staleRunId = ApexMergeArtifactStatusService.newStatusRunId();
        System.assertNotEquals(activeRunId, staleRunId);
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest,
            0,
            staleRunId
        );
        System.assertEquals(
            0,
            ApexMergeArtifactRetrievalService.lastInvokedCalloutCount,
            'Stale statusRunId must stop before any callout.'
        );
    }

    @IsTest
    static void queueable_staleAfterCallouts_doesNotMutateCurrentRun() {
        SeedContext ctx = loadConflictSeedContext();
        Blob clsBytes = Blob.valueOf('class Stale {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        String manifest = buildManifestJson(clsBytes, metaBytes, true);
        String activeRunId = seedQueuedArtifactStatus(ctx, manifest);
        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );
        String staleRunId = ApexMergeArtifactStatusService.newStatusRunId();
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest,
            0,
            staleRunId
        );
        ApexMergeArtifactStatusService.StatusSnapshot stored =
            loadStoredStatusSnapshot(ctx.planId);
        System.assertEquals(activeRunId, stored.statusRunId);
        System.assertEquals(
            ApexMergeArtifactStatusService.OVERALL_QUEUED,
            stored.overallStatus
        );
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_NOT_STARTED,
            stored.units[0].status
        );
        System.assertEquals(
            0,
            countLatestArtifactsForPlan(ctx.planId, CLS_ARTIFACT),
            'Post-callout ownership loss must not persist ContentVersion rows.'
        );
    }

    @IsTest
    static void queueable_staleManifestIdentity_preCallout_noCallouts() {
        SeedContext ctx = loadConflictSeedContext();
        Blob clsBytes = Blob.valueOf('class StaleManifest {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        String seededManifest = buildManifestJson(clsBytes, metaBytes, true);
        String statusRunId = seedQueuedArtifactStatus(ctx, seededManifest);
        String differentManifest = buildManifestJsonWithManifestId(
            'mfm_retrieval_stale',
            clsBytes,
            metaBytes,
            true
        );
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            differentManifest,
            0,
            statusRunId
        );
        System.assertEquals(
            0,
            ApexMergeArtifactRetrievalService.lastInvokedCalloutCount,
            'Manifest identity mismatch must stop before any callout.'
        );
    }

    @IsTest
    static void queueable_staleStatusRunId_authFailure_keepsActiveQueued() {
        SeedContext ctx = loadConflictSeedContext();
        Blob clsBytes = Blob.valueOf('class StaleFail {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        String manifest = buildManifestJson(clsBytes, metaBytes, true);
        String activeRunId = seedQueuedArtifactStatus(ctx, manifest);
        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(401, '{"success":false,"error":"Unauthorized"}', null, null)
        );
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest,
            0,
            ApexMergeArtifactStatusService.newStatusRunId()
        );
        assertPlanOverallStatus(
            ctx.planId,
            ApexMergeArtifactStatusService.OVERALL_QUEUED
        );
        System.assertEquals(
            activeRunId,
            loadStoredStatusSnapshot(ctx.planId).statusRunId
        );
    }

    @IsTest
    static void queueable_malformedDurableState_preCallout_noMutation() {
        SeedContext ctx = loadConflictSeedContext();
        update new Deployment_Plan__c(
            Id = ctx.planId,
            Latest_Apex_Merge_Artifact_Status__c =
                ApexMergeArtifactStatusService.OVERALL_QUEUED,
            Latest_Apex_Merge_Artifact_JSON__c = '{not-valid-status-json'
        );
        String manifest = buildManifestJson(
            Blob.valueOf('class BadStore {}'),
            Blob.valueOf('<ApexClass/>'),
            true
        );
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest,
            0,
            ApexMergeArtifactStatusService.newStatusRunId()
        );
        System.assertEquals(
            0,
            ApexMergeArtifactRetrievalService.lastInvokedCalloutCount
        );
    }

    @IsTest
    static void sync_rejectedWhenAsyncQueued() {
        SeedContext ctx = loadDefaultSeedContext();
        String manifestJson = buildManifestJson(
            Blob.valueOf('class Sync {}'),
            Blob.valueOf('<ApexClass/>'),
            true
        );
        seedQueuedArtifactStatus(ctx, manifestJson);
        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(
                Blob.valueOf('class Sync {}'),
                Blob.valueOf('<ApexClass/>')
            )
        );
        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals(
            ApexMergeArtifactRetrievalService.CODE_RUN_IN_PROGRESS,
            payload.get('code')
        );
    }

    @IsTest
    static void sync_rejectedWhenAsyncProcessing() {
        SeedContext ctx = loadDefaultSeedContext();
        String manifestJson = buildManifestJson(
            Blob.valueOf('class SyncProc {}'),
            Blob.valueOf('<ApexClass/>'),
            true
        );
        writeDurableAcceptanceState(
            ctx,
            manifestJson,
            ApexMergeArtifactStatusService.OVERALL_PROCESSING
        );
        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(
                Blob.valueOf('class SyncProc {}'),
                Blob.valueOf('<ApexClass/>')
            )
        );
        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals(
            ApexMergeArtifactRetrievalService.CODE_RUN_IN_PROGRESS,
            payload.get('code')
        );
    }

    @IsTest
    static void sync_succeedsWithBlankDurableState() {
        SeedContext ctx = loadDefaultSeedContext();
        Deployment_Plan__c before = [
            SELECT
                Latest_Apex_Merge_Artifact_Status__c,
                Latest_Apex_Merge_Artifact_JSON__c
            FROM Deployment_Plan__c
            WHERE Id = :ctx.planId
            LIMIT 1
        ];
        System.assertEquals(null, before.Latest_Apex_Merge_Artifact_Status__c);
        System.assertEquals(null, before.Latest_Apex_Merge_Artifact_JSON__c);
        Blob clsBytes = Blob.valueOf('class BlankSync {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );
        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(true, payload.get('success'));
        Deployment_Plan__c after = [
            SELECT
                Latest_Apex_Merge_Artifact_Status__c,
                Latest_Apex_Merge_Artifact_JSON__c
            FROM Deployment_Plan__c
            WHERE Id = :ctx.planId
            LIMIT 1
        ];
        System.assertEquals(
            before.Latest_Apex_Merge_Artifact_Status__c,
            after.Latest_Apex_Merge_Artifact_Status__c
        );
        System.assertEquals(
            before.Latest_Apex_Merge_Artifact_JSON__c,
            after.Latest_Apex_Merge_Artifact_JSON__c
        );
    }

    @IsTest
    static void sync_failsClosed_malformedStoredJson() {
        SeedContext ctx = loadDefaultSeedContext();
        update new Deployment_Plan__c(
            Id = ctx.planId,
            Latest_Apex_Merge_Artifact_Status__c =
                ApexMergeArtifactStatusService.OVERALL_QUEUED,
            Latest_Apex_Merge_Artifact_JSON__c = '{not-valid-status-json'
        );
        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(
                Blob.valueOf('class SyncBadJson {}'),
                Blob.valueOf('<ApexClass/>')
            )
        );
        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(
                Blob.valueOf('class SyncBadJson {}'),
                Blob.valueOf('<ApexClass/>'),
                true
            )
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals(
            ApexMergeArtifactRetrievalService.CODE_INVALID_STORED_STATUS,
            payload.get('code')
        );
    }

    @IsTest
    static void sync_failsClosed_splitDurableFields() {
        SeedContext ctx = loadDefaultSeedContext();
        update new Deployment_Plan__c(
            Id = ctx.planId,
            Latest_Apex_Merge_Artifact_Status__c =
                ApexMergeArtifactStatusService.OVERALL_QUEUED,
            Latest_Apex_Merge_Artifact_JSON__c = null
        );
        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(
                Blob.valueOf('class SyncSplit {}'),
                Blob.valueOf('<ApexClass/>')
            )
        );
        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(
                Blob.valueOf('class SyncSplit {}'),
                Blob.valueOf('<ApexClass/>'),
                true
            )
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals(
            ApexMergeArtifactRetrievalService.CODE_STATUS_STORE_AMBIGUOUS,
            payload.get('code')
        );
    }

    @IsTest
    static void sync_failsClosed_statusPicklistJsonMismatch() {
        SeedContext ctx = loadDefaultSeedContext();
        String manifestJson = buildManifestJson(
            Blob.valueOf('class SyncMismatch {}'),
            Blob.valueOf('<ApexClass/>'),
            true
        );
        seedQueuedArtifactStatus(ctx, manifestJson);
        update new Deployment_Plan__c(
            Id = ctx.planId,
            Latest_Apex_Merge_Artifact_Status__c =
                ApexMergeArtifactStatusService.OVERALL_PROCESSING
        );
        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(
                Blob.valueOf('class SyncMismatch {}'),
                Blob.valueOf('<ApexClass/>')
            )
        );
        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals(
            ApexMergeArtifactRetrievalService.CODE_STATUS_STORE_MISMATCH,
            payload.get('code')
        );
    }

    @IsTest
    static void sync_succeedsWhenTerminal_leavesDurableStatusUnchanged() {
        SeedContext ctx = loadDefaultSeedContext();
        String manifestJson = buildManifestJson(
            Blob.valueOf('class TerminalSync {}'),
            Blob.valueOf('<ApexClass/>'),
            true
        );
        writeDurableAcceptanceState(
            ctx,
            manifestJson,
            ApexMergeArtifactStatusService.OVERALL_COMPLETED
        );
        Deployment_Plan__c before = [
            SELECT
                Latest_Apex_Merge_Artifact_Status__c,
                Latest_Apex_Merge_Artifact_JSON__c
            FROM Deployment_Plan__c
            WHERE Id = :ctx.planId
            LIMIT 1
        ];
        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(
                Blob.valueOf('class TerminalSync {}'),
                Blob.valueOf('<ApexClass/>')
            )
        );
        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(true, payload.get('success'));
        System.assertEquals(
            null,
            payload.get('code'),
            'Successful sync must not return a failure code.'
        );
        Deployment_Plan__c after = [
            SELECT
                Latest_Apex_Merge_Artifact_Status__c,
                Latest_Apex_Merge_Artifact_JSON__c
            FROM Deployment_Plan__c
            WHERE Id = :ctx.planId
            LIMIT 1
        ];
        System.assertEquals(
            before.Latest_Apex_Merge_Artifact_Status__c,
            after.Latest_Apex_Merge_Artifact_Status__c
        );
        System.assertEquals(
            before.Latest_Apex_Merge_Artifact_JSON__c,
            after.Latest_Apex_Merge_Artifact_JSON__c
        );
    }

    /**
     * Direct synchronous invoke with a caught AuraHandledException does not prove
     * rollback in a real Queueable execution (uncaught exception path). It only
     * verifies unit-0 success persistence plus no successor enqueue when the
     * enqueue seam throws after status moves to PROCESSING.
     */
    @IsTest
    static void queueable_successorEnqueueFailure_doesNotEnqueueSuccessor() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class Rollback {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Blob clsBytesB = Blob.valueOf('class RollbackB {}');
        Blob metaBytesB = Blob.valueOf('<ApexClass status="B"/>');
        String manifest = buildTwoUnitManifest(
            clsBytes,
            metaBytes,
            clsBytesB,
            metaBytesB
        );
        String statusRunId = seedQueuedArtifactStatus(ctx, manifest);
        Integer clsCountBefore = countLatestArtifactsForPlan(
            ctx.planId,
            CLS_ARTIFACT
        );
        Integer metaCountBefore = countLatestArtifactsForPlan(
            ctx.planId,
            META_ARTIFACT
        );
        Integer queueableJobsBefore = Limits.getQueueableJobs();
        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );
        ApexMergeArtifactRetrievalService.blockSuccessorEnqueueForTest = true;
        Boolean threwExpected = false;
        try {
            Test.startTest();
            try {
                ApexMergeArtifactRetrievalService.processQueuedUnit(
                    ctx.comparisonId,
                    ctx.planId,
                    SESSION_ID,
                    manifest,
                    0,
                    statusRunId
                );
            } catch (AuraHandledException e) {
                threwExpected = true;
            }
            Test.stopTest();
        } finally {
            ApexMergeArtifactRetrievalService.blockSuccessorEnqueueForTest = false;
        }
        System.assertEquals(
            true,
            threwExpected,
            'Enqueue failure seam must throw AuraHandledException.'
        );
        assertPlanOverallStatus(
            ctx.planId,
            ApexMergeArtifactStatusService.OVERALL_PROCESSING
        );
        ApexMergeArtifactStatusService.StatusSnapshot stored =
            loadStoredStatusSnapshot(ctx.planId);
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_COMPLETED,
            stored.units[0].status
        );
        System.assertEquals(
            clsCountBefore + 1,
            countLatestArtifactsForPlan(ctx.planId, CLS_ARTIFACT),
            'Unit 0 cls artifact must be persisted before enqueue seam throws.'
        );
        System.assertEquals(
            metaCountBefore + 1,
            countLatestArtifactsForPlan(ctx.planId, META_ARTIFACT),
            'Unit 0 metaXml artifact must be persisted before enqueue seam throws.'
        );
        System.assertEquals(
            queueableJobsBefore,
            Limits.getQueueableJobs(),
            'Enqueue failure must not leave a successor queueable job enqueued.'
        );
    }

    @IsTest
    static void queueable_processesSingleUnit() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class Queueable {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        String manifest = buildManifestJson(clsBytes, metaBytes, true);

        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );
        String statusRunId = seedQueuedArtifactStatus(ctx, manifest);
        Test.startTest();
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest,
            0,
            statusRunId
        );
        Test.stopTest();

        System.assertEquals(
            1,
            countLatestArtifactsForPlan(ctx.planId, CLS_ARTIFACT)
        );
        assertPlanOverallStatus(
            ctx.planId,
            ApexMergeArtifactStatusService.OVERALL_COMPLETED
        );
        ApexMergeArtifactStatusService.StatusSnapshot stored =
            loadStoredStatusSnapshot(ctx.planId);
        String expectedClsSha = sha256Hex(clsBytes);
        System.assertEquals(statusRunId, stored.statusRunId);
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_COMPLETED,
            stored.units[0].status
        );
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_COMPLETED,
            stored.units[0].artifacts.cls.status
        );
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_COMPLETED,
            stored.units[0].artifacts.metaXml.status
        );
        System.assertNotEquals(null, stored.completedAt);
        System.assertEquals(expectedClsSha, stored.units[0].artifacts.cls.sha256);
        System.assertEquals(clsBytes.size(), stored.units[0].artifacts.cls.byteLength);
        System.assertEquals(
            ApexMergeArtifactStatusService.OVERALL_COMPLETED,
            stored.overallStatus
        );
    }

    @IsTest
    static void sync_heapThreshold_acceptsSmallUnit() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class Small {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        System.assertEquals(
            false,
            ApexMergeArtifactRetrievalService.requiresAsyncProcessing(
                ApexMergeArtifactRetrievalService.parseCanonicalManifest(
                    (Map<String, Object>) JSON.deserializeUntyped(
                        buildManifestJson(clsBytes, metaBytes, true)
                    )
                ).units
            )
        );
    }

    @IsTest
    static void sync_heapThreshold_routesLargeSingleUnitToAsync() {
        SeedContext ctx = loadDefaultSeedContext();
        Map<String, Object> manifest = buildLargeSingleUnitManifest();
        String manifestJson = JSON.serialize(manifest);
        List<ApexMergeArtifactRetrievalService.ManifestUnit> units =
            parseManifestUnits(manifestJson);

        System.assertEquals(1, units.size());
        System.assertEquals(
            true,
            ApexMergeArtifactRetrievalService.requiresAsyncProcessing(units),
            'Single unit above sync descriptor budget must route async.'
        );
        assertAsyncAcceptedPayload(
            parsePayload(
                ApexMergeArtifactRetrievalService.asyncAcceptedEnvelope(
                    SESSION_ID,
                    MANIFEST_ID,
                    ctx.planId,
                    1,
                    manifest,
                    'status_run_fixture'
                )
            ),
            ctx.planId,
            1
        );
    }

    @IsTest
    static void aggregateDescriptorByteBudget_rejectedOnAsyncUnit() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob tiny = Blob.valueOf('x');
        Map<String, Object> manifest = new Map<String, Object>{
            'mergeManifestId' => MANIFEST_ID,
            'units' => new List<Object>{
                new Map<String, Object>{
                    'metadataName' => 'Big',
                    'cls' => new Map<String, Object>{
                        'artifactId' => CLS_ARTIFACT,
                        'sha256' => sha256Hex(tiny),
                        'byteLength' => 3000000
                    },
                    'metaXml' => new Map<String, Object>{
                        'artifactId' => META_ARTIFACT,
                        'sha256' => sha256Hex(tiny),
                        'byteLength' => 3000000
                    }
                }
            }
        };

        String statusRunId = seedQueuedArtifactStatus(
            ctx,
            JSON.serialize(manifest)
        );
        Test.startTest();
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            JSON.serialize(manifest),
            0,
            statusRunId
        );
        Test.stopTest();

        ApexMergeArtifactRetrievalService.ChainFailureRecord failure =
            ApexMergeArtifactRetrievalService.lastChainFailure;
        System.assertNotEquals(null, failure);
        System.assertEquals('ARTIFACT_TOO_LARGE', failure.code);
        assertPlanOverallStatus(
            ctx.planId,
            ApexMergeArtifactStatusService.OVERALL_FAILED
        );
    }

    @IsTest
    static void sessionExpired_stopsQueueableAndRecordsFailure() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class Expired {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Map<String, Object> manifest = new Map<String, Object>{
            'mergeManifestId' => MANIFEST_ID,
            'mergeSessionId' => SESSION_ID,
            'sessionExpiresAt' => System.now().addHours(-2).getTime(),
            'units' => new List<Object>{
                buildUnit('Foo', CLS_ARTIFACT, META_ARTIFACT, clsBytes, metaBytes)
            }
        };

        String statusRunId = seedQueuedArtifactStatus(
            ctx,
            JSON.serialize(manifest)
        );
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            JSON.serialize(manifest),
            0,
            statusRunId
        );
        ApexMergeArtifactRetrievalService.ChainFailureRecord failure =
            ApexMergeArtifactRetrievalService.lastChainFailure;
        System.assertNotEquals(null, failure);
        System.assertEquals('EXPIRED', failure.code);
        System.assertEquals(
            0,
            countLatestArtifactsForPlan(ctx.planId, CLS_ARTIFACT)
        );
        assertPlanOverallStatus(
            ctx.planId,
            ApexMergeArtifactStatusService.OVERALL_FAILED
        );
    }

    @IsTest
    static void queueable_failure_stopsChainingAndKeepsPriorArtifacts() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class First {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Blob clsBytesB = Blob.valueOf('class Second {}');
        Blob metaBytesB = Blob.valueOf('<ApexClass status="B"/>');
        String artifactClsB =
            'merge/mfm_retrieval_1/classes/Bar/ApexClass/cls';
        String artifactMetaB =
            'merge/mfm_retrieval_1/classes/Bar/ApexClass/metaXml';

        Test.setMock(
            HttpCalloutMock.class,
            new RoutingMock(
                authBody(true),
                new Map<String, Integer>{
                    CLS_ARTIFACT => 200,
                    META_ARTIFACT => 200,
                    artifactClsB => 404,
                    artifactMetaB => 404
                },
                new Map<String, Blob>{
                    CLS_ARTIFACT => clsBytes,
                    META_ARTIFACT => metaBytes
                }
            )
        );

        String manifest = buildTwoUnitManifest(
            clsBytes,
            metaBytes,
            clsBytesB,
            metaBytesB
        );

        String statusRunId = seedQueuedArtifactStatus(ctx, manifest);
        Test.startTest();
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest,
            0,
            statusRunId
        );
        Test.stopTest();

        System.assertEquals(
            1,
            countLatestArtifactsForPlan(ctx.planId, CLS_ARTIFACT)
        );
        System.assertEquals(
            0,
            countLatestArtifactsForPlan(ctx.planId, artifactClsB)
        );
        ApexMergeArtifactRetrievalService.ChainFailureRecord failure =
            ApexMergeArtifactRetrievalService.lastChainFailure;
        System.assertNotEquals(null, failure);
        System.assertEquals(true, failure.partialChain);
        System.assertEquals('NOT_FOUND', failure.code);
        assertPlanOverallStatus(
            ctx.planId,
            ApexMergeArtifactStatusService.OVERALL_PARTIALLY_FAILED
        );
        ApexMergeArtifactStatusService.StatusSnapshot stored =
            loadStoredStatusSnapshot(ctx.planId);
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_COMPLETED,
            stored.units[0].status
        );
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_FAILED,
            stored.units[1].status
        );
        System.assertEquals(1, failure.unitIndex);
    }

    @IsTest
    static void queueable_metaXmlPersistFailure_preservesClsReference() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class Partial {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        String manifest = buildManifestJson(clsBytes, metaBytes, true);
        insertStoredArtifact(ctx.planId, 'Foo', 'cls', CLS_ARTIFACT, clsBytes);
        insertStoredArtifact(
            ctx.planId,
            'Foo',
            'metaXml',
            META_ARTIFACT,
            Blob.valueOf('<duplicate/>')
        );
        insertStoredArtifact(
            ctx.planId,
            'Foo',
            'metaXml',
            META_ARTIFACT,
            metaBytes
        );

        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );
        String statusRunId = seedQueuedArtifactStatus(ctx, manifest);

        Test.startTest();
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest,
            0,
            statusRunId
        );
        Test.stopTest();

        ApexMergeArtifactStatusService.StatusSnapshot stored =
            loadStoredStatusSnapshot(ctx.planId);
        String expectedClsSha = sha256Hex(clsBytes);
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_FAILED,
            stored.units[0].status
        );
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_COMPLETED,
            stored.units[0].artifacts.cls.status
        );
        System.assertNotEquals(
            null,
            stored.units[0].artifacts.cls.contentDocumentId
        );
        System.assertEquals(expectedClsSha, stored.units[0].artifacts.cls.sha256);
        System.assertEquals(clsBytes.size(), stored.units[0].artifacts.cls.byteLength);
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_FAILED,
            stored.units[0].artifacts.metaXml.status
        );
        System.assertEquals('AMBIGUOUS', stored.units[0].artifacts.metaXml.errorCode);
        System.assert(
            String.isNotBlank(stored.units[0].artifacts.metaXml.errorMessage)
        );
        System.assert(
            stored.units[0].artifacts.metaXml.errorMessage.contains(
                'Multiple artifact files'
            ),
            'Expected ambiguity message: ' +
                stored.units[0].artifacts.metaXml.errorMessage
        );
        assertPlanOverallStatus(
            ctx.planId,
            ApexMergeArtifactStatusService.OVERALL_FAILED
        );
    }

    @IsTest
    static void queueable_metaXmlPersistFailure_onFirstUnit_doesNotEnqueueSecond() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class PartialA {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Blob clsBytesB = Blob.valueOf('class PartialB {}');
        Blob metaBytesB = Blob.valueOf('<ApexClass status="B"/>');
        String manifest = buildTwoUnitManifest(
            clsBytes,
            metaBytes,
            clsBytesB,
            metaBytesB
        );
        insertStoredArtifact(ctx.planId, 'Foo', 'cls', CLS_ARTIFACT, clsBytes);
        insertStoredArtifact(
            ctx.planId,
            'Foo',
            'metaXml',
            META_ARTIFACT,
            Blob.valueOf('<duplicate/>')
        );
        insertStoredArtifact(
            ctx.planId,
            'Foo',
            'metaXml',
            META_ARTIFACT,
            metaBytes
        );

        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );
        String statusRunId = seedQueuedArtifactStatus(ctx, manifest);
        Integer queueableBefore = Limits.getQueueableJobs();

        Test.startTest();
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest,
            0,
            statusRunId
        );
        Test.stopTest();

        System.assertEquals(
            queueableBefore,
            Limits.getQueueableJobs(),
            'Failed first unit must not enqueue the second unit.'
        );
        assertPlanOverallStatus(
            ctx.planId,
            ApexMergeArtifactStatusService.OVERALL_FAILED
        );
        ApexMergeArtifactStatusService.StatusSnapshot stored =
            loadStoredStatusSnapshot(ctx.planId);
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_FAILED,
            stored.units[0].status
        );
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_NOT_STARTED,
            stored.units[1].status
        );
    }

    @IsTest
    static void queueable_authorizationFailure_recordsTerminalStatus() {
        SeedContext ctx = loadDefaultSeedContext();
        Map<String, Object> manifest = buildLargeSingleUnitManifest();
        String manifestJson = JSON.serialize(manifest);

        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(401, '{"success":false,"error":"Unauthorized"}', null, null)
        );

        Test.startTest();
        String acceptance =
            ApexMergeArtifactRetrievalService.retrieveAndPersist(
                ctx.comparisonId,
                ctx.planId,
                SESSION_ID,
                manifestJson
            );
        Test.stopTest();

        Map<String, Object> accepted = parsePayload(acceptance);
        System.assertEquals(true, accepted.get('success'));
        System.assertEquals(true, accepted.get('async'));

        ApexMergeArtifactStatusService.StatusSnapshot stored =
            loadStoredStatusSnapshot(ctx.planId);
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_FAILED,
            stored.units[0].status
        );
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_NOT_STARTED,
            stored.units[0].artifacts.cls.status
        );
        assertPlanOverallStatus(
            ctx.planId,
            ApexMergeArtifactStatusService.OVERALL_FAILED
        );
    }

    @IsTest
    static void queueable_statusPersistFailure_preventsChaining() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class Chain {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Blob clsBytesB = Blob.valueOf('class ChainB {}');
        Blob metaBytesB = Blob.valueOf('<ApexClass status="B"/>');
        String manifest = buildTwoUnitManifest(
            clsBytes,
            metaBytes,
            clsBytesB,
            metaBytesB
        );

        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );
        String statusRunId = seedQueuedArtifactStatus(ctx, manifest);
        ApexMergeArtifactRetrievalService.blockQueuedUnitStatusPersistForTest = true;

        Boolean threw = false;
        Integer queueableBefore = Limits.getQueueableJobs();
        try {
            Test.startTest();
            ApexMergeArtifactRetrievalService.processQueuedUnit(
                ctx.comparisonId,
                ctx.planId,
                SESSION_ID,
                manifest,
                0,
                statusRunId
            );
        } catch (AuraHandledException e) {
            threw = true;
        } finally {
            Test.stopTest();
            ApexMergeArtifactRetrievalService.blockQueuedUnitStatusPersistForTest = false;
        }

        System.assertEquals(true, threw);
        System.assertEquals(queueableBefore, Limits.getQueueableJobs());
    }

    @IsTest
    static void queueable_nonFinalUnit_setsProcessingAndEnqueuesAfterStatus() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class First {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Blob clsBytesB = Blob.valueOf('class Second {}');
        Blob metaBytesB = Blob.valueOf('<ApexClass status="B"/>');
        String manifest = buildTwoUnitManifest(
            clsBytes,
            metaBytes,
            clsBytesB,
            metaBytesB
        );

        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );
        String statusRunId = seedQueuedArtifactStatus(ctx, manifest);
        Integer queueableBefore = Limits.getQueueableJobs();

        Test.startTest();
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest,
            0,
            statusRunId
        );

        assertPlanOverallStatus(
            ctx.planId,
            ApexMergeArtifactStatusService.OVERALL_PROCESSING
        );
        ApexMergeArtifactStatusService.StatusSnapshot stored =
            loadStoredStatusSnapshot(ctx.planId);
        System.assertEquals(null, stored.completedAt);
        System.assertEquals(
            ApexMergeArtifactStatusService.UNIT_COMPLETED,
            stored.units[0].status
        );
        System.assertEquals(
            1,
            Limits.getQueueableJobs() - queueableBefore,
            'Success on unit 0 must enqueue unit 1 after status persistence.'
        );
        System.assertEquals(
            stored.statusRunId,
            ApexMergeArtifactRetrievalService.lastEnqueuedStatusRunId,
            'Successor queueable must receive the persisted statusRunId.'
        );
        Test.stopTest();
    }

    @IsTest
    static void multipleArtifacts_success() {
        Blob clsBytes = Blob.valueOf('class A {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Blob clsBytesB = Blob.valueOf('class B {}');
        Blob metaBytesB = Blob.valueOf('<ApexClass status="B"/>');
        String manifestJson = buildTwoUnitManifest(
            clsBytes,
            metaBytes,
            clsBytesB,
            metaBytesB
        );
        System.assertEquals(
            true,
            ApexMergeArtifactRetrievalService.requiresAsyncProcessing(
                parseManifestUnits(manifestJson)
            ),
            'Two manifest units exceed the synchronous request limit.'
        );
    }

    @IsTest
    static void duplicatePersistenceRetry_reusesExistingFiles() {
        SeedContext ctx = loadRetryIdempotentSeedContext();
        Blob clsBytes = Blob.valueOf('class Retry {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );
        String manifest = buildManifestJson(clsBytes, metaBytes, true);

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(true, payload.get('success'), json);
        List<Object> persisted = (List<Object>) payload.get('persistedArtifacts');
        for (Object row : persisted) {
            Map<String, Object> ref = (Map<String, Object>) row;
            System.assertEquals(true, ref.get('idempotentReuse'));
        }
    }

    @IsTest
    static void wrongComparisonPlanRelationship_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Id otherComparisonId = loadOtherComparisonId();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');

        String json = retrieveWithCommittedCalloutWindow(
            otherComparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('INVALID_REQUEST', payload.get('code'));
        System.assertEquals(
            String.valueOf(ctx.planId),
            String.valueOf(payload.get('deploymentPlanId'))
        );
        System.assertEquals(SESSION_ID, payload.get('mergeSessionId'));
        System.assertEquals(MANIFEST_ID, payload.get('mergeManifestId'));
    }

    @IsTest
    static void missingDestinationCredentials_rejected() {
        SeedContext ctx = loadMissingCredentialsSeedContext();
        Blob clsBytes = Blob.valueOf('class X {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('INVALID_REQUEST', payload.get('code'));
        System.assertEquals(
            String.valueOf(ctx.planId),
            String.valueOf(payload.get('deploymentPlanId'))
        );
        System.assertEquals(FIXTURE_PLAN_MISSING_CREDS, queryPlanName(ctx.planId));
    }

    @IsTest
    static void maximumBatchSize_rejected() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob tiny = Blob.valueOf('x');
        List<Object> units = new List<Object>();
        for (Integer index = 0; index < 6; index++) {
            String name = 'C' + index;
            String clsArtifactId =
                'merge/mfm_retrieval_1/classes/' +
                name +
                '/ApexClass/cls';
            String metaArtifactId =
                'merge/mfm_retrieval_1/classes/' +
                name +
                '/ApexClass/metaXml';
            units.add(
                new Map<String, Object>{
                    'metadataName' => name,
                    'cls' => roleDescriptor(clsArtifactId, tiny),
                    'metaXml' => roleDescriptor(metaArtifactId, tiny)
                }
            );
        }
        String manifest = JSON.serialize(
            new Map<String, Object>{
                'mergeManifestId' => MANIFEST_ID,
                'units' => units
            }
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifest
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals('INVALID_REQUEST', payload.get('code'));
    }

    @IsTest
    static void failureHalfwayThroughBatch_reportsPartialArtifacts() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class Half {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Test.setMock(
            HttpCalloutMock.class,
            new RoutingMock(
                authBody(true),
                new Map<String, Integer>{
                    CLS_ARTIFACT => 200,
                    META_ARTIFACT => 503
                },
                new Map<String, Blob>{ CLS_ARTIFACT => clsBytes }
            )
        );

        String json = retrieveWithCommittedCalloutWindow(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals(
            null,
            payload.get('persistedArtifacts'),
            'No DML should occur before all callouts succeed.'
        );
    }

    @IsTest
    static void controllerWrapper_validatesPlanAndReturnsReferences() {
        SeedContext ctx = loadDefaultSeedContext();
        Blob clsBytes = Blob.valueOf('class ViaCtrl {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        Test.setMock(
            HttpCalloutMock.class,
            buildSuccessMock(clsBytes, metaBytes)
        );

        Test.startTest();
        String json = ApexMergeController.persistSealedMergeArtifacts(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            buildManifestJson(clsBytes, metaBytes, true)
        );
        Test.stopTest();

        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(true, payload.get('success'), json);
        assertNoSecrets(json);
    }

    private class SeedContext {
        public Id comparisonId;
        public Id planId;
        public Id destinationOrgId;
    }

    private class RoutingMock implements HttpCalloutMock {
        private Map<String, Object> authorizeBody;
        private Map<String, Integer> statusByArtifact;
        private Map<String, Blob> bytesByArtifact;
        private String errorJson;
        private Map<String, Integer> contentLengthByArtifact;

        RoutingMock(
            Map<String, Object> authorizeBody,
            Map<String, Integer> statusByArtifact,
            Map<String, Blob> bytesByArtifact
        ) {
            this(authorizeBody, statusByArtifact, bytesByArtifact, null, null);
        }

        RoutingMock(
            Map<String, Object> authorizeBody,
            Map<String, Integer> statusByArtifact,
            Map<String, Blob> bytesByArtifact,
            String errorJson
        ) {
            this(authorizeBody, statusByArtifact, bytesByArtifact, errorJson, null);
        }

        RoutingMock(
            Map<String, Object> authorizeBody,
            Map<String, Integer> statusByArtifact,
            Map<String, Blob> bytesByArtifact,
            String errorJson,
            Map<String, Integer> contentLengthByArtifact
        ) {
            this.authorizeBody = authorizeBody;
            this.statusByArtifact = statusByArtifact;
            this.bytesByArtifact = bytesByArtifact;
            this.errorJson = errorJson;
            this.contentLengthByArtifact = contentLengthByArtifact;
        }

        public HTTPResponse respond(HTTPRequest req) {
            if (req.getEndpoint().contains('/artifact-handoff/authorize')) {
                return jsonResponse(200, JSON.serialize(authorizeBody));
            }

            String artifactId = extractArtifactId(req.getEndpoint());
            Integer status = statusByArtifact.containsKey(artifactId)
                ? statusByArtifact.get(artifactId)
                : 404;
            if (status == 200) {
                Blob bytes = bytesByArtifact.get(artifactId);
                Integer contentLength = bytes == null ? 0 : bytes.size();
                if (
                    contentLengthByArtifact != null &&
                    contentLengthByArtifact.containsKey(artifactId)
                ) {
                    contentLength = contentLengthByArtifact.get(artifactId);
                }
                return blobResponse(200, bytes, contentLength);
            }
            if (String.isNotBlank(errorJson)) {
                return jsonResponse(status, errorJson);
            }
            return jsonResponse(
                status,
                '{"success":false,"error":"Artifact unavailable"}'
            );
        }
    }

    private class StaticMock implements HttpCalloutMock {
        Integer statusCode;
        String jsonBody;
        Blob binaryBody;
        Integer contentLength;

        StaticMock(
            Integer statusCode,
            String jsonBody,
            Blob binaryBody,
            Integer contentLength
        ) {
            this.statusCode = statusCode;
            this.jsonBody = jsonBody;
            this.binaryBody = binaryBody;
            this.contentLength = contentLength;
        }

        public HTTPResponse respond(HTTPRequest req) {
            if (binaryBody != null) {
                return blobResponse(statusCode, binaryBody, contentLength);
            }
            return jsonResponse(statusCode, jsonBody);
        }
    }

    private static RoutingMock buildSuccessMock(Blob clsBytes, Blob metaBytes) {
        return new RoutingMock(
            authBody(true),
            new Map<String, Integer>{
                CLS_ARTIFACT => 200,
                META_ARTIFACT => 200
            },
            new Map<String, Blob>{
                CLS_ARTIFACT => clsBytes,
                META_ARTIFACT => metaBytes
            }
        );
    }

    private static Map<String, Object> authBody(Boolean authorized) {
        return new Map<String, Object>{
            'success' => true,
            'authorized' => authorized,
            'mergeSessionId' => SESSION_ID,
            'mergeManifestId' => MANIFEST_ID,
            'verifiedOrgId' => DST_ORG_ID
        };
    }

    private static String buildManifestJsonWithManifestId(
        String mergeManifestId,
        Blob clsBytes,
        Blob metaBytes,
        Boolean includeSession
    ) {
        Map<String, Object> manifest = new Map<String, Object>{
            'mergeManifestId' => mergeManifestId,
            'units' => new List<Object>{
                buildUnit('Foo', CLS_ARTIFACT, META_ARTIFACT, clsBytes, metaBytes)
            }
        };
        if (includeSession == true) {
            manifest.put('mergeSessionId', SESSION_ID);
        }
        return JSON.serialize(manifest);
    }

    private static String buildManifestJson(
        Blob clsBytes,
        Blob metaBytes,
        Boolean includeSession
    ) {
        Map<String, Object> manifest = new Map<String, Object>{
            'mergeManifestId' => MANIFEST_ID,
            'units' => new List<Object>{
                buildUnit('Foo', CLS_ARTIFACT, META_ARTIFACT, clsBytes, metaBytes)
            }
        };
        if (includeSession == true) {
            manifest.put('mergeSessionId', SESSION_ID);
        }
        return JSON.serialize(manifest);
    }

    private static String buildTwoUnitManifest(
        Blob clsBytes,
        Blob metaBytes,
        Blob clsBytesB,
        Blob metaBytesB
    ) {
        return JSON.serialize(
            new Map<String, Object>{
                'mergeManifestId' => MANIFEST_ID,
                'mergeSessionId' => SESSION_ID,
                'units' => new List<Object>{
                    buildUnit(
                        'Foo',
                        CLS_ARTIFACT,
                        META_ARTIFACT,
                        clsBytes,
                        metaBytes
                    ),
                    buildUnit(
                        'Bar',
                        'merge/mfm_retrieval_1/classes/Bar/ApexClass/cls',
                        'merge/mfm_retrieval_1/classes/Bar/ApexClass/metaXml',
                        clsBytesB,
                        metaBytesB
                    )
                }
            }
        );
    }

    private static Map<String, Object> buildUnit(
        String metadataName,
        String clsArtifactId,
        String metaArtifactId,
        Blob clsBytes,
        Blob metaBytes
    ) {
        return new Map<String, Object>{
            'metadataName' => metadataName,
            'cls' => roleDescriptor(clsArtifactId, clsBytes),
            'metaXml' => roleDescriptor(metaArtifactId, metaBytes)
        };
    }

    private static Map<String, Object> roleDescriptor(
        String artifactId,
        Blob bytes
    ) {
        return new Map<String, Object>{
            'artifactId' => artifactId,
            'sha256' => sha256Hex(bytes),
            'byteLength' => bytes.size()
        };
    }

    private static void insertConflictDuplicateMeta(Id planId, Blob bytes) {
        insertStoredArtifact(planId, 'Foo', 'metaXml', META_ARTIFACT, bytes);
    }

    private static void insertStoredArtifact(
        Id planId,
        String metadataName,
        String role,
        String artifactId,
        Blob bytes
    ) {
        String extension = role == 'metaXml' ? '.cls-meta.xml' : '.cls';
        insert new ContentVersion(
            Title = artifactId,
            PathOnClient = metadataName + extension,
            VersionData = bytes,
            FirstPublishLocationId = planId,
            Description =
                'apex-merge-artifact|' +
                String.valueOf(planId) +
                '|' +
                MANIFEST_ID +
                '|' +
                artifactId +
                '|' +
                metadataName +
                '|' +
                role +
                '|' +
                sha256Hex(bytes) +
                '|' +
                bytes.size()
        );
    }

    private static String extractArtifactId(String endpoint) {
        Integer marker = endpoint.indexOf('/artifacts/');
        if (marker < 0) {
            return null;
        }
        String tail = endpoint.substring(marker + '/artifacts/'.length());
        Integer queryIdx = tail.indexOf('?');
        if (queryIdx >= 0) {
            tail = tail.substring(0, queryIdx);
        }
        return EncodingUtil.urlDecode(tail, 'UTF-8');
    }

    private static HTTPResponse jsonResponse(Integer statusCode, String body) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(body);
        res.setStatus(statusCode >= 200 && statusCode < 300 ? 'OK' : 'Error');
        return res;
    }

    private static HTTPResponse blobResponse(
        Integer statusCode,
        Blob body,
        Integer contentLength
    ) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setHeader('Content-Type', 'application/octet-stream');
        if (contentLength != null) {
            res.setHeader('Content-Length', String.valueOf(contentLength));
        }
        res.setBodyAsBlob(body);
        res.setStatus(statusCode >= 200 && statusCode < 300 ? 'OK' : 'Error');
        return res;
    }

    private static Map<String, Object> parsePayload(String responseJson) {
        return (Map<String, Object>) JSON.deserializeUntyped(responseJson);
    }

    private static void assertNoSecrets(String json) {
        System.assert(!json.contains(MOCK_RT), json);
        System.assert(!json.toLowerCase().contains('refreshtoken'), json);
    }

    private static String sha256Hex(Blob value) {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', value)
        ).toLowerCase();
    }

    /**
     * @TestSetup file/fixture work must not block callouts unless the callout runs inside startTest.
     */
    private static String retrieveWithCommittedCalloutWindow(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String manifestJson
    ) {
        Test.startTest();
        String json = ApexMergeArtifactRetrievalService.retrieveAndPersist(
            comparisonId,
            deploymentPlanId,
            mergeSessionId,
            manifestJson
        );
        Test.stopTest();
        return json;
    }

    private static Integer countLatestArtifactsForPlan(
        Id planId,
        String artifactTitle
    ) {
        return [
            SELECT COUNT()
            FROM ContentVersion
            WHERE Title = :artifactTitle
            AND IsLatest = true
            AND FirstPublishLocationId = :planId
        ];
    }

    private static List<ApexMergeArtifactRetrievalService.ManifestUnit> parseManifestUnits(
        String manifestJson
    ) {
        Map<String, Object> manifest = (Map<String, Object>) JSON.deserializeUntyped(
            manifestJson
        );
        ApexMergeArtifactRetrievalService.ManifestParseResult parsed =
            ApexMergeArtifactRetrievalService.parseCanonicalManifest(manifest);
        System.assertEquals(
            true,
            parsed.success == true,
            parsed.message != null
                ? parsed.message
                : 'Canonical manifest parse must succeed.'
        );
        return parsed.units;
    }

    private static String seedQueuedArtifactStatus(
        SeedContext ctx,
        String manifestJson
    ) {
        List<ApexMergeArtifactRetrievalService.ManifestUnit> units =
            parseManifestUnits(manifestJson);
        List<String> metadataNames = new List<String>();
        for (ApexMergeArtifactRetrievalService.ManifestUnit unit : units) {
            metadataNames.add(unit.metadataName);
        }
        String statusRunId = ApexMergeArtifactStatusService.newStatusRunId();
        ApexMergeArtifactStatusService.StatusSnapshot snapshot =
            ApexMergeArtifactStatusService.newQueuedSnapshot(
                MANIFEST_ID,
                SESSION_ID,
                ctx.comparisonId,
                ctx.planId,
                metadataNames
            );
        snapshot.statusRunId = statusRunId;
        System.assertEquals(
            true,
            ApexMergeArtifactStatusService.persist(snapshot).success
        );
        return statusRunId;
    }

    private static ApexMergeArtifactStatusService.StatusSnapshot loadStoredStatusSnapshot(
        Id planId
    ) {
        ApexMergeArtifactStatusService.LoadResult loaded =
            ApexMergeArtifactStatusService.loadFromDeploymentPlan(planId);
        System.assert(
            loaded.success == true,
            String.isNotBlank(loaded.message)
                ? loaded.message
                : 'Expected durable artifact status on deployment plan.'
        );
        return loaded.snapshot;
    }

    private static void assertPlanOverallStatus(Id planId, String expected) {
        Deployment_Plan__c plan = [
            SELECT Latest_Apex_Merge_Artifact_Status__c
            FROM Deployment_Plan__c
            WHERE Id = :planId
            LIMIT 1
        ];
        System.assertEquals(expected, plan.Latest_Apex_Merge_Artifact_Status__c);
    }

    private static void assertAsyncAcceptedPayload(
        Map<String, Object> payload,
        Id deploymentPlanId,
        Integer expectedUnitCount
    ) {
        System.assertEquals(true, payload.get('success'));
        System.assertEquals(true, payload.get('async'));
        System.assertEquals(expectedUnitCount, payload.get('queuedUnitCount'));
        System.assertEquals(
            null,
            payload.get('persistedArtifacts'),
            'Async acceptance must not return persisted artifact references.'
        );
        System.assertEquals(SESSION_ID, payload.get('mergeSessionId'));
        System.assertEquals(MANIFEST_ID, payload.get('mergeManifestId'));
        System.assertEquals(
            String.valueOf(deploymentPlanId),
            String.valueOf(payload.get('deploymentPlanId'))
        );
        if (payload.containsKey('statusRunId')) {
            System.assert(
                String.isNotBlank(String.valueOf(payload.get('statusRunId')))
            );
        }
    }

    private static void assertQueuedStatusPersisted(
        Id deploymentPlanId,
        String expectedStatusRunId,
        List<String> expectedMetadataNames,
        Id comparisonId
    ) {
        Deployment_Plan__c plan = [
            SELECT
                Latest_Apex_Merge_Artifact_Status__c,
                Latest_Apex_Merge_Artifact_JSON__c,
                Latest_Apex_Merge_Artifact_Started_At__c,
                Latest_Apex_Merge_Artifact_Completed_At__c
            FROM Deployment_Plan__c
            WHERE Id = :deploymentPlanId
            LIMIT 1
        ];
        System.assertEquals(
            ApexMergeArtifactStatusService.OVERALL_QUEUED,
            plan.Latest_Apex_Merge_Artifact_Status__c
        );
        System.assertNotEquals(null, plan.Latest_Apex_Merge_Artifact_JSON__c);
        System.assertNotEquals(null, plan.Latest_Apex_Merge_Artifact_Started_At__c);
        System.assertEquals(null, plan.Latest_Apex_Merge_Artifact_Completed_At__c);

        ApexMergeArtifactStatusService.StatusSnapshot snapshot =
            ApexMergeArtifactStatusService.deserialize(
                plan.Latest_Apex_Merge_Artifact_JSON__c
            );
        System.assertEquals(1, snapshot.schemaVersion);
        System.assertEquals(expectedStatusRunId, snapshot.statusRunId);
        System.assertEquals(MANIFEST_ID, snapshot.mergeManifestId);
        System.assertEquals(SESSION_ID, snapshot.mergeSessionId);
        System.assertEquals(
            String.valueOf(comparisonId),
            snapshot.comparisonId
        );
        System.assertEquals(
            String.valueOf(deploymentPlanId),
            snapshot.deploymentPlanId
        );
        System.assertEquals(
            ApexMergeArtifactStatusService.OVERALL_QUEUED,
            snapshot.overallStatus
        );
        System.assertEquals(
            expectedMetadataNames.size(),
            snapshot.totalUnits
        );
        System.assertEquals(-1, snapshot.currentUnitIndex);
        System.assertEquals(null, snapshot.completedAt);
        System.assertEquals(null, snapshot.lastError);
        System.assert(String.isNotBlank(snapshot.startedAt));
        System.assert(String.isNotBlank(snapshot.updatedAt));

        System.assertEquals(expectedMetadataNames.size(), snapshot.units.size());
        for (Integer i = 0; i < expectedMetadataNames.size(); i++) {
            System.assertEquals(
                expectedMetadataNames[i],
                snapshot.units[i].metadataName
            );
            System.assertEquals(
                ApexMergeArtifactStatusService.UNIT_NOT_STARTED,
                snapshot.units[i].status
            );
            System.assertEquals(
                ApexMergeArtifactStatusService.UNIT_NOT_STARTED,
                snapshot.units[i].artifacts.cls.status
            );
            System.assertEquals(
                ApexMergeArtifactStatusService.UNIT_NOT_STARTED,
                snapshot.units[i].artifacts.metaXml.status
            );
        }
    }

    private static Map<String, Object> buildLargeSingleUnitManifest() {
        Blob clsBytes = Blob.valueOf('class Large {}');
        Blob metaBytes = Blob.valueOf('<ApexClass/>');
        return new Map<String, Object>{
            'mergeManifestId' => MANIFEST_ID,
            'mergeSessionId' => SESSION_ID,
            'units' => new List<Object>{
                new Map<String, Object>{
                    'metadataName' => 'BigOne',
                    'cls' => new Map<String, Object>{
                        'artifactId' => CLS_ARTIFACT,
                        'sha256' => sha256Hex(clsBytes),
                        'byteLength' => 900000
                    },
                    'metaXml' => new Map<String, Object>{
                        'artifactId' => META_ARTIFACT,
                        'sha256' => sha256Hex(metaBytes),
                        'byteLength' => 250000
                    }
                }
            }
        };
    }

    private static String queryPlanName(Id planId) {
        return [
            SELECT Name
            FROM Deployment_Plan__c
            WHERE Id = :planId
            LIMIT 1
        ]
        .Name;
    }

    private static SeedContext planSeedContext(String planName) {
        Deployment_Plan__c plan = [
            SELECT
                Id,
                Metadata_Comparison__c,
                Destination_Org__c
            FROM Deployment_Plan__c
            WHERE Name = :planName
            LIMIT 1
        ];
        SeedContext ctx = new SeedContext();
        ctx.comparisonId = plan.Metadata_Comparison__c;
        ctx.planId = plan.Id;
        ctx.destinationOrgId = plan.Destination_Org__c;
        return ctx;
    }

    private static void assertAsyncAcceptanceRejectsTerminal(String terminalOverall) {
        SeedContext ctx = loadConflictSeedContext();
        String manifestJson = buildTwoUnitManifest(
            Blob.valueOf('class A {}'),
            Blob.valueOf('<ApexClass/>'),
            Blob.valueOf('class B {}'),
            Blob.valueOf('<ApexClass status="B"/>')
        );
        writeDurableAcceptanceState(ctx, manifestJson, terminalOverall);
        Test.setMock(
            HttpCalloutMock.class,
            new StaticMock(401, '{"success":false,"error":"Unauthorized"}', null, null)
        );
        Integer queueablesBefore = Limits.getQueueableJobs();
        String json = ApexMergeArtifactRetrievalService.retrieveAndPersist(
            ctx.comparisonId,
            ctx.planId,
            SESSION_ID,
            manifestJson
        );
        Map<String, Object> payload = parsePayload(json);
        System.assertEquals(false, payload.get('success'));
        System.assertEquals(
            ApexMergeArtifactRetrievalService.CODE_RUN_TERMINATED,
            payload.get('code')
        );
        System.assertEquals(
            0,
            Limits.getQueueableJobs() - queueablesBefore,
            'Terminal run must block a new async accept.'
        );
    }

    private static void writeDurableAcceptanceState(
        SeedContext ctx,
        String manifestJson,
        String overallStatus
    ) {
        List<ApexMergeArtifactRetrievalService.ManifestUnit> units =
            parseManifestUnits(manifestJson);
        List<String> metadataNames = new List<String>();
        for (ApexMergeArtifactRetrievalService.ManifestUnit unit : units) {
            metadataNames.add(unit.metadataName);
        }
        ApexMergeArtifactStatusService.StatusSnapshot snapshot =
            ApexMergeArtifactStatusService.newQueuedSnapshot(
                MANIFEST_ID,
                SESSION_ID,
                ctx.comparisonId,
                ctx.planId,
                metadataNames
            );
        snapshot.statusRunId = ApexMergeArtifactStatusService.newStatusRunId();
        snapshot.overallStatus = overallStatus;
        if (
            ApexMergeArtifactStatusService.OVERALL_QUEUED.equals(overallStatus)
        ) {
            snapshot.currentUnitIndex = -1;
            snapshot.completedAt = null;
        } else if (
            ApexMergeArtifactStatusService.OVERALL_PROCESSING.equals(
                overallStatus
            )
        ) {
            snapshot.currentUnitIndex = 0;
            snapshot.completedAt = null;
        } else {
            snapshot.currentUnitIndex = units.size() - 1;
            snapshot.completedAt = ApexMergeArtifactStatusService.nowIsoUtc();
        }
        System.assertEquals(
            true,
            ApexMergeArtifactStatusService.validate(snapshot).success,
            'Durable acceptance seed snapshot must validate.'
        );
        Deployment_Plan__c row = new Deployment_Plan__c(Id = ctx.planId);
        row.Latest_Apex_Merge_Artifact_Status__c = overallStatus;
        row.Latest_Apex_Merge_Artifact_JSON__c =
            ApexMergeArtifactStatusService.serialize(snapshot);
        row.Latest_Apex_Merge_Artifact_Started_At__c = Datetime.now();
        if (
            ApexMergeArtifactStatusService.OVERALL_COMPLETED.equals(
                overallStatus
            ) ||
            ApexMergeArtifactStatusService.OVERALL_FAILED.equals(overallStatus) ||
            ApexMergeArtifactStatusService.OVERALL_PARTIALLY_FAILED.equals(
                overallStatus
            )
        ) {
            row.Latest_Apex_Merge_Artifact_Completed_At__c = Datetime.now();
        } else {
            row.Latest_Apex_Merge_Artifact_Completed_At__c = null;
        }
        update row;
    }

    private static SeedContext loadDefaultSeedContext() {
        return planSeedContext(FIXTURE_PLAN_DEFAULT);
    }

    private static SeedContext loadConflictSeedContext() {
        return planSeedContext(FIXTURE_PLAN_CONFLICT);
    }

    private static SeedContext loadRetryIdempotentSeedContext() {
        return planSeedContext(FIXTURE_PLAN_RETRY);
    }

    private static SeedContext loadMissingCredentialsSeedContext() {
        return planSeedContext(FIXTURE_PLAN_MISSING_CREDS);
    }

    private static Id loadOtherComparisonId() {
        return [
            SELECT Id
            FROM Metadata_Comparison__c
            WHERE Name = :FIXTURE_CMP_OTHER
            LIMIT 1
        ]
        .Id;
    }
}