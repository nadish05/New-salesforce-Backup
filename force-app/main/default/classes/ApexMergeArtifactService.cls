/**
 * Salesforce Files persistence for Apex merge artifacts (.cls / .cls-meta.xml).
 * Stores binary content on ContentVersion.VersionData only.
 * No Long Text / Base64 on custom objects. Does not call the merge backend.
 */
public with sharing class ApexMergeArtifactService {
    public static final String ROLE_CLS = 'cls';
    public static final String ROLE_META_XML = 'metaXml';

    private static final String DESCRIPTION_PREFIX = 'apex-merge-artifact|';
    private static final Set<String> SUPPORTED_ROLES = new Set<String>{
        ROLE_CLS,
        ROLE_META_XML
    };

    @TestVisible
    private static Integer testPracticalByteLimitOverride;

    public class PersistRequest {
        public Id deploymentPlanId;
        public String mergeManifestId;
        public String artifactId;
        public String metadataName;
        public String role;
        public Blob artifactContent;
        public String expectedSha256;
        public Integer expectedByteLength;
    }

    public class PersistResult {
        public Boolean success;
        public String code;
        public String message;
        public String artifactId;
        public Id contentDocumentId;
        public String sha256;
        public Integer byteLength;
        public String metadataName;
        public String role;
        public Boolean idempotentReuse;
    }

    /**
     * Persists a merge artifact after caller-side retrieval and integrity checks.
     */
    public static PersistResult persistArtifact(PersistRequest request) {
        PersistResult validation = validateRequest(request);
        if (validation != null) {
            return validation;
        }

        Blob bytes = request.artifactContent;
        if (bytes.size() > practicalByteLimit()) {
            return failResult(
                'INVALID_REQUEST',
                'Artifact exceeds the practical Apex byte limit.'
            );
        }

        Integer actualSize = bytes.size();
        if (request.expectedByteLength != actualSize) {
            return failResult(
                'INTEGRITY_MISMATCH',
                'Byte length does not match artifact content.'
            );
        }

        String actualHash = sha256Hex(bytes);
        String expectedHash = normalizeHash(request.expectedSha256);
        if (actualHash != expectedHash) {
            return failResult(
                'INTEGRITY_MISMATCH',
                'SHA-256 does not match artifact content.'
            );
        }

        if (!deploymentPlanExists(request.deploymentPlanId)) {
            return failResult('NOT_FOUND', 'Deployment plan not found.');
        }

        if (!Schema.sObjectType.ContentVersion.isCreateable()) {
            return failResult(
                'UNAUTHORIZED',
                'Insufficient access for ContentVersion.'
            );
        }

        List<ContentVersion> matching = queryMatchingLatestVersions(
            request.deploymentPlanId,
            request.mergeManifestId,
            request.artifactId
        );
        if (matching.size() > 1) {
            return failResult(
                'AMBIGUOUS',
                'Multiple artifact files match this identity.'
            );
        }
        if (matching.size() == 1) {
            return handleExistingArtifact(matching[0], request, actualHash);
        }

        ContentVersion version = new ContentVersion();
        version.Title = request.artifactId;
        version.PathOnClient = pathOnClient(request.metadataName, request.role);
        version.VersionData = bytes;
        version.FirstPublishLocationId = request.deploymentPlanId;
        version.Description = buildDescription(request, actualHash, actualSize);

        try {
            insert version;
        } catch (DmlException e) {
            return failResult(
                'INVALID_REQUEST',
                sanitizedDmlMessage(e)
            );
        }

        ContentVersion stored = [
            SELECT Id, ContentDocumentId, ContentSize, Title
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        return okResult(
            request,
            stored.ContentDocumentId,
            false
        );
    }

    public static ContentVersion findLatestVersion(
        Id deploymentPlanId,
        String mergeManifestId,
        String artifactId
    ) {
        List<ContentVersion> matching = queryMatchingLatestVersions(
            deploymentPlanId,
            mergeManifestId,
            artifactId
        );
        return matching.size() == 1 ? matching[0] : null;
    }

    private static List<ContentVersion> queryMatchingLatestVersions(
        Id deploymentPlanId,
        String mergeManifestId,
        String artifactId
    ) {
        if (
            deploymentPlanId == null ||
            String.isBlank(mergeManifestId) ||
            String.isBlank(artifactId)
        ) {
            return new List<ContentVersion>();
        }

        String descriptionMarker =
            descriptionKeyPrefix(deploymentPlanId, mergeManifestId, artifactId) +
            '%';

        return [
            SELECT Id, ContentDocumentId, ContentSize, Title, Description
            FROM ContentVersion
            WHERE Title = :artifactId
            AND IsLatest = true
            AND Description LIKE :descriptionMarker
            ORDER BY CreatedDate DESC
        ];
    }

    @TestVisible
    private static PersistResult validateRequest(PersistRequest request) {
        if (request == null) {
            return failResult(
                'INVALID_REQUEST',
                'Persist request is required.'
            );
        }
        if (request.deploymentPlanId == null) {
            return failResult(
                'INVALID_REQUEST',
                'deploymentPlanId is required.'
            );
        }
        if (String.isBlank(request.mergeManifestId)) {
            return failResult(
                'INVALID_REQUEST',
                'mergeManifestId is required.'
            );
        }
        if (String.isBlank(request.artifactId)) {
            return failResult(
                'INVALID_REQUEST',
                'artifactId is required.'
            );
        }
        if (request.artifactId.length() >
            DeploymentSnapshotArtifactService.CONTENT_VERSION_TITLE_LIMIT) {
            return failResult(
                'INVALID_REQUEST',
                'artifactId exceeds the 255-character persistable length.'
            );
        }
        if (String.isBlank(request.metadataName)) {
            return failResult(
                'INVALID_REQUEST',
                'metadataName is required.'
            );
        }
        if (String.isBlank(request.role) || !SUPPORTED_ROLES.contains(request.role)) {
            return failResult(
                'INVALID_REQUEST',
                'role must be cls or metaXml.'
            );
        }
        if (request.artifactContent == null || request.artifactContent.size() == 0) {
            return failResult(
                'INVALID_REQUEST',
                'Artifact bytes are required.'
            );
        }
        if (String.isBlank(request.expectedSha256)) {
            return failResult(
                'INVALID_REQUEST',
                'expectedSha256 is required.'
            );
        }
        if (request.expectedByteLength == null || request.expectedByteLength < 0) {
            return failResult(
                'INVALID_REQUEST',
                'expectedByteLength is required.'
            );
        }
        return null;
    }

    private static PersistResult handleExistingArtifact(
        ContentVersion existing,
        PersistRequest request,
        String actualHash
    ) {
        List<ContentVersion> rows = [
            SELECT Id, VersionData, ContentDocumentId, ContentSize
            FROM ContentVersion
            WHERE Id = :existing.Id
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return failResult(
                'NOT_FOUND',
                'Existing artifact file could not be loaded.'
            );
        }

        Blob storedBytes = rows[0].VersionData;
        if (storedBytes == null || storedBytes.size() == 0) {
            return failResult(
                'CONFLICT',
                'Stored artifact file has no content.'
            );
        }

        String storedHash = sha256Hex(storedBytes);
        if (storedHash == actualHash) {
            return okResult(
                request,
                rows[0].ContentDocumentId,
                true
            );
        }

        return failResult(
            'CONFLICT',
            'Artifact identity already has different content.'
        );
    }

    private static PersistResult okResult(
        PersistRequest request,
        Id contentDocumentId,
        Boolean idempotentReuse
    ) {
        PersistResult result = new PersistResult();
        result.success = true;
        result.artifactId = request.artifactId;
        result.contentDocumentId = contentDocumentId;
        result.sha256 = normalizeHash(request.expectedSha256);
        result.byteLength = request.expectedByteLength;
        result.metadataName = request.metadataName;
        result.role = request.role;
        result.idempotentReuse = idempotentReuse == true;
        return result;
    }

    private static PersistResult failResult(String code, String message) {
        PersistResult result = new PersistResult();
        result.success = false;
        result.code = code;
        result.message = message;
        return result;
    }

    private static Boolean deploymentPlanExists(Id deploymentPlanId) {
        return [
                SELECT COUNT()
                FROM Deployment_Plan__c
                WHERE Id = :deploymentPlanId
            ] > 0;
    }

    private static String buildDescription(
        PersistRequest request,
        String sha256Hex,
        Integer byteLength
    ) {
        return descriptionKeyPrefix(
                request.deploymentPlanId,
                request.mergeManifestId,
                request.artifactId
            ) +
            request.metadataName +
            '|' +
            request.role +
            '|' +
            sha256Hex +
            '|' +
            String.valueOf(byteLength);
    }

    private static String descriptionKeyPrefix(
        Id deploymentPlanId,
        String mergeManifestId,
        String artifactId
    ) {
        return DESCRIPTION_PREFIX +
            String.valueOf(deploymentPlanId) +
            '|' +
            mergeManifestId +
            '|' +
            artifactId +
            '|';
    }

    private static Integer practicalByteLimit() {
        if (Test.isRunningTest() && testPracticalByteLimitOverride != null) {
            return testPracticalByteLimitOverride;
        }
        return DeploymentSnapshotArtifactService.PRACTICAL_APEX_BYTE_LIMIT;
    }

    private static String pathOnClient(String metadataName, String role) {
        String safeName = String.isBlank(metadataName)
            ? 'artifact'
            : metadataName.trim();
        safeName = safeName.replace('/', '_').replace('\\', '_');
        if (role == ROLE_META_XML) {
            return safeName + '.cls-meta.xml';
        }
        return safeName + '.cls';
    }

    @TestVisible
    private static String sha256Hex(Blob value) {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', value)
        ).toLowerCase();
    }

    @TestVisible
    private static String normalizeHash(String expectedSha256) {
        return expectedSha256 == null
            ? null
            : expectedSha256.trim().toLowerCase();
    }

    private static String sanitizedDmlMessage(DmlException e) {
        if (e == null) {
            return 'Unable to store merge artifact.';
        }
        String message = e.getMessage();
        if (String.isBlank(message)) {
            return 'Unable to store merge artifact.';
        }
        if (message.length() > 240) {
            return message.substring(0, 240);
        }
        return message;
    }
}