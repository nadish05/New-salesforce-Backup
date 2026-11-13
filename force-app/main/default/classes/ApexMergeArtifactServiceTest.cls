/**
 * Unit tests for ApexMergeArtifactService — Salesforce Files persistence only.
 */
@IsTest
private class ApexMergeArtifactServiceTest {

    private static final String MANIFEST_ID = 'mfm_test_001';
    private static final String ARTIFACT_ID_CLS =
        'merge/mfm_test_001/classes/Foo/ApexClass/cls';
    private static final String ARTIFACT_ID_META =
        'merge/mfm_test_001/classes/Foo/ApexClass/metaXml';

    @IsTest
    static void persist_cls_success() {
        Id planId = seedDeploymentPlan();
        Blob bytes = Blob.valueOf('public with sharing class Foo {}');
        ApexMergeArtifactService.PersistRequest request = buildRequest(
            planId,
            ARTIFACT_ID_CLS,
            'Foo',
            ApexMergeArtifactService.ROLE_CLS,
            bytes
        );

        Test.startTest();
        ApexMergeArtifactService.PersistResult result =
            ApexMergeArtifactService.persistArtifact(request);
        Test.stopTest();

        assertSuccessResult(result, request, false);
        assertStoredFile(
            planId,
            request,
            bytes,
            'Foo.cls',
            'apex-merge-artifact|'
        );
    }

    @IsTest
    static void persist_metaXml_success() {
        Id planId = seedDeploymentPlan();
        Blob bytes = Blob.valueOf(
            '<?xml version="1.0"?><ApexClass xmlns="http://soap.sforce.com/2006/04/metadata"/>'
        );
        ApexMergeArtifactService.PersistRequest request = buildRequest(
            planId,
            ARTIFACT_ID_META,
            'Foo',
            ApexMergeArtifactService.ROLE_META_XML,
            bytes
        );

        Test.startTest();
        ApexMergeArtifactService.PersistResult result =
            ApexMergeArtifactService.persistArtifact(request);
        Test.stopTest();

        assertSuccessResult(result, request, false);
        assertStoredFile(
            planId,
            request,
            bytes,
            'Foo.cls-meta.xml',
            'apex-merge-artifact|'
        );
    }

    @IsTest
    static void persist_sha256Mismatch_rejected() {
        Id planId = seedDeploymentPlan();
        Blob bytes = Blob.valueOf('class Body {}');
        ApexMergeArtifactService.PersistRequest request = buildRequest(
            planId,
            ARTIFACT_ID_CLS,
            'Foo',
            ApexMergeArtifactService.ROLE_CLS,
            bytes
        );
        request.expectedSha256 =
            '0000000000000000000000000000000000000000000000000000000000000000';

        ApexMergeArtifactService.PersistResult result =
            ApexMergeArtifactService.persistArtifact(request);

        System.assertEquals(false, result.success);
        System.assertEquals('INTEGRITY_MISMATCH', result.code);
        assertNoFilesForArtifact(request.artifactId);
    }

    @IsTest
    static void persist_byteLengthMismatch_rejected() {
        Id planId = seedDeploymentPlan();
        Blob bytes = Blob.valueOf('class Body {}');
        ApexMergeArtifactService.PersistRequest request = buildRequest(
            planId,
            ARTIFACT_ID_CLS,
            'Foo',
            ApexMergeArtifactService.ROLE_CLS,
            bytes
        );
        request.expectedByteLength = bytes.size() + 10;

        ApexMergeArtifactService.PersistResult result =
            ApexMergeArtifactService.persistArtifact(request);

        System.assertEquals(false, result.success);
        System.assertEquals('INTEGRITY_MISMATCH', result.code);
        assertNoFilesForArtifact(request.artifactId);
    }

    @IsTest
    static void persist_emptyBlob_rejected() {
        Id planId = seedDeploymentPlan();
        ApexMergeArtifactService.PersistRequest request =
            new ApexMergeArtifactService.PersistRequest();
        request.deploymentPlanId = planId;
        request.mergeManifestId = MANIFEST_ID;
        request.artifactId = ARTIFACT_ID_CLS;
        request.metadataName = 'Foo';
        request.role = ApexMergeArtifactService.ROLE_CLS;
        request.artifactContent = Blob.valueOf('');
        request.expectedByteLength = 0;
        request.expectedSha256 = sha256Hex(Blob.valueOf(''));

        ApexMergeArtifactService.PersistResult result =
            ApexMergeArtifactService.persistArtifact(request);

        System.assertEquals(false, result.success);
        System.assertEquals('INVALID_REQUEST', result.code);
    }

    @IsTest
    static void persist_nullMetadata_rejected() {
        Id planId = seedDeploymentPlan();
        Blob bytes = Blob.valueOf('class X {}');
        ApexMergeArtifactService.PersistRequest request = buildRequest(
            planId,
            ARTIFACT_ID_CLS,
            null,
            ApexMergeArtifactService.ROLE_CLS,
            bytes
        );

        ApexMergeArtifactService.PersistResult result =
            ApexMergeArtifactService.persistArtifact(request);

        System.assertEquals(false, result.success);
        System.assertEquals('INVALID_REQUEST', result.code);
    }

    @IsTest
    static void persist_invalidRole_rejected() {
        Id planId = seedDeploymentPlan();
        Blob bytes = Blob.valueOf('class X {}');
        ApexMergeArtifactService.PersistRequest request = buildRequest(
            planId,
            ARTIFACT_ID_CLS,
            'Foo',
            'body',
            bytes
        );

        ApexMergeArtifactService.PersistResult result =
            ApexMergeArtifactService.persistArtifact(request);

        System.assertEquals(false, result.success);
        System.assertEquals('INVALID_REQUEST', result.code);
    }

    @IsTest
    static void persist_unknownPlan_rejected() {
        Id planId = seedDeploymentPlan();
        delete [SELECT Id FROM Deployment_Plan__c WHERE Id = :planId];

        Blob bytes = Blob.valueOf('class X {}');
        ApexMergeArtifactService.PersistRequest request = buildRequest(
            planId,
            ARTIFACT_ID_CLS,
            'Foo',
            ApexMergeArtifactService.ROLE_CLS,
            bytes
        );

        ApexMergeArtifactService.PersistResult result =
            ApexMergeArtifactService.persistArtifact(request);

        System.assertEquals(false, result.success);
        System.assertEquals('NOT_FOUND', result.code);
    }

    @IsTest
    static void persist_duplicateRetry_reusesContentDocument() {
        Id planId = seedDeploymentPlan();
        Blob bytes = Blob.valueOf('public class RetryTest {}');
        ApexMergeArtifactService.PersistRequest request = buildRequest(
            planId,
            ARTIFACT_ID_CLS,
            'RetryTest',
            ApexMergeArtifactService.ROLE_CLS,
            bytes
        );

        ApexMergeArtifactService.PersistResult first =
            ApexMergeArtifactService.persistArtifact(request);
        System.assertEquals(true, first.success);

        ApexMergeArtifactService.PersistResult second =
            ApexMergeArtifactService.persistArtifact(request);
        System.assertEquals(true, second.success);
        System.assertEquals(true, second.idempotentReuse);
        System.assertEquals(
            first.contentDocumentId,
            second.contentDocumentId
        );

        Integer latestCount = [
            SELECT COUNT()
            FROM ContentVersion
            WHERE Title = :request.artifactId
            AND IsLatest = true
        ];
        System.assertEquals(1, latestCount);
    }

    @IsTest
    static void persist_conflictingContent_rejected() {
        Id planId = seedDeploymentPlan();
        Blob firstBytes = Blob.valueOf('public class One {}');
        ApexMergeArtifactService.PersistRequest first = buildRequest(
            planId,
            ARTIFACT_ID_CLS,
            'Foo',
            ApexMergeArtifactService.ROLE_CLS,
            firstBytes
        );
        System.assertEquals(
            true,
            ApexMergeArtifactService.persistArtifact(first).success
        );

        Blob secondBytes = Blob.valueOf('public class Two {}');
        ApexMergeArtifactService.PersistRequest second = buildRequest(
            planId,
            ARTIFACT_ID_CLS,
            'Foo',
            ApexMergeArtifactService.ROLE_CLS,
            secondBytes
        );

        ApexMergeArtifactService.PersistResult conflict =
            ApexMergeArtifactService.persistArtifact(second);

        System.assertEquals(false, conflict.success);
        System.assertEquals('CONFLICT', conflict.code);
    }

    @IsTest
    static void persist_oversizedArtifact_rejected() {
        Id planId = seedDeploymentPlan();
        ApexMergeArtifactService.testPracticalByteLimitOverride = 8;
        Blob bytes = Blob.valueOf('123456789');
        ApexMergeArtifactService.PersistRequest request = buildRequest(
            planId,
            ARTIFACT_ID_CLS,
            'Big',
            ApexMergeArtifactService.ROLE_CLS,
            bytes
        );

        ApexMergeArtifactService.PersistResult result =
            ApexMergeArtifactService.persistArtifact(request);

        System.assertEquals(false, result.success);
        System.assertEquals('INVALID_REQUEST', result.code);
        System.assert(
            result.message.contains('practical Apex byte limit'),
            result.message
        );
    }

    @IsTest
    static void persist_returnsContentDocumentIdAndMetadata() {
        Id planId = seedDeploymentPlan();
        Blob bytes = Blob.valueOf('// meta payload');
        ApexMergeArtifactService.PersistRequest request = buildRequest(
            planId,
            ARTIFACT_ID_META,
            'Bar',
            ApexMergeArtifactService.ROLE_META_XML,
            bytes
        );

        ApexMergeArtifactService.PersistResult result =
            ApexMergeArtifactService.persistArtifact(request);

        System.assertEquals(true, result.success);
        System.assertNotEquals(null, result.contentDocumentId);
        System.assertEquals(request.artifactId, result.artifactId);
        System.assertEquals(request.metadataName, result.metadataName);
        System.assertEquals(request.role, result.role);
        System.assertEquals(request.expectedByteLength, result.byteLength);
        System.assertEquals(
            sha256Hex(bytes).toLowerCase(),
            result.sha256.toLowerCase()
        );
    }

    @IsTest
    static void persist_ambiguousDuplicateFiles_rejected() {
        Id planId = seedDeploymentPlan();
        Blob bytes = Blob.valueOf('public class Dup {}');
        ApexMergeArtifactService.PersistRequest request = buildRequest(
            planId,
            ARTIFACT_ID_CLS,
            'Dup',
            ApexMergeArtifactService.ROLE_CLS,
            bytes
        );

        String description =
            'apex-merge-artifact|' +
            String.valueOf(planId) +
            '|' +
            MANIFEST_ID +
            '|' +
            ARTIFACT_ID_CLS +
            '|Dup|cls|' +
            sha256Hex(bytes) +
            '|' +
            bytes.size();

        insert new List<ContentVersion>{
            new ContentVersion(
                Title = ARTIFACT_ID_CLS,
                PathOnClient = 'Dup.cls',
                VersionData = bytes,
                FirstPublishLocationId = planId,
                Description = description
            ),
            new ContentVersion(
                Title = ARTIFACT_ID_CLS,
                PathOnClient = 'Dup.cls',
                VersionData = bytes,
                FirstPublishLocationId = planId,
                Description = description
            )
        };

        ApexMergeArtifactService.PersistResult result =
            ApexMergeArtifactService.persistArtifact(request);

        System.assertEquals(false, result.success);
        System.assertEquals('AMBIGUOUS', result.code);
    }

    private static ApexMergeArtifactService.PersistRequest buildRequest(
        Id planId,
        String artifactId,
        String metadataName,
        String role,
        Blob bytes
    ) {
        ApexMergeArtifactService.PersistRequest request =
            new ApexMergeArtifactService.PersistRequest();
        request.deploymentPlanId = planId;
        request.mergeManifestId = MANIFEST_ID;
        request.artifactId = artifactId;
        request.metadataName = metadataName;
        request.role = role;
        request.artifactContent = bytes;
        request.expectedByteLength = bytes.size();
        request.expectedSha256 = sha256Hex(bytes);
        return request;
    }

    private static void assertSuccessResult(
        ApexMergeArtifactService.PersistResult result,
        ApexMergeArtifactService.PersistRequest request,
        Boolean expectedReuse
    ) {
        System.assertEquals(
            true,
            result.success,
            'Expected persistence to succeed'
                + (result.success == true
                    ? '.'
                    : '; code=' + String.valueOf(result.code)
                        + '; message=' + String.valueOf(result.message))
        );
        System.assertNotEquals(null, result.contentDocumentId);
        System.assertEquals(request.artifactId, result.artifactId);
        System.assertEquals(
            expectedReuse == true,
            result.idempotentReuse == true
        );
    }

    private static void assertStoredFile(
        Id planId,
        ApexMergeArtifactService.PersistRequest request,
        Blob expectedBytes,
        String expectedPathSuffix,
        String descriptionPrefix
    ) {
        List<ContentVersion> versions = [
            SELECT
                Id,
                Title,
                PathOnClient,
                VersionData,
                FirstPublishLocationId,
                Description,
                ContentDocumentId
            FROM ContentVersion
            WHERE Title = :request.artifactId
            AND IsLatest = true
            LIMIT 1
        ];
        System.assertEquals(1, versions.size());
        ContentVersion stored = versions[0];

        System.assertEquals(request.artifactId, stored.Title);
        System.assertEquals(expectedPathSuffix, stored.PathOnClient);
        System.assertEquals(planId, stored.FirstPublishLocationId);
        System.assert(stored.Description.startsWith(descriptionPrefix));
        System.assert(
            stored.Description.contains(MANIFEST_ID),
            stored.Description
        );
        System.assert(
            stored.Description.contains(request.metadataName),
            stored.Description
        );
        System.assert(
            stored.Description.contains(request.role),
            stored.Description
        );
        assertBlobEqual(expectedBytes, stored.VersionData);
    }

    private static void assertNoFilesForArtifact(String artifactId) {
        System.assertEquals(
            0,
            [SELECT COUNT() FROM ContentVersion WHERE Title = :artifactId]
        );
    }

    private static Id seedDeploymentPlan() {
        Connected_Org__c src = new Connected_Org__c(
            Name = 'Src Merge Art',
            Org_ID__c = '00Dmerge000000001',
            Instance_URL__c = 'https://src-merge.example.com',
            Refresh_Token__c = 'mock-token-src',
            Active__c = true
        );
        Connected_Org__c dst = new Connected_Org__c(
            Name = 'Dst Merge Art',
            Org_ID__c = '00Dmerge000000002',
            Instance_URL__c = 'https://dst-merge.example.com',
            Refresh_Token__c = 'mock-token-dst',
            Active__c = true
        );
        insert new List<Connected_Org__c>{ src, dst };

        Metadata_Comparison__c comparison = new Metadata_Comparison__c(
            Name = 'Cmp Merge Art',
            Source_Org__c = src.Id,
            Destination_Org__c = dst.Id,
            Source_Branch__c = 'gym',
            Destination_Branch__c = 'agent'
        );
        insert comparison;

        Deployment_Plan__c plan = new Deployment_Plan__c(
            Name = 'DP-Merge-Artifact',
            Metadata_Comparison__c = comparison.Id,
            Source_Org__c = src.Id,
            Destination_Org__c = dst.Id,
            Status__c = 'Draft'
        );
        insert plan;
        return plan.Id;
    }

    private static String sha256Hex(Blob value) {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', value)
        ).toLowerCase();
    }

    private static void assertBlobEqual(Blob expected, Blob actual) {
        System.assertEquals(
            EncodingUtil.convertToHex(expected),
            EncodingUtil.convertToHex(actual)
        );
    }

}