/**
 * Salesforce Files artifact contract for destination-before packed bytes.
 * Stores binary content on ContentVersion.VersionData only.
 * No Long Text / Base64 fields. No bytes on custom objects.
 * Practical Apex heap limit applies; large-artifact streaming is out of scope.
 */
public with sharing class DeploymentSnapshotArtifactService {
    public static final Integer PRACTICAL_APEX_BYTE_LIMIT = 4500000;
    public static final Integer CONTENT_VERSION_TITLE_LIMIT = 255;
    private static final String DESCRIPTION_PREFIX = 'control-plane-artifact|';

    public static ControlPlaneResult storeArtifact(
        String snapshotId,
        String metadataType,
        String metadataName,
        String artifactId,
        Blob versionData
    ) {
        if (versionData == null || versionData.size() == 0) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'Artifact bytes are required.'
            );
        }
        if (String.isBlank(artifactId)) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'artifactId is required.'
            );
        }
        ControlPlaneResult lengthError = rejectIfArtifactIdTooLong(artifactId);
        if (lengthError != null) {
            return lengthError;
        }
        if (!Schema.sObjectType.ContentVersion.isCreateable()) {
            return ControlPlaneResult.fail(
                'UNAUTHORIZED',
                'Insufficient access for ContentVersion.'
            );
        }

        ControlPlaneResult memberResult =
            DeploymentSnapshotService.getMember(
                snapshotId,
                metadataType,
                metadataName
            );
        if (memberResult.success != true) {
            return memberResult;
        }
        Deployment_Snapshot_Member__c member =
            (Deployment_Snapshot_Member__c) memberResult.record;
        if (member.Snapshot_Is_Sealed__c == true) {
            return ControlPlaneResult.fail(
                'SEALED',
                'SEALED snapshots are immutable.'
            );
        }

        Deployment_Snapshot__c snapshot = [
            SELECT Id, Snapshot_Id__c, Status__c
            FROM Deployment_Snapshot__c
            WHERE Snapshot_Id__c = :snapshotId
            LIMIT 1
        ];

        ContentVersion version = new ContentVersion();
        version.Title = artifactId;
        version.PathOnClient = toPathOnClient(artifactId);
        version.VersionData = versionData;
        version.FirstPublishLocationId = snapshot.Id;
        version.Description =
            'control-plane-artifact|' +
            snapshotId +
            '|' +
            member.Member_Key__c;

        try {
            insert version;
        } catch (DmlException e) {
            return ControlPlaneResult.fail(
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

        member.Artifact_Id__c = artifactId;
        member.Artifact_Size__c = stored.ContentSize;
        member.Content_Document_Id__c = stored.ContentDocumentId;
        try {
            update member;
        } catch (DmlException e) {
            return ControlPlaneResult.fail(
                'SEALED',
                'SEALED snapshots are immutable.'
            );
        }

        ControlPlaneResult result = ControlPlaneResult.ok(member);
        result.message = stored.ContentDocumentId;
        result.artifactId = artifactId;
        result.artifactSize = stored.ContentSize;
        result.contentDocumentId = stored.ContentDocumentId;
        return result;
    }

    /**
     * REST/backend upload. Member may not exist yet (Node put-before-addMember).
     * Bytes are stored on the snapshot via FirstPublishLocationId.
     */
    public static ControlPlaneResult storeArtifactById(
        String snapshotId,
        String artifactId,
        Blob versionData
    ) {
        if (versionData == null || versionData.size() == 0) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'Artifact bytes are required.'
            );
        }
        if (versionData.size() > PRACTICAL_APEX_BYTE_LIMIT) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'Artifact exceeds the practical Apex byte limit.'
            );
        }

        ParsedArtifact parsed = parseAndValidate(snapshotId, artifactId);
        if (parsed.error != null) {
            return parsed.error;
        }
        if (!Schema.sObjectType.ContentVersion.isCreateable()) {
            return ControlPlaneResult.fail(
                'UNAUTHORIZED',
                'Insufficient access for ContentVersion.'
            );
        }

        List<Deployment_Snapshot__c> snapshots = [
            SELECT Id, Snapshot_Id__c, Status__c
            FROM Deployment_Snapshot__c
            WHERE Snapshot_Id__c = :snapshotId
            LIMIT 1
        ];
        if (snapshots.isEmpty()) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Snapshot not found.');
        }
        Deployment_Snapshot__c snapshot = snapshots[0];
        if (snapshot.Status__c == DeploymentSnapshotService.STATUS_SEALED) {
            return ControlPlaneResult.fail(
                'SEALED',
                'SEALED snapshots are immutable.'
            );
        }

        Deployment_Snapshot_Member__c member = findMemberIfPresent(
            snapshotId,
            parsed.identity.metadataType,
            parsed.identity.metadataName
        );
        if (member != null && member.Snapshot_Is_Sealed__c == true) {
            return ControlPlaneResult.fail(
                'SEALED',
                'SEALED snapshots are immutable.'
            );
        }

        ContentVersion existing = findLatestVersion(snapshotId, artifactId);
        ContentVersion version = new ContentVersion();
        version.Title = artifactId;
        version.PathOnClient = toPathOnClient(artifactId);
        version.VersionData = versionData;
        version.Description = descriptionValue(snapshotId, artifactId);
        if (existing != null) {
            version.ContentDocumentId = existing.ContentDocumentId;
        } else {
            version.FirstPublishLocationId = snapshot.Id;
        }

        try {
            insert version;
        } catch (DmlException e) {
            return ControlPlaneResult.fail(
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

        if (member != null) {
            ControlPlaneResult memberUpdate = updateMemberArtifact(member, stored);
            if (memberUpdate.success != true) {
                return memberUpdate;
            }
            member = (Deployment_Snapshot_Member__c) memberUpdate.record;
        }

        return artifactEnvelope(
            artifactId,
            stored.ContentSize,
            stored.ContentDocumentId,
            member
        );
    }

    public static ControlPlaneResult getArtifactMetadata(
        String snapshotId,
        String metadataType,
        String metadataName
    ) {
        ControlPlaneResult memberResult =
            DeploymentSnapshotService.getMember(
                snapshotId,
                metadataType,
                metadataName
            );
        if (memberResult.success != true) {
            return memberResult;
        }
        return memberResult;
    }

    public static ControlPlaneResult getArtifactMetadataById(
        String snapshotId,
        String artifactId
    ) {
        ParsedArtifact parsed = parseAndValidate(snapshotId, artifactId);
        if (parsed.error != null) {
            return parsed.error;
        }
        ContentVersion version = findLatestVersion(snapshotId, artifactId);
        if (version == null) {
            return ControlPlaneResult.fail(
                'NOT_FOUND',
                'Artifact file is not associated.'
            );
        }
        Deployment_Snapshot_Member__c member = findMemberIfPresent(
            snapshotId,
            parsed.identity.metadataType,
            parsed.identity.metadataName
        );
        return artifactEnvelope(
            artifactId,
            version.ContentSize,
            version.ContentDocumentId,
            member
        );
    }

    public static ControlPlaneResult existsArtifactById(
        String snapshotId,
        String artifactId
    ) {
        ParsedArtifact parsed = parseAndValidate(snapshotId, artifactId);
        if (parsed.error != null) {
            return parsed.error;
        }
        ContentVersion version = findLatestVersion(snapshotId, artifactId);
        if (version == null) {
            return ControlPlaneResult.fail(
                'NOT_FOUND',
                'Artifact file is not associated.'
            );
        }
        ControlPlaneResult result = artifactEnvelope(
            artifactId,
            version.ContentSize,
            version.ContentDocumentId,
            null
        );
        result.exists = true;
        return result;
    }

    /**
     * Returns artifact bytes for backend integration.
     * Not exposed on LWC and not a public rollback API.
     */
    public static ControlPlaneResult getArtifactBytes(
        String snapshotId,
        String metadataType,
        String metadataName
    ) {
        ControlPlaneResult memberResult =
            DeploymentSnapshotService.getMember(
                snapshotId,
                metadataType,
                metadataName
            );
        if (memberResult.success != true) {
            return memberResult;
        }

        Deployment_Snapshot_Member__c member =
            (Deployment_Snapshot_Member__c) memberResult.record;
        if (String.isBlank(member.Content_Document_Id__c)) {
            return ControlPlaneResult.fail(
                'NOT_FOUND',
                'Artifact file is not associated.'
            );
        }

        List<ContentVersion> versions = [
            SELECT Id, VersionData, ContentSize, Title, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId = :member.Content_Document_Id__c
            AND IsLatest = true
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            return ControlPlaneResult.fail(
                'NOT_FOUND',
                'Artifact file is not associated.'
            );
        }

        ControlPlaneResult result = ControlPlaneResult.ok(member);
        result.artifactBytes = versions[0].VersionData;
        result.artifactId = member.Artifact_Id__c;
        result.artifactSize = versions[0].ContentSize;
        result.contentDocumentId = versions[0].ContentDocumentId;
        return result;
    }

    public static ControlPlaneResult getArtifactBytesById(
        String snapshotId,
        String artifactId
    ) {
        ParsedArtifact parsed = parseAndValidate(snapshotId, artifactId);
        if (parsed.error != null) {
            return parsed.error;
        }

        List<ContentVersion> versions = queryLatestWithBytes(snapshotId, artifactId);
        if (versions.isEmpty()) {
            return ControlPlaneResult.fail(
                'NOT_FOUND',
                'Artifact file is not associated.'
            );
        }

        Deployment_Snapshot_Member__c member = findMemberIfPresent(
            snapshotId,
            parsed.identity.metadataType,
            parsed.identity.metadataName
        );
        ControlPlaneResult result = artifactEnvelope(
            artifactId,
            versions[0].ContentSize,
            versions[0].ContentDocumentId,
            member
        );
        result.artifactBytes = versions[0].VersionData;
        return result;
    }

    public static ContentVersion findLatestVersion(
        String snapshotId,
        String artifactId
    ) {
        if (String.isBlank(snapshotId) || String.isBlank(artifactId)) {
            return null;
        }
        String prefix = descriptionPrefix(snapshotId);
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, ContentSize, Title, Description
            FROM ContentVersion
            WHERE Title = :artifactId
            AND IsLatest = true
            AND Description LIKE :prefix
            LIMIT 2
        ];
        return versions.isEmpty() ? null : versions[0];
    }

    public static ControlPlaneResult validateArtifactId(
        String snapshotId,
        String artifactId
    ) {
        ParsedArtifact parsed = parseAndValidate(snapshotId, artifactId);
        return parsed.error != null
            ? parsed.error
            : ControlPlaneResult.ok(null);
    }

    public class ArtifactIdentity {
        public String snapshotId;
        public String metadataType;
        public String metadataName;
        public String artifactId;
    }

    private class ParsedArtifact {
        public ControlPlaneResult error;
        public ArtifactIdentity identity;
    }

    private static ParsedArtifact parseAndValidate(
        String snapshotId,
        String artifactId
    ) {
        ParsedArtifact parsed = new ParsedArtifact();
        if (String.isBlank(snapshotId)) {
            parsed.error = ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'snapshotId is required.'
            );
            return parsed;
        }
        if (String.isBlank(artifactId)) {
            parsed.error = ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'artifactId is required.'
            );
            return parsed;
        }
        if (artifactId.contains('..') ||
            artifactId.contains('\\') ||
            artifactId.startsWith('/') ||
            !artifactId.startsWith('snapshots/')) {
            parsed.error = ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'artifactId must be a snapshots/ relative path.'
            );
            return parsed;
        }
        ControlPlaneResult lengthError = rejectIfArtifactIdTooLong(artifactId);
        if (lengthError != null) {
            parsed.error = lengthError;
            return parsed;
        }

        List<String> parts = artifactId.split('/');
        if (parts.size() != 5 ||
            parts[0] != 'snapshots' ||
            parts[2] != 'destination-before' ||
            String.isBlank(parts[1]) ||
            String.isBlank(parts[3]) ||
            String.isBlank(parts[4])) {
            parsed.error = ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'artifactId must match snapshots/{snapshotId}/destination-before/{type}/{name}.'
            );
            return parsed;
        }
        if (parts[1] != snapshotId) {
            parsed.error = ControlPlaneResult.fail(
                'NOT_FOUND',
                'Artifact does not belong to this snapshot.'
            );
            return parsed;
        }

        ArtifactIdentity identity = new ArtifactIdentity();
        identity.snapshotId = parts[1];
        identity.metadataType = EncodingUtil.urlDecode(parts[3], 'UTF-8');
        identity.metadataName = EncodingUtil.urlDecode(parts[4], 'UTF-8');
        identity.artifactId = artifactId;
        parsed.identity = identity;
        return parsed;
    }

    private static ControlPlaneResult updateMemberArtifact(
        Deployment_Snapshot_Member__c member,
        ContentVersion stored
    ) {
        if (String.isNotBlank(stored.Title)) {
            member.Artifact_Id__c = stored.Title;
        }
        member.Artifact_Size__c = stored.ContentSize;
        member.Content_Document_Id__c = stored.ContentDocumentId;
        try {
            update member;
        } catch (DmlException e) {
            return ControlPlaneResult.fail(
                'SEALED',
                'SEALED snapshots are immutable.'
            );
        }
        return ControlPlaneResult.ok(member);
    }

    private static Deployment_Snapshot_Member__c findMemberIfPresent(
        String snapshotId,
        String metadataType,
        String metadataName
    ) {
        ControlPlaneResult memberResult =
            DeploymentSnapshotService.getMember(
                snapshotId,
                metadataType,
                metadataName
            );
        if (memberResult.success != true) {
            return null;
        }
        return (Deployment_Snapshot_Member__c) memberResult.record;
    }

    private static List<ContentVersion> queryLatestWithBytes(
        String snapshotId,
        String artifactId
    ) {
        String prefix = descriptionPrefix(snapshotId);
        return [
            SELECT Id, VersionData, ContentSize, Title, ContentDocumentId, Description
            FROM ContentVersion
            WHERE Title = :artifactId
            AND IsLatest = true
            AND Description LIKE :prefix
            LIMIT 1
        ];
    }

    private static ControlPlaneResult artifactEnvelope(
        String artifactId,
        Decimal size,
        Id contentDocumentId,
        SObject record
    ) {
        ControlPlaneResult result = ControlPlaneResult.ok(record);
        result.artifactId = artifactId;
        result.artifactSize = size;
        result.contentDocumentId = contentDocumentId;
        result.message = contentDocumentId == null ? null : String.valueOf(contentDocumentId);
        return result;
    }

    private static ControlPlaneResult rejectIfArtifactIdTooLong(
        String artifactId
    ) {
        if (artifactId != null &&
            artifactId.length() > CONTENT_VERSION_TITLE_LIMIT) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'artifactId exceeds the 255-character persistable length.'
            );
        }
        return null;
    }

    private static String descriptionPrefix(String snapshotId) {
        return DESCRIPTION_PREFIX + snapshotId + '|%';
    }

    private static String descriptionValue(String snapshotId, String artifactId) {
        return DESCRIPTION_PREFIX + snapshotId + '|' + artifactId;
    }

    private static String toPathOnClient(String artifactId) {
        String safe = artifactId.replace('/', '_').replace('\\', '_');
        if (safe.length() > 240) {
            safe = safe.substring(0, 240);
        }
        return safe + '.bin';
    }

    private static String sanitizedDmlMessage(DmlException e) {
        if (e == null) {
            return 'Unable to store artifact.';
        }
        String message = e.getMessage();
        if (String.isBlank(message)) {
            return 'Unable to store artifact.';
        }
        if (message.length() > 240) {
            return message.substring(0, 240);
        }
        return message;
    }
}