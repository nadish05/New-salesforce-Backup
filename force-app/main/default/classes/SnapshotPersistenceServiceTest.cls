@IsTest
private class SnapshotPersistenceServiceTest {

    private class ArtifactCalloutMock implements HttpCalloutMock {
        Integer statusCode;
        Blob body;
        String expectedSnapshotId;
        String expectedArtifactId;
        String expectedHistoryId;
        Integer respondCount = 0;

        ArtifactCalloutMock(
            Integer statusCode,
            Blob body,
            String expectedSnapshotId,
            String expectedArtifactId,
            String expectedHistoryId
        ) {
            this.statusCode = statusCode;
            this.body = body;
            this.expectedSnapshotId = expectedSnapshotId;
            this.expectedArtifactId = expectedArtifactId;
            this.expectedHistoryId = expectedHistoryId;
        }

        public HTTPResponse respond(HTTPRequest req) {
            respondCount++;

            System.assert(
                req.getEndpoint().contains('/api/deployment/snapshot-artifact'),
                'Expected snapshot artifact endpoint.'
            );
            System.assertEquals('GET', req.getMethod());

            if (expectedSnapshotId != null) {
                System.assert(
                    req.getEndpoint().contains(
                        EncodingUtil.urlEncode(expectedSnapshotId, 'UTF-8')
                    ),
                    'Expected snapshotId query parameter.'
                );
            }

            if (expectedArtifactId != null) {
                System.assert(
                    req.getEndpoint().contains(
                        EncodingUtil.urlEncode(expectedArtifactId, 'UTF-8')
                    ),
                    'Expected artifactId query parameter.'
                );
            }

            if (expectedHistoryId != null) {
                System.assert(
                    req.getEndpoint().contains(
                        EncodingUtil.urlEncode(expectedHistoryId, 'UTF-8')
                    ),
                    'Expected historyId query parameter.'
                );
            }

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/octet-stream');
            res.setStatusCode(statusCode);

            if (body != null) {
                res.setBodyAsBlob(body);
            } else {
                res.setBody('');
            }

            return res;
        }
    }

    @IsTest
    static void absentSnapshotExportCreatesNothing() {
        Test.startTest();
        String enriched = SnapshotPersistenceService.applyToDeploymentResponse(
            JSON.serialize(
                new Map<String, Object>{
                    'deploymentHistory' => new Map<String, Object>{
                        'historyId' => 'history_absent',
                        'status' => 'SUCCESS'
                    }
                }
            )
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(enriched);
        System.assertEquals(false, parsed.containsKey('snapshotPersistence'));
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Deployment_Snapshot__c]
        );
    }

    @IsTest
    static void validSealedSnapshotCreatesRecord() {
        Blob artifactBytes = EncodingUtil.convertFromHex('0001FF0A0D');
        String artifactHash = sha256Hex(artifactBytes);
        String snapshotId = 'snap-valid-sealed';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'AccountService');

        Test.setMock(
            HttpCalloutMock.class,
            new ArtifactCalloutMock(
                200,
                artifactBytes,
                snapshotId,
                artifactId,
                'history_valid'
            )
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(buildExport(snapshotId, artifactId, artifactHash, true)),
                'history_valid'
            );
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Deployment_Snapshot__c snapshot = [
            SELECT Status__c, Snapshot_Id__c, Overall_Integrity_Hash__c
            FROM Deployment_Snapshot__c
            WHERE Snapshot_Id__c = :snapshotId
            LIMIT 1
        ];
        System.assertEquals('SEALED', snapshot.Status__c);
        System.assertEquals('overall-hash-1', snapshot.Overall_Integrity_Hash__c);
    }

    @IsTest
    static void sameSnapshotIdIsIdempotent() {
        Blob artifactBytes = EncodingUtil.convertFromHex('010203');
        String artifactHash = sha256Hex(artifactBytes);
        String snapshotId = 'snap-idempotent';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'AccountService');

        ArtifactCalloutMock mock = new ArtifactCalloutMock(
            200,
            artifactBytes,
            snapshotId,
            artifactId,
            'history_idempotent'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        String exportJson = JSON.serialize(
            buildExport(snapshotId, artifactId, artifactHash, true)
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult first =
            SnapshotPersistenceService.persistSnapshotExport(
                exportJson,
                'history_idempotent'
            );
        SnapshotPersistenceService.PersistResult second =
            SnapshotPersistenceService.persistSnapshotExport(
                exportJson,
                'history_idempotent'
            );
        Test.stopTest();

        System.assertEquals(true, first.success);
        System.assertEquals(true, second.success);
        System.assertEquals('ALREADY_PERSISTED', second.code);
        System.assertEquals(1, mock.respondCount);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Deployment_Snapshot__c WHERE Snapshot_Id__c = :snapshotId]
        );
    }

    @IsTest
    static void memberPersistenceCreatesMemberRows() {
        Blob artifactBytes = Blob.valueOf('member-bytes');
        String artifactHash = sha256Hex(artifactBytes);
        String snapshotId = 'snap-members';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'Foo');

        Test.setMock(
            HttpCalloutMock.class,
            new ArtifactCalloutMock(
                200,
                artifactBytes,
                snapshotId,
                artifactId,
                'history_members'
            )
        );

        Map<String, Object> snapshotExport = buildExport(
            snapshotId,
            artifactId,
            artifactHash,
            true
        );
        snapshotExport.put('memberCount', 2);
        snapshotExport.put(
            'members',
            new List<Object>{
                buildModifiedMember(
                    'ApexClass',
                    'Foo',
                    artifactId,
                    artifactHash,
                    'expected-after-hash'
                ),
                buildNewMember('CustomObject', 'Bar__c')
            }
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(snapshotExport),
                'history_members'
            );
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Deployment_Snapshot_Member__c
                WHERE Deployment_Snapshot__r.Snapshot_Id__c = :snapshotId
            ]
        );
    }

    @IsTest
    static void newMemberPersistsWithoutArtifactCallout() {
        String snapshotId = 'snap-new-only';
        Map<String, Object> snapshotExport = buildExport(
            snapshotId,
            null,
            null,
            false
        );
        snapshotExport.put('memberCount', 1);
        snapshotExport.put(
            'members',
            new List<Object>{ buildNewMember('CustomObject', 'Widget__c') }
        );
        snapshotExport.put('overallIntegrityHash', 'overall-hash-new');
        snapshotExport.put('rollbackEligible', false);

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(snapshotExport),
                'history_new'
            );
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Deployment_Snapshot_Member__c member = [
            SELECT Change_Class__c, Artifact_Id__c, Capture_Status__c
            FROM Deployment_Snapshot_Member__c
            WHERE Deployment_Snapshot__r.Snapshot_Id__c = :snapshotId
            LIMIT 1
        ];
        System.assertEquals('NEW', member.Change_Class__c);
        System.assertEquals(null, member.Artifact_Id__c);
        System.assertEquals('NOT_REQUIRED', member.Capture_Status__c);
    }

    @IsTest
    static void modifiedMemberStoresExactBinaryBytes() {
        Blob artifactBytes = EncodingUtil.convertFromHex('0001FF0A0D');
        String artifactHash = sha256Hex(artifactBytes);
        String snapshotId = 'snap-binary';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'BinarySvc');

        Test.setMock(
            HttpCalloutMock.class,
            new ArtifactCalloutMock(
                200,
                artifactBytes,
                snapshotId,
                artifactId,
                'history_binary'
            )
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(
                    buildExport(snapshotId, artifactId, artifactHash, true)
                ),
                'history_binary'
            );
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);

        Deployment_Snapshot_Member__c member = [
            SELECT Content_Document_Id__c
            FROM Deployment_Snapshot_Member__c
            WHERE Deployment_Snapshot__r.Snapshot_Id__c = :snapshotId
            LIMIT 1
        ];

        ContentVersion version = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :member.Content_Document_Id__c
            AND IsLatest = true
            LIMIT 1
        ];
        System.assertEquals(artifactHash, sha256Hex(version.VersionData));
    }

    @IsTest
    static void artifact404FailsClosed() {
        String snapshotId = 'snap-artifact-404';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'Missing');

        Test.setMock(
            HttpCalloutMock.class,
            new ArtifactCalloutMock(
                404,
                null,
                snapshotId,
                artifactId,
                'history_404'
            )
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(
                    buildExport(
                        snapshotId,
                        artifactId,
                        'deadbeef',
                        true
                    )
                ),
                'history_404'
            );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('SNAPSHOT_ARTIFACT_NOT_FOUND', result.code);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Deployment_Snapshot__c WHERE Snapshot_Id__c = :snapshotId]
        );
    }

    @IsTest
    static void artifact503FailsClosed() {
        String snapshotId = 'snap-artifact-503';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'Unavailable');

        Test.setMock(
            HttpCalloutMock.class,
            new ArtifactCalloutMock(
                503,
                null,
                snapshotId,
                artifactId,
                'history_503'
            )
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(
                    buildExport(
                        snapshotId,
                        artifactId,
                        'deadbeef',
                        true
                    )
                ),
                'history_503'
            );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('SNAPSHOT_ARTIFACT_UNAVAILABLE', result.code);
    }

    @IsTest
    static void artifact400FailsClosed() {
        String snapshotId = 'snap-artifact-400';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'BadRequest');

        Test.setMock(
            HttpCalloutMock.class,
            new ArtifactCalloutMock(
                400,
                null,
                snapshotId,
                artifactId,
                'history_400'
            )
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(
                    buildExport(
                        snapshotId,
                        artifactId,
                        'deadbeef',
                        true
                    )
                ),
                'history_400'
            );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('SNAPSHOT_ARTIFACT_INVALID', result.code);
    }

    @IsTest
    static void memberCountMismatchFailsClosed() {
        String snapshotId = 'snap-count-mismatch';
        Map<String, Object> snapshotExport = buildExport(
            snapshotId,
            null,
            null,
            false
        );
        snapshotExport.put('memberCount', 2);
        snapshotExport.put(
            'members',
            new List<Object>{ buildNewMember('CustomObject', 'OnlyOne__c') }
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(snapshotExport),
                'history_count'
            );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('SNAPSHOT_MEMBER_COUNT_MISMATCH', result.code);
    }

    @IsTest
    static void invalidStatusFailsClosed() {
        Map<String, Object> snapshotExport = buildExport(
            'snap-invalid-status',
            null,
            null,
            false
        );
        snapshotExport.put('status', 'READY');

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(snapshotExport),
                'history_status'
            );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('SNAPSHOT_STATUS_INVALID', result.code);
    }

    @IsTest
    static void integrityMismatchDoesNotRemainRollbackEligible() {
        Blob artifactBytes = Blob.valueOf('integrity-bytes');
        String wrongHash = '0000000000000000000000000000000000000000000000000000000000000000';
        String snapshotId = 'snap-integrity';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'Integrity');

        Test.setMock(
            HttpCalloutMock.class,
            new ArtifactCalloutMock(
                200,
                artifactBytes,
                snapshotId,
                artifactId,
                'history_integrity'
            )
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(
                    buildExport(snapshotId, artifactId, wrongHash, true)
                ),
                'history_integrity'
            );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('SNAPSHOT_INTEGRITY_MISMATCH', result.code);

        List<Deployment_Snapshot__c> snapshots = [
            SELECT Status__c, Rollback_Eligible__c
            FROM Deployment_Snapshot__c
            WHERE Snapshot_Id__c = :snapshotId
        ];

        if (!snapshots.isEmpty()) {
            System.assertEquals('FAILED', snapshots[0].Status__c);
            System.assertEquals(false, snapshots[0].Rollback_Eligible__c);
        }
    }

    @IsTest
    static void completePersistenceSealsSnapshot() {
        Blob artifactBytes = Blob.valueOf('sealed-bytes');
        String artifactHash = sha256Hex(artifactBytes);
        String snapshotId = 'snap-complete';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'Complete');

        Test.setMock(
            HttpCalloutMock.class,
            new ArtifactCalloutMock(
                200,
                artifactBytes,
                snapshotId,
                artifactId,
                'history_complete'
            )
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(
                    buildExport(snapshotId, artifactId, artifactHash, true)
                ),
                'history_complete'
            );
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Deployment_Snapshot__c snapshot = [
            SELECT Status__c, Sealed_At__c, Rollback_Eligible__c
            FROM Deployment_Snapshot__c
            WHERE Snapshot_Id__c = :snapshotId
            LIMIT 1
        ];
        System.assertEquals('SEALED', snapshot.Status__c);
        System.assertNotEquals(null, snapshot.Sealed_At__c);
        System.assertEquals(true, snapshot.Rollback_Eligible__c);
    }

    @IsTest
    static void historyCorrelationSetsSnapshotId() {
        Blob artifactBytes = Blob.valueOf('history-bytes');
        String artifactHash = sha256Hex(artifactBytes);
        String snapshotId = 'snap-history';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'HistorySvc');
        String historyId = 'history_corr_001';

        DeploymentHistoryDTO dto = new DeploymentHistoryDTO();
        dto.historyId = historyId;
        dto.status = 'SUCCESS';
        DeploymentHistoryService.save(dto);

        Test.setMock(
            HttpCalloutMock.class,
            new ArtifactCalloutMock(
                200,
                artifactBytes,
                snapshotId,
                artifactId,
                historyId
            )
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(
                    buildExport(snapshotId, artifactId, artifactHash, true)
                ),
                historyId
            );
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);

        Deployment_History__c history = [
            SELECT Snapshot_Id__c
            FROM Deployment_History__c
            WHERE Backend_History_Id__c = :historyId
            LIMIT 1
        ];
        System.assertEquals(snapshotId, history.Snapshot_Id__c);
    }

    @IsTest
    static void validateDeploymentWithoutSnapshotExportUnchanged() {
        String responseBody = JSON.serialize(
            new Map<String, Object>{
                'deploymentReadiness' => new Map<String, Object>{
                    'canDeploy' => true
                }
            }
        );

        Test.setMock(
            HttpCalloutMock.class,
            new ValidateDeploymentMock(responseBody)
        );

        Test.startTest();
        String result = DeploymentValidationController.validateDeployment(
            'rt',
            'https://example.my.salesforce.com',
            '00Dxx0000000001',
            samplePackageJson()
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.containsKey('snapshotPersistence'));
        System.assertNotEquals(null, parsed.get('deploymentReadiness'));
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Deployment_Snapshot__c]
        );
    }

    private class ValidateDeploymentMock implements HttpCalloutMock {
        String body;

        ValidateDeploymentMock(String body) {
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            System.assert(
                req.getEndpoint().contains('/api/deployment/validate')
            );
            System.assertEquals('POST', req.getMethod());

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(body);
            return res;
        }
    }

    private static String samplePackageJson() {
        return JSON.serialize(
            new Map<String, Object>{
                'repoUrl' => 'https://example.com/repo.git',
                'sourceBranch' => 'src',
                'destinationBranch' => 'dst',
                'selectedMetadata' => new List<Object>(),
                'requiredDependencies' => new List<Object>(),
                'selectedTestClasses' => new List<Object>()
            }
        );
    }

    @IsTest
    static void crossSnapshotArtifactIdFailsClosed() {
        String snapshotId = 'snap-cross';
        String artifactId = artifactIdFor(
            'other-snapshot',
            'ApexClass',
            'Cross'
        );

        Test.startTest();
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                JSON.serialize(
                    buildExport(
                        snapshotId,
                        artifactId,
                        'deadbeef',
                        true
                    )
                ),
                'history_cross'
            );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('SNAPSHOT_MEMBER_INVALID', result.code);
    }

    private static Map<String, Object> buildExport(
        String snapshotId,
        String artifactId,
        String destinationBeforeHash,
        Boolean rollbackEligible
    ) {
        List<Object> members = new List<Object>();

        if (artifactId != null) {
            members.add(
                buildModifiedMember(
                    'ApexClass',
                    'AccountService',
                    artifactId,
                    destinationBeforeHash,
                    'expected-after-hash'
                )
            );
        }

        return new Map<String, Object>{
            'snapshotId' => snapshotId,
            'deploymentId' => 'history_' + snapshotId,
            'sourceOrgId' => '00D000000000099',
            'destinationOrgId' => '00D000000000001',
            'sourceBranch' => 'feature/a',
            'destinationBranch' => 'uat',
            'status' => 'SEALED',
            'schemaVersion' => 1,
            'snapshotVersion' => 1,
            'overallIntegrityHash' => 'overall-hash-1',
            'rollbackEligible' => rollbackEligible,
            'createdAt' => '2026-08-27T10:00:00.000Z',
            'completedAt' => '2026-08-27T10:00:01.000Z',
            'sealedAt' => '2026-08-27T10:00:01.000Z',
            'memberCount' => members.size(),
            'members' => members
        };
    }

    private static Map<String, Object> buildModifiedMember(
        String metadataType,
        String metadataName,
        String artifactId,
        String destinationBeforeHash,
        String expectedAfterHash
    ) {
        return new Map<String, Object>{
            'metadataType' => metadataType,
            'metadataName' => metadataName,
            'filePath' =>
                'force-app/main/default/classes/' + metadataName + '.cls',
            'changeClass' => 'MODIFIED',
            'existedBefore' => true,
            'destinationBeforeHash' => destinationBeforeHash,
            'expectedAfterHash' => expectedAfterHash,
            'artifactId' => artifactId,
            'artifactSize' => 5,
            'captureStatus' => 'COMPLETE'
        };
    }

    private static Map<String, Object> buildNewMember(
        String metadataType,
        String metadataName
    ) {
        return new Map<String, Object>{
            'metadataType' => metadataType,
            'metadataName' => metadataName,
            'filePath' =>
                'force-app/main/default/objects/' + metadataName + '/object',
            'changeClass' => 'NEW',
            'existedBefore' => false,
            'destinationBeforeHash' => null,
            'expectedAfterHash' => null,
            'artifactId' => null,
            'artifactSize' => 0,
            'captureStatus' => 'ABSENT_PROVEN'
        };
    }

    private static String artifactIdFor(
        String snapshotId,
        String metadataType,
        String metadataName
    ) {
        return 'snapshots/' +
            snapshotId +
            '/destination-before/' +
            metadataType +
            '/' +
            metadataName;
    }

    private static String sha256Hex(Blob value) {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', value)
        ).toLowerCase();
    }
}