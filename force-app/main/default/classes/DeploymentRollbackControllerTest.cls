@IsTest
private class DeploymentRollbackControllerTest {
    /*
     * Empty artifact bytes (DeploymentRollbackController.buildArtifactsMap):
     * ContentVersion requires non-empty VersionData at insert time.
     * DeploymentSnapshotArtifactService.storeArtifactById also rejects
     * null/empty blobs before persistence. Therefore the controller's
     * defensive null/zero-byte branch cannot be exercised through the
     * supported Salesforce integration path in this test class. That branch
     * remains an intentional production guard and is not covered here.
     */

    private class RollbackCalloutMock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        String capturedBody;
        String capturedEndpoint;
        Integer callCount = 0;

        RollbackCalloutMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            callCount++;
            capturedBody = req.getBody();
            capturedEndpoint = req.getEndpoint();

            System.assert(
                req.getEndpoint().contains('/api/deployment/rollback'),
                'Expected rollback endpoint.'
            );
            System.assertEquals('POST', req.getMethod());

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody(body);
            res.setStatus(statusCode == 200 ? 'OK' : 'Error');
            return res;
        }
    }

    @IsTest
    static void missingSnapshotIdReturnsFailure() {
        RollbackCalloutMock mock = new RollbackCalloutMock(200, '{"success":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            null,
            'history-1',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals('snapshotId is required.', parsed.get('error'));
        System.assertEquals(0, mock.callCount);
    }

    @IsTest
    static void snapshotNotFoundReturnsFailure() {
        RollbackCalloutMock mock = new RollbackCalloutMock(200, '{"success":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            'snap-missing',
            'history-1',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals('Snapshot not found.', parsed.get('error'));
        System.assertEquals(0, mock.callCount);
    }

    @IsTest
    static void snapshotNotSealedReturnsFailure() {
        createSealedSnapshot('snap-open', true, false);

        RollbackCalloutMock mock = new RollbackCalloutMock(200, '{"success":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            'snap-open',
            'history-open',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals(
            'Snapshot is not eligible for rollback.',
            parsed.get('error')
        );
        System.assertEquals(0, mock.callCount);
    }

    @IsTest
    static void snapshotSealedButNotRollbackEligibleReturnsFailure() {
        createSealedSnapshot('snap-ineligible', false, true);

        RollbackCalloutMock mock = new RollbackCalloutMock(200, '{"success":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            'snap-ineligible',
            'history-ineligible',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals(
            'Snapshot is not eligible for rollback.',
            parsed.get('error')
        );
        System.assertEquals(0, mock.callCount);
    }

    @IsTest
    static void historyMismatchReturnsFailure() {
        createSealedSnapshotWithArtifact(
            'snap-history-mismatch',
            true,
            memberPayload('snap-history-mismatch', 'ApexClass', 'AccountService'),
            Blob.valueOf('artifact-bytes')
        );

        Deployment_History__c history = new Deployment_History__c(
            Backend_History_Id__c = 'history-correlated',
            Snapshot_Id__c = 'snap-history-mismatch'
        );
        insert history;

        RollbackCalloutMock mock = new RollbackCalloutMock(200, '{"success":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            'snap-history-mismatch',
            'history-other',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals(
            'historyId does not match the selected snapshot.',
            parsed.get('error')
        );
        System.assertEquals(0, mock.callCount);
    }

    @IsTest
    static void successfulRollbackRequest() {
        Blob artifactBytes = Blob.valueOf('rollback-artifact');
        createSealedSnapshotWithArtifact(
            'snap-rollback',
            true,
            memberPayload('snap-rollback', 'ApexClass', 'AccountService'),
            artifactBytes
        );

        RollbackCalloutMock mock = new RollbackCalloutMock(
            200,
            JSON.serialize(
                new Map<String, Object>{
                    'success' => true,
                    'status' => 'ACCEPTED'
                }
            )
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            'snap-rollback',
            'history-rollback',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(true, parsed.get('success'));
        System.assertEquals('ACCEPTED', parsed.get('status'));
        System.assertEquals(1, mock.callCount);
    }

    @IsTest
    static void backendHttpErrorReturnsStructuredFailure() {
        createSealedSnapshot('snap-http-error', true, true);

        RollbackCalloutMock mock = new RollbackCalloutMock(500, '');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            'snap-http-error',
            'history-http-error',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals(500, parsed.get('statusCode'));
        System.assertNotEquals(null, parsed.get('error'));
        System.assertEquals(1, mock.callCount);
    }

    @IsTest
    static void modifiedMemberLoadsContentVersionBytes() {
        Blob artifactBytes = Blob.valueOf('packed-destination-before');
        String snapshotId = 'snap-load-bytes';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'DemoModifiedClass');

        createSealedSnapshotWithArtifact(
            snapshotId,
            true,
            memberPayload(snapshotId, 'ApexClass', 'DemoModifiedClass'),
            artifactBytes
        );

        RollbackCalloutMock mock = new RollbackCalloutMock(
            200,
            JSON.serialize(new Map<String, Object>{ 'success' => true })
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        DeploymentRollbackController.executeRollback(
            snapshotId,
            'history-load-bytes',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assert(request.containsKey('artifacts'));

        Map<String, Object> artifacts =
            (Map<String, Object>) request.get('artifacts');
        System.assert(artifacts.containsKey(artifactId));

        Map<String, Object> artifactEntry =
            (Map<String, Object>) artifacts.get(artifactId);
        Blob decoded = EncodingUtil.base64Decode(
            (String) artifactEntry.get('contentBase64')
        );
        System.assertEquals(artifactBytes, decoded);
        System.assertEquals(artifactBytes.size(), artifactEntry.get('size'));
    }

    @IsTest
    static void calloutPayloadContainsExpectedFields() {
        Blob artifactBytes = Blob.valueOf('abcd');
        String snapshotId = 'snap-payload';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'AccountService');

        createSealedSnapshotWithArtifact(
            snapshotId,
            true,
            memberPayload(snapshotId, 'ApexClass', 'AccountService'),
            artifactBytes
        );

        RollbackCalloutMock mock = new RollbackCalloutMock(
            200,
            JSON.serialize(new Map<String, Object>{ 'success' => true })
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        DeploymentRollbackController.executeRollback(
            snapshotId,
            'history-payload',
            'refresh-token-value',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);

        System.assertEquals(snapshotId, request.get('snapshotId'));
        System.assertEquals('history-payload', request.get('historyId'));
        System.assertEquals('refresh-token-value', request.get('refreshToken'));
        System.assertEquals(
            'https://example.my.salesforce.com',
            request.get('instanceUrl')
        );
        System.assertEquals('00D000000000001', request.get('orgId'));
        System.assert(request.containsKey('snapshotExport'));
        System.assert(request.containsKey('artifacts'));

        Map<String, Object> snapshotExport =
            (Map<String, Object>) request.get('snapshotExport');
        System.assertEquals(snapshotId, snapshotExport.get('snapshotId'));
        System.assertEquals('SEALED', snapshotExport.get('status'));
        System.assertEquals(true, snapshotExport.get('rollbackEligible'));
        System.assert(snapshotExport.containsKey('overallIntegrityHash'));
        System.assert(snapshotExport.containsKey('memberCount'));
        System.assert(snapshotExport.containsKey('members'));

        List<Object> members = (List<Object>) snapshotExport.get('members');
        System.assertEquals(1, members.size());

        Map<String, Object> member =
            (Map<String, Object>) members[0];
        System.assertEquals('ApexClass', member.get('metadataType'));
        System.assertEquals('AccountService', member.get('metadataName'));
        System.assertEquals(artifactId, member.get('artifactId'));
        System.assert(member.containsKey('destinationBeforeHash'));
        System.assertEquals(false, member.containsKey('contentBase64'));

        Map<String, Object> artifacts =
            (Map<String, Object>) request.get('artifacts');
        System.assertEquals(1, artifacts.size());
        System.assert(artifacts.containsKey(artifactId));
        String contentDocumentId = (String) member.get('contentDocumentId');
        System.assertNotEquals(null, contentDocumentId);
        System.assertEquals(false, artifacts.containsKey(contentDocumentId));

        System.assertEquals(false, request.containsKey('clientSecret'));
        System.assertEquals(false, mock.capturedBody.contains('clientSecret'));
    }

    @IsTest
    static void multipleModifiedMembersCreateMultipleArtifactEntries() {
        String snapshotId = 'snap-multi';
        Blob firstBytes = Blob.valueOf('first');
        Blob secondBytes = Blob.valueOf('second-member');

        createSnapshotBase(snapshotId, true, 2);
        DeploymentSnapshotService.addMember(
            snapshotId,
            memberPayload(snapshotId, 'ApexClass', 'FirstClass')
        );
        DeploymentSnapshotService.addMember(
            snapshotId,
            memberPayload(snapshotId, 'ApexClass', 'SecondClass')
        );
        storeArtifact(
            snapshotId,
            'ApexClass',
            'FirstClass',
            firstBytes
        );
        storeArtifact(
            snapshotId,
            'ApexClass',
            'SecondClass',
            secondBytes
        );
        DeploymentSnapshotService.sealSnapshot(snapshotId);

        RollbackCalloutMock mock = new RollbackCalloutMock(
            200,
            JSON.serialize(new Map<String, Object>{ 'success' => true })
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        DeploymentRollbackController.executeRollback(
            snapshotId,
            'history-multi',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        Map<String, Object> artifacts =
            (Map<String, Object>) request.get('artifacts');
        System.assertEquals(2, artifacts.size());
        System.assert(
            artifacts.containsKey(
                artifactIdFor(snapshotId, 'ApexClass', 'FirstClass')
            )
        );
        System.assert(
            artifacts.containsKey(
                artifactIdFor(snapshotId, 'ApexClass', 'SecondClass')
            )
        );
    }

    @IsTest
    static void blankArtifactIdFailsBeforeCallout() {
        Map<String, Object> member = memberPayload(
            'snap-no-artifact-id',
            'ApexClass',
            'AccountService'
        );
        member.remove('artifactId');
        createSealedSnapshot('snap-no-artifact-id', true, true, member);

        RollbackCalloutMock mock = new RollbackCalloutMock(200, '{"success":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            'snap-no-artifact-id',
            'history-no-artifact-id',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assert(
            ((String) parsed.get('error')).contains('Artifact Id is required.')
        );
        System.assertEquals(0, mock.callCount);
    }

    @IsTest
    static void blankContentDocumentIdFailsBeforeCallout() {
        createSealedSnapshot(
            'snap-no-content-doc',
            true,
            true,
            memberPayload('snap-no-content-doc', 'ApexClass', 'AccountService')
        );

        RollbackCalloutMock mock = new RollbackCalloutMock(200, '{"success":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            'snap-no-content-doc',
            'history-no-content-doc',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assert(
            ((String) parsed.get('error')).contains(
                'Artifact file is not associated.'
            )
        );
        System.assertEquals(0, mock.callCount);
    }

    @IsTest
    static void missingContentVersionFailsBeforeCallout() {
        String snapshotId = 'snap-missing-cv';
        createSealedSnapshot(
            snapshotId,
            true,
            true,
            memberWithStoredArtifactMetadata(
                snapshotId,
                'ApexClass',
                'AccountService',
                '069000000000001AAA'
            )
        );

        RollbackCalloutMock mock = new RollbackCalloutMock(200, '{"success":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            snapshotId,
            'history-missing-cv',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assert(
            ((String) parsed.get('error')).contains(
                'Artifact file is not associated.'
            )
        );
        System.assertEquals(0, mock.callCount);
    }

    @IsTest
    static void artifactSizeMismatchFailsBeforeCallout() {
        String snapshotId = 'snap-size-mismatch';
        Blob artifactBytes = Blob.valueOf('12345');

        createSnapshotBase(snapshotId, true, 1);
        DeploymentSnapshotService.addMember(
            snapshotId,
            memberPayload(snapshotId, 'ApexClass', 'AccountService')
        );
        storeArtifact(snapshotId, 'ApexClass', 'AccountService', artifactBytes);

        Deployment_Snapshot_Member__c member = [
            SELECT Id
            FROM Deployment_Snapshot_Member__c
            WHERE Member_Key__c = :DeploymentSnapshotService.buildMemberKey(
                snapshotId,
                'ApexClass',
                'AccountService'
            )
            LIMIT 1
        ];
        member.Artifact_Size__c = 99;
        update member;

        DeploymentSnapshotService.sealSnapshot(snapshotId);

        RollbackCalloutMock mock = new RollbackCalloutMock(200, '{"success":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            snapshotId,
            'history-size-mismatch',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assert(
            ((String) parsed.get('error')).contains(
                'Artifact size does not match snapshot member metadata.'
            )
        );
        System.assertEquals(0, mock.callCount);
    }

    @IsTest
    static void duplicateArtifactIdFailsBeforeCallout() {
        String snapshotId = 'snap-dup-artifact';
        String artifactId = artifactIdFor(snapshotId, 'ApexClass', 'SharedClass');
        Blob artifactBytes = Blob.valueOf('shared');

        createSnapshotBase(snapshotId, true, 2);
        Map<String, Object> firstMember = memberPayload(
            snapshotId,
            'ApexClass',
            'FirstClass'
        );
        firstMember.put('artifactId', artifactId);
        Map<String, Object> secondMember = memberPayload(
            snapshotId,
            'ApexClass',
            'SecondClass'
        );
        secondMember.put('artifactId', artifactId);

        DeploymentSnapshotService.addMember(snapshotId, firstMember);
        DeploymentSnapshotService.addMember(snapshotId, secondMember);

        ControlPlaneResult stored =
            DeploymentSnapshotArtifactService.storeArtifactById(
                snapshotId,
                artifactId,
                artifactBytes
            );
        System.assertEquals(true, stored.success, stored.message);
        wireMembersToSharedArtifact(
            snapshotId,
            new List<String>{ 'FirstClass', 'SecondClass' },
            artifactId,
            stored.contentDocumentId,
            stored.artifactSize
        );

        DeploymentSnapshotService.sealSnapshot(snapshotId);

        RollbackCalloutMock mock = new RollbackCalloutMock(200, '{"success":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = DeploymentRollbackController.executeRollback(
            snapshotId,
            'history-dup-artifact',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        System.assertEquals(
            'Duplicate artifact Id found in snapshot members.',
            parsed.get('error')
        );
        System.assertEquals(0, mock.callCount);
    }

    @IsTest
    static void newAndUnknownMembersSkipArtifactLoading() {
        String snapshotId = 'snap-mixed';
        Blob artifactBytes = Blob.valueOf('modified-only');

        createSnapshotBase(snapshotId, true, 3);
        DeploymentSnapshotService.addMember(
            snapshotId,
            memberPayload(snapshotId, 'ApexClass', 'ModifiedClass')
        );
        DeploymentSnapshotService.addMember(
            snapshotId,
            newMemberPayload(snapshotId, 'ApexClass', 'NewClass', 'NEW')
        );
        DeploymentSnapshotService.addMember(
            snapshotId,
            newMemberPayload(snapshotId, 'ApexClass', 'UnknownClass', 'UNKNOWN')
        );
        storeArtifact(
            snapshotId,
            'ApexClass',
            'ModifiedClass',
            artifactBytes
        );
        DeploymentSnapshotService.sealSnapshot(snapshotId);

        RollbackCalloutMock mock = new RollbackCalloutMock(
            200,
            JSON.serialize(new Map<String, Object>{ 'success' => true })
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        DeploymentRollbackController.executeRollback(
            snapshotId,
            'history-mixed',
            'refresh-token',
            'https://example.my.salesforce.com',
            '00D000000000001'
        );
        Test.stopTest();

        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        Map<String, Object> artifacts =
            (Map<String, Object>) request.get('artifacts');
        System.assertEquals(1, artifacts.size());

        Map<String, Object> snapshotExport =
            (Map<String, Object>) request.get('snapshotExport');
        List<Object> members = (List<Object>) snapshotExport.get('members');
        System.assertEquals(3, members.size());
    }

    private static void createSealedSnapshot(
        String snapshotId,
        Boolean rollbackEligible,
        Boolean seal
    ) {
        createSealedSnapshot(snapshotId, rollbackEligible, seal, null);
    }

    private static void createSealedSnapshot(
        String snapshotId,
        Boolean rollbackEligible,
        Boolean seal,
        Map<String, Object> member
    ) {
        createSnapshotBase(
            snapshotId,
            rollbackEligible,
            member == null ? 0 : 1
        );

        if (member != null) {
            DeploymentSnapshotService.addMember(snapshotId, member);
        }

        if (seal) {
            DeploymentSnapshotService.sealSnapshot(snapshotId);
        }
    }

    private static void createSealedSnapshotWithArtifact(
        String snapshotId,
        Boolean rollbackEligible,
        Map<String, Object> member,
        Blob artifactBytes
    ) {
        createSnapshotBase(snapshotId, rollbackEligible, 1);
        DeploymentSnapshotService.addMember(snapshotId, member);
        storeArtifact(
            snapshotId,
            (String) member.get('metadataType'),
            (String) member.get('metadataName'),
            artifactBytes
        );
        DeploymentSnapshotService.sealSnapshot(snapshotId);
    }

    private static void createSnapshotBase(
        String snapshotId,
        Boolean rollbackEligible,
        Integer memberCount
    ) {
        DeploymentSnapshotService.createSnapshot(
            new Map<String, Object>{
                'snapshotId' => snapshotId,
                'deploymentId' => 'history-' + snapshotId,
                'sourceOrgId' => '00D000000000099',
                'destinationOrgId' => '00D000000000001',
                'sourceBranch' => 'feature/a',
                'destinationBranch' => 'uat',
                'schemaVersion' => '1',
                'snapshotVersion' => '1',
                'rollbackEligible' => rollbackEligible,
                'overallIntegrityHash' => 'overall-hash-' + snapshotId,
                'memberCount' => memberCount
            }
        );
    }

    private static void storeArtifact(
        String snapshotId,
        String metadataType,
        String metadataName,
        Blob artifactBytes
    ) {
        ControlPlaneResult stored = DeploymentSnapshotArtifactService.storeArtifactById(
            snapshotId,
            artifactIdFor(snapshotId, metadataType, metadataName),
            artifactBytes
        );
        System.assertEquals(true, stored.success, stored.message);
    }

    private static void wireMembersToSharedArtifact(
        String snapshotId,
        List<String> metadataNames,
        String sharedArtifactId,
        Id contentDocumentId,
        Decimal artifactSize
    ) {
        Deployment_Snapshot__c snapshot = [
            SELECT Id
            FROM Deployment_Snapshot__c
            WHERE Snapshot_Id__c = :snapshotId
            LIMIT 1
        ];
        List<Deployment_Snapshot_Member__c> members = [
            SELECT Id, Metadata_Name__c
            FROM Deployment_Snapshot_Member__c
            WHERE Deployment_Snapshot__c = :snapshot.Id
            AND Metadata_Name__c IN :metadataNames
        ];
        System.assertEquals(
            metadataNames.size(),
            members.size(),
            'Expected all shared-artifact members to exist.'
        );
        for (Deployment_Snapshot_Member__c member : members) {
            member.Artifact_Id__c = sharedArtifactId;
            member.Content_Document_Id__c = contentDocumentId;
            member.Artifact_Size__c = artifactSize;
        }
        update members;
    }

    private static Map<String, Object> memberWithStoredArtifactMetadata(
        String snapshotId,
        String metadataType,
        String metadataName,
        String contentDocumentId
    ) {
        Map<String, Object> member = memberPayload(
            snapshotId,
            metadataType,
            metadataName
        );
        member.put('contentDocumentId', contentDocumentId);
        member.put('artifactSize', 4);
        return member;
    }

    private static Map<String, Object> memberPayload(
        String snapshotId,
        String metadataType,
        String metadataName
    ) {
        return new Map<String, Object>{
            'metadataType' => metadataType,
            'metadataName' => metadataName,
            'filePath' =>
                'force-app/main/default/classes/' + metadataName + '.cls',
            'changeClass' => 'MODIFIED',
            'existedBefore' => true,
            'destinationBeforeHash' => 'aa',
            'expectedAfterHash' => 'bb',
            'artifactId' => artifactIdFor(snapshotId, metadataType, metadataName),
            'captureStatus' => 'CAPTURED'
        };
    }

    private static Map<String, Object> newMemberPayload(
        String snapshotId,
        String metadataType,
        String metadataName,
        String changeClass
    ) {
        return new Map<String, Object>{
            'metadataType' => metadataType,
            'metadataName' => metadataName,
            'filePath' =>
                'force-app/main/default/classes/' + metadataName + '.cls',
            'changeClass' => changeClass,
            'existedBefore' => false,
            'captureStatus' => 'NOT_REQUIRED'
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
}