/**
 * Control-plane persistence contract tests.
 * No callouts, no destination retrieve/deploy, no rollback execution.
 */
@IsTest
private class ControlPlanePersistenceTest {

    @IsTest
    static void snapshotCreateAndGet() {
        ControlPlaneResult created = DeploymentSnapshotService.createSnapshot(
            snapshotPayload('snap-create')
        );
        System.assertEquals(true, created.success);
        ControlPlaneResult fetched =
            DeploymentSnapshotService.getSnapshot('snap-create');
        Deployment_Snapshot__c record =
            (Deployment_Snapshot__c) fetched.record;
        System.assertEquals('CAPTURING', record.Status__c);
        System.assertEquals('00D000000000001', record.Destination_Org_Id__c);
    }

    @IsTest
    static void snapshotMemberCreateAndGet() {
        DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-mem'));
        ControlPlaneResult added = DeploymentSnapshotService.addMember(
            'snap-mem',
            memberPayload('ApexClass', 'AccountService')
        );
        System.assertEquals(true, added.success);
        ControlPlaneResult fetched = DeploymentSnapshotService.getMember(
            'snap-mem',
            'ApexClass',
            'AccountService'
        );
        Deployment_Snapshot_Member__c member =
            (Deployment_Snapshot_Member__c) fetched.record;
        System.assertEquals('MODIFIED', member.Change_Class__c);
        System.assertEquals(true, member.Existed_Before__c);
        ControlPlaneResult members =
            DeploymentSnapshotService.getMembers('snap-mem');
        System.assertEquals(1, members.records.size());
    }

    @IsTest
    static void duplicateSnapshotIdBlocked() {
        DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-dup'));
        ControlPlaneResult second =
            DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-dup'));
        System.assertEquals(false, second.success);
        System.assertEquals('DUPLICATE_VALUE', second.code);
        System.assertEquals('Snapshot_Id__c', second.field);
    }

    @IsTest
    static void duplicateSnapshotMemberBlocked() {
        DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-mdup'));
        DeploymentSnapshotService.addMember(
            'snap-mdup',
            memberPayload('ApexClass', 'AccountService')
        );
        ControlPlaneResult second = DeploymentSnapshotService.addMember(
            'snap-mdup',
            memberPayload('ApexClass', 'AccountService')
        );
        System.assertEquals(false, second.success);
        System.assertEquals('DUPLICATE_VALUE', second.code);
    }

    @IsTest
    static void sealedSnapshotMutationBlocked() {
        DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-seal'));
        DeploymentSnapshotService.addMember(
            'snap-seal',
            memberPayload('ApexClass', 'AccountService')
        );
        ControlPlaneResult sealed =
            DeploymentSnapshotService.sealSnapshot('snap-seal');
        System.assertEquals(true, sealed.success);
        Deployment_Snapshot__c record =
            (Deployment_Snapshot__c) sealed.record;
        System.assertEquals('SEALED', record.Status__c);
        System.assertNotEquals(null, record.Sealed_At__c);

        ControlPlaneResult updateAttempt =
            DeploymentSnapshotService.updateSnapshot(
                'snap-seal',
                new Map<String, Object>{
                    'rollbackEligible' => false,
                    'overallIntegrityHash' => 'abc'
                }
            );
        System.assertEquals(false, updateAttempt.success);
        System.assertEquals('SEALED', updateAttempt.code);

        ControlPlaneResult memberAttempt = DeploymentSnapshotService.addMember(
            'snap-seal',
            memberPayload('ApexTrigger', 'AccountTrigger')
        );
        System.assertEquals(false, memberAttempt.success);
        System.assertEquals('SEALED', memberAttempt.code);
    }

    @IsTest
    static void artifactStoredOnContentVersionOnly() {
        DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-art'));
        DeploymentSnapshotService.addMember(
            'snap-art',
            memberPayload('ApexClass', 'AccountService')
        );
        Blob packed = Blob.valueOf('packed-destination-before-bytes');
        ControlPlaneResult stored =
            DeploymentSnapshotArtifactService.storeArtifact(
                'snap-art',
                'ApexClass',
                'AccountService',
                'art-001',
                packed
            );
        System.assertEquals(true, stored.success);
        Deployment_Snapshot_Member__c member =
            (Deployment_Snapshot_Member__c) stored.record;
        System.assertEquals('art-001', member.Artifact_Id__c);
        System.assertNotEquals(null, member.Content_Document_Id__c);
        System.assert(
            member.Artifact_Size__c > 0,
            'Artifact size must be stored as metadata.'
        );

        List<ContentVersion> versions = [
            SELECT Id, VersionData, Title
            FROM ContentVersion
            WHERE ContentDocumentId = :member.Content_Document_Id__c
        ];
        System.assertEquals(1, versions.size());
        System.assertEquals('art-001', versions[0].Title);
        assertBlobBytesEqual(
            packed,
            versions[0].VersionData,
            'ContentVersion.VersionData'
        );

        member = [
            SELECT
                File_Path__c,
                Destination_Before_Hash__c
            FROM Deployment_Snapshot_Member__c
            WHERE Id = :member.Id
        ];
        System.assert(
            member.File_Path__c == null ||
            !member.File_Path__c.contains('packed-destination-before-bytes'),
            'Artifact bytes must not live on ordinary text fields.'
        );

        ControlPlaneResult bytes =
            DeploymentSnapshotArtifactService.getArtifactBytes(
                'snap-art',
                'ApexClass',
                'AccountService'
            );
        System.assertEquals(true, bytes.success);
        assertBlobBytesEqual(
            packed,
            bytes.artifactBytes,
            'getArtifactBytes.artifactBytes'
        );
    }

    @IsTest
    static void rollbackOperationCreateAndDuplicates() {
        ControlPlaneResult created =
            RollbackOperationService.createOperation(
                operationPayload('op-1', '00D000000000001', 'snap-op')
            );
        System.assertEquals(true, created.success);
        Rollback_Operation__c record =
            (Rollback_Operation__c) created.record;
        System.assertEquals('NOT_STARTED', record.Status__c);
        System.assertEquals(
            '00D000000000001|snap-op',
            record.Rollback_Scope_Key__c
        );
        System.assertEquals(
            '00D000000000001|snap-op',
            record.Active_Scope_Key__c
        );

        ControlPlaneResult dupId =
            RollbackOperationService.createOperation(
                operationPayload('op-1', '00D000000000002', 'snap-other')
            );
        System.assertEquals(false, dupId.success);
        System.assertEquals('DUPLICATE_VALUE', dupId.code);

        String activeScopeDuplicateDml =
            probeActiveScopeDuplicateDml('op-dup-probe', '00D000000000001', 'snap-op');
        ControlPlaneResult dupScope =
            RollbackOperationService.createOperation(
                operationPayload('op-2', '00D000000000001', 'snap-op')
            );
        System.assertEquals(false, dupScope.success);
        System.assertEquals(
            'CONFLICT',
            dupScope.code,
            'Active scope duplicate mapping diagnostic. serviceField=' +
            String.valueOf(dupScope.field) +
            ' serviceMessage=' +
            String.valueOf(dupScope.message) +
            ' dmlProbe=' +
            activeScopeDuplicateDml
        );
        System.assertEquals('Active_Scope_Key__c', dupScope.field);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Rollback_Operation__c WHERE Snapshot_Id__c = 'snap-op']
        );
    }

    @IsTest
    static void rollbackFailedReleasesActiveFenceAndAllowsRetry() {
        RollbackOperationService.createOperation(
            operationPayload('op-fail-a', '00D000000000001', 'snap-retry')
        );
        ControlPlaneResult failed =
            RollbackOperationService.markTerminal(
                'op-fail-a',
                'FAILED',
                'FAILED',
                'capture failed'
            );
        System.assertEquals(true, failed.success);
        Rollback_Operation__c oldRow =
            (Rollback_Operation__c) failed.record;
        System.assertEquals('FAILED', oldRow.Status__c);
        System.assertEquals(null, oldRow.Active_Scope_Key__c);
        System.assertEquals(
            '00D000000000001|snap-retry',
            oldRow.Rollback_Scope_Key__c
        );

        Map<String, Object> retry = operationPayload(
            'op-fail-b',
            '00D000000000001',
            'snap-retry'
        );
        retry.put('retryOfOperationId', 'op-fail-a');
        ControlPlaneResult created =
            RollbackOperationService.createOperation(retry);
        System.assertEquals(true, created.success);
        Rollback_Operation__c nextRow =
            (Rollback_Operation__c) created.record;
        System.assertEquals('op-fail-b', nextRow.Operation_Id__c);
        System.assertEquals('op-fail-a', nextRow.Retry_Of_Operation_Id__c);
        System.assertEquals(
            '00D000000000001|snap-retry',
            nextRow.Active_Scope_Key__c
        );
        Rollback_Operation__c persistedOld = [
            SELECT Active_Scope_Key__c
            FROM Rollback_Operation__c
            WHERE Operation_Id__c = 'op-fail-a'
        ];
        System.assertEquals(null, persistedOld.Active_Scope_Key__c);
    }

    @IsTest
    static void rollbackMultipleFailedRowsAndHistoricalQuery() {
        for (String operationId : new List<String>{
            'op-hist-a',
            'op-hist-b',
            'op-hist-c'
        }) {
            RollbackOperationService.createOperation(
                operationPayload(operationId, '00D000000000001', 'snap-hist')
            );
            ControlPlaneResult failed =
                RollbackOperationService.markTerminal(
                    operationId,
                    'FAILED',
                    'FAILED',
                    'failed'
                );
            System.assertEquals(true, failed.success);
        }

        ControlPlaneResult found =
            RollbackOperationService.findByDestinationAndSnapshot(
                '00D000000000001',
                'snap-hist'
            );
        System.assertEquals(true, found.success);
        System.assertEquals(3, found.records.size());
        Set<String> statuses = new Set<String>();
        for (SObject row : found.records) {
            statuses.add(((Rollback_Operation__c) row).Status__c);
            System.assertEquals(
                null,
                ((Rollback_Operation__c) row).Active_Scope_Key__c
            );
        }
        System.assertEquals(new Set<String>{ 'FAILED' }, statuses);
    }

    @IsTest
    static void rollbackActiveFenceBlocksSucceededUnknownInProgress() {
        assertCreateBlockedAfterStatus(
            'op-succ',
            'snap-succ',
            'SUCCEEDED',
            true
        );
        assertCreateBlockedAfterStatus(
            'op-unk',
            'snap-unk',
            'UNKNOWN_RESULT',
            false
        );
        RollbackOperationService.createOperation(
            operationPayload('op-prog', '00D000000000001', 'snap-prog')
        );
        RollbackOperationService.claimOperation('op-prog');
        ControlPlaneResult blocked =
            RollbackOperationService.createOperation(
                operationPayload('op-prog-2', '00D000000000001', 'snap-prog')
            );
        System.assertEquals(false, blocked.success);
        System.assertEquals('CONFLICT', blocked.code);
        System.assertEquals('Active_Scope_Key__c', blocked.field);
    }

    @IsTest
    static void differentRollbackScopeDoesNotConflict() {
        ControlPlaneResult firstScope =
            RollbackOperationService.createOperation(
                operationPayload('op-scope-a', '00D000000000001', 'snap-a')
            );
        System.assertEquals(true, firstScope.success);

        ControlPlaneResult secondScope =
            RollbackOperationService.createOperation(
                operationPayload('op-scope-b', '00D000000000001', 'snap-b')
            );
        System.assertEquals(true, secondScope.success);
        System.assertNotEquals('CONFLICT', secondScope.code);
    }

    @IsTest
    static void rollbackStateMachineAndUnknownPreserved() {
        RollbackOperationService.createOperation(
            operationPayload('op-state', '00D000000000001', 'snap-state')
        );
        ControlPlaneResult started =
            RollbackOperationService.markExecutionStarted('op-state');
        System.assertEquals(
            'IN_PROGRESS',
            ((Rollback_Operation__c) started.record).Status__c
        );

        ControlPlaneResult failedUpdate =
            RollbackOperationService.updateOperation(
                'op-state',
                new Map<String, Object>{ 'status' => 'FAILED' }
            );
        System.assertEquals(false, failedUpdate.success);
        System.assertEquals('INVALID_STATE', failedUpdate.code);
        System.assertEquals(
            'IN_PROGRESS',
            ((Rollback_Operation__c) RollbackOperationService.getOperation(
                    'op-state'
                )
                .record)
                .Status__c
        );

        ControlPlaneResult unknown =
            RollbackOperationService.markTerminal(
                'op-state',
                'UNKNOWN_RESULT',
                'UNKNOWN',
                'Result could not be confirmed.'
            );
        System.assertEquals(true, unknown.success);
        System.assertEquals(
            'UNKNOWN_RESULT',
            ((Rollback_Operation__c) unknown.record).Status__c
        );
        System.assertEquals(
            '00D000000000001|snap-state',
            ((Rollback_Operation__c) unknown.record).Active_Scope_Key__c
        );

        ControlPlaneResult overwrite =
            RollbackOperationService.markTerminal(
                'op-state',
                'FAILED',
                'FAILED',
                'late failure'
            );
        System.assertEquals(false, overwrite.success);
        System.assertEquals(
            'UNKNOWN_RESULT',
            ((Rollback_Operation__c) RollbackOperationService.getOperation(
                    'op-state'
                )
                .record)
                .Status__c
        );
    }

    @IsTest
    static void destinationLockAcquireContentionAndGeneration() {
        ControlPlaneResult first = DestinationOrgLockService.acquire(
            lockPayload('00D000000000001', 'replica-a', 'DEPLOY')
        );
        System.assertEquals(true, first.success);
        System.assertEquals(1, first.leaseGeneration);

        ControlPlaneResult contention = DestinationOrgLockService.acquire(
            lockPayload('00D000000000001', 'replica-b', 'ROLLBACK')
        );
        System.assertEquals(false, contention.success);
        System.assertEquals('CONFLICT', contention.code);
        System.assertEquals(1, contention.leaseGeneration);

        ControlPlaneResult otherOrg = DestinationOrgLockService.acquire(
            lockPayload('00D000000000002', 'replica-b', 'DEPLOY')
        );
        System.assertEquals(true, otherOrg.success);

        ControlPlaneResult renewed = DestinationOrgLockService.renew(
            new Map<String, Object>{
                'destinationOrgId' => '00D000000000001',
                'ownerId' => 'replica-a',
                'leaseGeneration' => 1
            }
        );
        System.assertEquals(true, renewed.success);

        ControlPlaneResult released = DestinationOrgLockService.release(
            new Map<String, Object>{
                'destinationOrgId' => '00D000000000001',
                'ownerId' => 'replica-a',
                'leaseGeneration' => 1
            }
        );
        System.assertEquals(true, released.success);
        System.assertEquals(
            'RELEASED',
            ((Destination_Org_Lock__c) released.record).Status__c
        );

        ControlPlaneResult reacquired = DestinationOrgLockService.acquire(
            lockPayload('00D000000000001', 'replica-c', 'ROLLBACK')
        );
        System.assertEquals(true, reacquired.success);
        System.assertEquals(2, reacquired.leaseGeneration);

        ControlPlaneResult admin =
            DestinationOrgLockService.adminRelease('00D000000000001');
        System.assertEquals(true, admin.success);
        System.assertEquals(
            'RELEASED',
            ((Destination_Org_Lock__c) admin.record).Status__c
        );
        System.assertEquals(3, admin.leaseGeneration);
    }

    @IsTest
    static void sanitizeRejectsTokensAndApiRejectsCredentialBody() {
        Map<String, Object> dirty = new Map<String, Object>{
            'snapshotId' => 'snap-safe',
            'refreshToken' => 'secret-token',
            'destinationOrgId' => '00D000000000001'
        };
        Map<String, Object> clean = ControlPlaneSanitize.sanitize(dirty);
        System.assertEquals(false, clean.containsKey('refreshToken'));
        System.assertEquals(true, ControlPlaneSanitize.containsForbiddenKey(dirty));

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/control-plane/snapshots';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(dirty));
        RestContext.request = req;
        RestContext.response = res;

        ControlPlaneApi.handlePost();
        System.assertEquals(400, res.statusCode);
        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(
                res.responseBody.toString()
            );
        System.assertEquals(false, body.get('success'));
        System.assertEquals(0, [SELECT COUNT() FROM Deployment_Snapshot__c]);
    }

    @IsTest
    static void controlPlaneApiSnapshotAndLockRoutes() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/control-plane/snapshots';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            JSON.serialize(snapshotPayload('snap-api'))
        );
        RestContext.request = req;
        RestContext.response = res;
        ControlPlaneApi.handlePost();
        System.assertEquals(200, res.statusCode);

        req = new RestRequest();
        res = new RestResponse();
        req.requestUri = '/services/apexrest/control-plane/locks/acquire';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            JSON.serialize(
                lockPayload('00D000000000009', 'replica-api', 'DEPLOY')
            )
        );
        RestContext.request = req;
        RestContext.response = res;
        ControlPlaneApi.handlePost();
        System.assertEquals(200, res.statusCode);

        req = new RestRequest();
        res = new RestResponse();
        req.requestUri = '/services/apexrest/control-plane/locks/admin-release';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"destinationOrgId":"00D000000000009"}'
        );
        RestContext.request = req;
        RestContext.response = res;
        ControlPlaneApi.handlePost();
        Map<String, Object> denied =
            (Map<String, Object>) JSON.deserializeUntyped(
                res.responseBody.toString()
            );
        System.assertEquals(false, denied.get('success'));
    }

    @IsTest
    static void unauthorizedUserCannotCreateSnapshot() {
        Profile profile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        User u = new User(
            Alias = 'cpdeny',
            Email = 'cpdeny@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Deny',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'cpdeny' + DateTime.now().getTime() + '@example.com',
            ProfileId = profile.Id
        );
        insert u;

        System.runAs(u) {
            ControlPlaneResult result =
                DeploymentSnapshotService.createSnapshot(
                    snapshotPayload('snap-deny')
                );
            System.assertEquals(false, result.success);
            System.assertEquals('UNAUTHORIZED', result.code);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Deployment_Snapshot__c]);
    }

    @IsTest
    static void claimAndFindByDestinationAndSnapshot() {
        RollbackOperationService.createOperation(
            operationPayload('op-find', '00D000000000001', 'snap-find')
        );
        ControlPlaneResult found =
            RollbackOperationService.findByDestinationAndSnapshot(
                '00D000000000001',
                'snap-find'
            );
        System.assertEquals(true, found.success);
        System.assertEquals(1, found.records.size());
        System.assertEquals(
            'op-find',
            ((Rollback_Operation__c) found.records[0]).Operation_Id__c
        );
        ControlPlaneResult claimed =
            RollbackOperationService.claimOperation('op-find');
        System.assertEquals(
            'IN_PROGRESS',
            ((Rollback_Operation__c) claimed.record).Status__c
        );
        ControlPlaneResult claimedAgain =
            RollbackOperationService.claimOperation('op-find');
        System.assertEquals(false, claimedAgain.success);
        System.assertEquals('CONFLICT', claimedAgain.code);
    }

    @IsTest
    static void artifactRestRoundTripPreservesBytes() {
        DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-bin'));
        String artifactId =
            'snapshots/snap-bin/destination-before/ApexClass/AccountService';
        Blob packed = EncodingUtil.convertFromHex('0001FF0A0D0A');

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri =
            '/services/apexrest/control-plane/snapshots/snap-bin/artifacts';
        req.httpMethod = 'POST';
        req.params.put('artifactId', artifactId);
        req.requestBody = packed;
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ControlPlaneApi.handlePost();
        Test.stopTest();

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(
                res.responseBody.toString()
            );
        System.assertEquals(200, res.statusCode);
        System.assertEquals(true, body.get('success'));
        System.assertEquals(artifactId, body.get('artifactId'));
        System.assertNotEquals(null, body.get('contentDocumentId'));

        RestRequest getReq = new RestRequest();
        RestResponse getRes = new RestResponse();
        getReq.requestUri =
            '/services/apexrest/control-plane/snapshots/snap-bin/artifacts/' +
            EncodingUtil.urlEncode(artifactId, 'UTF-8');
        getReq.httpMethod = 'GET';
        RestContext.request = getReq;
        RestContext.response = getRes;
        ControlPlaneApi.handleGet();

        System.assertEquals(200, getRes.statusCode);
        assertBlobBytesEqual(
            packed,
            getRes.responseBody,
            'REST GET responseBody'
        );
    }

    @IsTest
    static void artifactRestCrossSnapshotRejected() {
        DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-a'));
        DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-b'));
        String artifactId =
            'snapshots/snap-a/destination-before/ApexClass/AccountService';
        ControlPlaneResult stored =
            DeploymentSnapshotArtifactService.storeArtifactById(
                'snap-a',
                artifactId,
                Blob.valueOf('owned-by-a')
            );
        System.assertEquals(true, stored.success);

        ControlPlaneResult crossed =
            DeploymentSnapshotArtifactService.getArtifactBytesById(
                'snap-b',
                artifactId
            );
        System.assertEquals(false, crossed.success);
        System.assertEquals('NOT_FOUND', crossed.code);

        ControlPlaneResult existsOther =
            DeploymentSnapshotArtifactService.existsArtifactById(
                'snap-b',
                artifactId
            );
        System.assertEquals(false, existsOther.success);
        System.assertEquals('NOT_FOUND', existsOther.code);
    }

    @IsTest
    static void artifactRestSealedOverwriteRejected() {
        DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-seal-art'));
        String artifactId =
            'snapshots/snap-seal-art/destination-before/ApexClass/AccountService';
        ControlPlaneResult stored =
            DeploymentSnapshotArtifactService.storeArtifactById(
                'snap-seal-art',
                artifactId,
                Blob.valueOf('before-seal')
            );
        System.assertEquals(true, stored.success);
        DeploymentSnapshotService.sealSnapshot('snap-seal-art');

        ControlPlaneResult overwrite =
            DeploymentSnapshotArtifactService.storeArtifactById(
                'snap-seal-art',
                artifactId,
                Blob.valueOf('after-seal')
            );
        System.assertEquals(false, overwrite.success);
        System.assertEquals('SEALED', overwrite.code);
    }

    @IsTest
    static void artifactIdLengthPersistsOrFailsClosed() {
        DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-len'));
        System.assertEquals(
            true,
            storeNamedArtifact('Name80', repeatChar('a', 80)).success
        );
        System.assertEquals(
            true,
            storeNamedArtifact('Name81', repeatChar('b', 81)).success
        );
        System.assertEquals(
            true,
            storeNamedArtifact('Name255', repeatChar('c', 255)).success
        );
        ControlPlaneResult tooLong =
            storeNamedArtifact('Name256', repeatChar('d', 256));
        System.assertEquals(false, tooLong.success);
        System.assertEquals('INVALID_REQUEST', tooLong.code);

        Map<String, Deployment_Snapshot_Member__c> stored = new Map<String, Deployment_Snapshot_Member__c>();
        for (Deployment_Snapshot_Member__c row : [
            SELECT Metadata_Name__c, Artifact_Id__c
            FROM Deployment_Snapshot_Member__c
            WHERE Metadata_Name__c IN ('Name80', 'Name81', 'Name255', 'Name256')
        ]) {
            stored.put(row.Metadata_Name__c, row);
        }
        System.assertEquals(80, stored.get('Name80').Artifact_Id__c.length());
        System.assertEquals(81, stored.get('Name81').Artifact_Id__c.length());
        System.assertEquals(255, stored.get('Name255').Artifact_Id__c.length());
        System.assertEquals(null, stored.get('Name256').Artifact_Id__c);
    }

    @IsTest
    static void artifactRestPathTraversalRejected() {
        DeploymentSnapshotService.createSnapshot(snapshotPayload('snap-path'));
        ControlPlaneResult traversal =
            DeploymentSnapshotArtifactService.storeArtifactById(
                'snap-path',
                'snapshots/../secrets/destination-before/ApexClass/A',
                Blob.valueOf('nope')
            );
        System.assertEquals(false, traversal.success);
        System.assertEquals('INVALID_REQUEST', traversal.code);
    }

    private static void assertBlobBytesEqual(
        Blob expected,
        Blob actual,
        String label
    ) {
        System.assertEquals(
            EncodingUtil.convertToHex(expected),
            EncodingUtil.convertToHex(actual),
            label + ' byte content must match.'
        );
    }

    private static String probeActiveScopeDuplicateDml(
        String operationId,
        String destinationOrgId,
        String snapshotId
    ) {
        String scopeKey = destinationOrgId + '|' + snapshotId;
        Rollback_Operation__c probe = new Rollback_Operation__c();
        probe.Operation_Id__c = operationId;
        probe.Destination_Org_Id__c = destinationOrgId;
        probe.Snapshot_Id__c = snapshotId;
        probe.Rollback_Scope_Key__c = scopeKey;
        probe.Active_Scope_Key__c = scopeKey;
        probe.Status__c = 'NOT_STARTED';
        probe.Created_At__c = Datetime.now();
        probe.Updated_At__c = probe.Created_At__c;
        try {
            insert probe;
            return 'unexpected insert success';
        } catch (DmlException e) {
            String diagnostic = 'dmlType=' +
                (e.getNumDml() > 0 ? String.valueOf(e.getDmlType(0)) : 'n/a');
            diagnostic += '; dmlFields=' +
                (e.getNumDml() > 0 ? String.valueOf(e.getDmlFields(0)) : 'n/a');
            diagnostic += '; dmlMessage=' +
                (e.getNumDml() > 0 ? String.valueOf(e.getDmlMessage(0)) : 'n/a');
            diagnostic += '; exceptionMessage=' + String.valueOf(e.getMessage());
            if (e.getNumDml() > 0) {
                List<Schema.SObjectField> dmlFields = e.getDmlFields(0);
                if (dmlFields != null && !dmlFields.isEmpty()) {
                    diagnostic += '; field0=' +
                        dmlFields[0].getDescribe().getName();
                }
            }
            return diagnostic;
        }
    }

    private static void assertCreateBlockedAfterStatus(
        String operationId,
        String snapshotId,
        String status,
        Boolean claimFirst
    ) {
        RollbackOperationService.createOperation(
            operationPayload(operationId, '00D000000000001', snapshotId)
        );
        if (claimFirst) {
            ControlPlaneResult claimed =
                RollbackOperationService.claimOperation(operationId);
            System.assertEquals(
                true,
                claimed.success,
                'claimOperation failed: code=' +
                String.valueOf(claimed.code) +
                ' message=' +
                String.valueOf(claimed.message) +
                ' field=' +
                String.valueOf(claimed.field)
            );
        }
        ControlPlaneResult terminal =
            RollbackOperationService.markTerminal(
                operationId,
                status,
                status,
                status
            );
        System.assertEquals(
            true,
            terminal.success,
            'markTerminal failed: code=' +
            String.valueOf(terminal.code) +
            ' message=' +
            String.valueOf(terminal.message) +
            ' field=' +
            String.valueOf(terminal.field)
        );
        ControlPlaneResult blocked =
            RollbackOperationService.createOperation(
                operationPayload(operationId + '-2', '00D000000000001', snapshotId)
            );
        System.assertEquals(false, blocked.success);
        System.assertEquals('CONFLICT', blocked.code);
        System.assertEquals('Active_Scope_Key__c', blocked.field);
    }

    private static ControlPlaneResult storeNamedArtifact(
        String name,
        String artifactId
    ) {
        DeploymentSnapshotService.addMember(
            'snap-len',
            memberPayload('ApexClass', name)
        );
        return DeploymentSnapshotArtifactService.storeArtifact(
            'snap-len',
            'ApexClass',
            name,
            artifactId,
            Blob.valueOf('bytes')
        );
    }

    private static String repeatChar(String value, Integer count) {
        List<String> parts = new List<String>();
        for (Integer i = 0; i < count; i++) {
            parts.add(value);
        }
        return String.join(parts, '');
    }

    private static Map<String, Object> snapshotPayload(String snapshotId) {
        return new Map<String, Object>{
            'snapshotId' => snapshotId,
            'deploymentId' => 'dep-1',
            'sourceOrgId' => '00D000000000099',
            'destinationOrgId' => '00D000000000001',
            'sourceBranch' => 'feature/a',
            'destinationBranch' => 'uat',
            'schemaVersion' => '1',
            'snapshotVersion' => '1',
            'rollbackEligible' => true
        };
    }

    private static Map<String, Object> memberPayload(
        String metadataType,
        String metadataName
    ) {
        return new Map<String, Object>{
            'metadataType' => metadataType,
            'metadataName' => metadataName,
            'filePath' => 'force-app/main/default/classes/' + metadataName + '.cls',
            'changeClass' => 'MODIFIED',
            'existedBefore' => true,
            'destinationBeforeHash' => 'aa',
            'expectedAfterHash' => 'bb',
            'captureStatus' => 'CAPTURED'
        };
    }

    private static Map<String, Object> operationPayload(
        String operationId,
        String destinationOrgId,
        String snapshotId
    ) {
        return new Map<String, Object>{
            'operationId' => operationId,
            'destinationOrgId' => destinationOrgId,
            'snapshotId' => snapshotId
        };
    }

    private static Map<String, Object> lockPayload(
        String destinationOrgId,
        String ownerId,
        String operationType
    ) {
        return new Map<String, Object>{
            'destinationOrgId' => destinationOrgId,
            'ownerId' => ownerId,
            'operationType' => operationType
        };
    }
}