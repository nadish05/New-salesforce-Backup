/**
 * Durable snapshot + member persistence for the Product/Control Org.
 * Does not retrieve, deploy, or delete destination metadata.
 */
public with sharing class DeploymentSnapshotService {
    public static final String STATUS_CAPTURING = 'CAPTURING';
    public static final String STATUS_READY = 'READY';
    public static final String STATUS_SEALED = 'SEALED';
    public static final String STATUS_FAILED = 'FAILED';

    private static final Set<String> SNAPSHOT_STATUSES = new Set<String>{
        STATUS_CAPTURING,
        STATUS_READY,
        STATUS_SEALED,
        STATUS_FAILED
    };
    private static final Set<String> CHANGE_CLASSES = new Set<String>{
        'MODIFIED',
        'NEW',
        'UNKNOWN'
    };
    private static final Set<String> CAPTURE_STATUSES = new Set<String>{
        'PENDING',
        'CAPTURING',
        'CAPTURED',
        'FAILED',
        'SKIPPED',
        'NOT_REQUIRED'
    };

    public static ControlPlaneResult createSnapshot(Map<String, Object> raw) {
        if (!isCreateable(Deployment_Snapshot__c.SObjectType)) {
            return unauthorized('Deployment_Snapshot__c');
        }

        Map<String, Object> payload = ControlPlaneSanitize.sanitize(raw);
        String snapshotId = textValue(payload.get('snapshotId'));
        if (String.isBlank(snapshotId)) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'snapshotId is required.'
            );
        }

        Deployment_Snapshot__c record = new Deployment_Snapshot__c();
        applySnapshotFields(record, payload, false);
        record.Snapshot_Id__c = snapshotId;
        if (String.isBlank(record.Status__c)) {
            record.Status__c = STATUS_CAPTURING;
        }
        if (record.Created_At__c == null) {
            record.Created_At__c = Datetime.now();
        }
        if (record.Member_Count__c == null) {
            record.Member_Count__c = 0;
        }

        try {
            insert record;
            return ControlPlaneResult.ok(getSnapshotRecord(snapshotId));
        } catch (DmlException e) {
            return dmlFailure(e, 'Snapshot_Id__c');
        }
    }

    public static ControlPlaneResult getSnapshot(String snapshotId) {
        if (!isReadable(Deployment_Snapshot__c.SObjectType)) {
            return unauthorized('Deployment_Snapshot__c');
        }
        Deployment_Snapshot__c record = getSnapshotRecord(snapshotId);
        if (record == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Snapshot not found.');
        }
        return ControlPlaneResult.ok(record);
    }

    public static ControlPlaneResult updateSnapshot(
        String snapshotId,
        Map<String, Object> raw
    ) {
        if (!isUpdateable(Deployment_Snapshot__c.SObjectType)) {
            return unauthorized('Deployment_Snapshot__c');
        }

        Deployment_Snapshot__c record = getSnapshotRecord(snapshotId);
        if (record == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Snapshot not found.');
        }
        if (record.Status__c == STATUS_SEALED) {
            return sealedFailure();
        }

        applySnapshotFields(record, ControlPlaneSanitize.sanitize(raw), true);
        if (record.Status__c == STATUS_SEALED) {
            return ControlPlaneResult.fail(
                'INVALID_STATE',
                'Use sealSnapshot to mark a snapshot SEALED.'
            );
        }

        try {
            update record;
            return ControlPlaneResult.ok(getSnapshotRecord(snapshotId));
        } catch (DmlException e) {
            return dmlFailure(e, null);
        }
    }

    public static ControlPlaneResult addMember(
        String snapshotId,
        Map<String, Object> raw
    ) {
        if (!isCreateable(Deployment_Snapshot_Member__c.SObjectType)) {
            return unauthorized('Deployment_Snapshot_Member__c');
        }

        Deployment_Snapshot__c snapshot = getSnapshotRecord(snapshotId);
        if (snapshot == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Snapshot not found.');
        }
        if (snapshot.Status__c == STATUS_SEALED) {
            return sealedFailure();
        }

        Map<String, Object> payload = ControlPlaneSanitize.sanitize(raw);
        String metadataType = textValue(payload.get('metadataType'));
        String metadataName = textValue(payload.get('metadataName'));
        if (String.isBlank(metadataType) || String.isBlank(metadataName)) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'metadataType and metadataName are required.'
            );
        }

        String changeClass = normalizePicklist(
            textValue(payload.get('changeClass')),
            CHANGE_CLASSES,
            'UNKNOWN'
        );
        String captureStatus = normalizePicklist(
            textValue(payload.get('captureStatus')),
            CAPTURE_STATUSES,
            'PENDING'
        );

        Deployment_Snapshot_Member__c member =
            new Deployment_Snapshot_Member__c();
        member.Deployment_Snapshot__c = snapshot.Id;
        member.Metadata_Type__c = metadataType;
        member.Metadata_Name__c = metadataName;
        member.File_Path__c = textValue(payload.get('filePath'));
        member.Change_Class__c = changeClass;
        member.Existed_Before__c = boolValue(payload.get('existedBefore'));
        member.Destination_Before_Hash__c =
            textValue(payload.get('destinationBeforeHash'));
        member.Expected_After_Hash__c =
            textValue(payload.get('expectedAfterHash'));
        member.Artifact_Id__c = textValue(payload.get('artifactId'));
        member.Artifact_Size__c = decimalValue(payload.get('artifactSize'));
        member.Capture_Status__c = captureStatus;
        member.Content_Document_Id__c =
            textValue(payload.get('contentDocumentId'));
        member.Member_Key__c = buildMemberKey(
            snapshot.Snapshot_Id__c,
            metadataType,
            metadataName
        );
        if (String.isBlank(member.Content_Document_Id__c) &&
            String.isNotBlank(member.Artifact_Id__c)) {
            ContentVersion storedFile =
                DeploymentSnapshotArtifactService.findLatestVersion(
                    snapshot.Snapshot_Id__c,
                    member.Artifact_Id__c
                );
            if (storedFile != null) {
                member.Content_Document_Id__c = storedFile.ContentDocumentId;
                if (member.Artifact_Size__c == null) {
                    member.Artifact_Size__c = storedFile.ContentSize;
                }
            }
        }

        try {
            insert member;
            snapshot.Member_Count__c =
                (snapshot.Member_Count__c == null
                    ? 0
                    : snapshot.Member_Count__c) + 1;
            update snapshot;
            return ControlPlaneResult.ok(getMemberRecord(member.Member_Key__c));
        } catch (DmlException e) {
            return dmlFailure(e, 'Member_Key__c');
        }
    }

    public static ControlPlaneResult getMember(
        String snapshotId,
        String metadataType,
        String metadataName
    ) {
        if (!isReadable(Deployment_Snapshot_Member__c.SObjectType)) {
            return unauthorized('Deployment_Snapshot_Member__c');
        }
        Deployment_Snapshot__c snapshot = getSnapshotRecord(snapshotId);
        if (snapshot == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Snapshot not found.');
        }
        String memberKey = buildMemberKey(
            snapshot.Snapshot_Id__c,
            metadataType,
            metadataName
        );
        Deployment_Snapshot_Member__c member = getMemberRecord(memberKey);
        if (member == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Member not found.');
        }
        return ControlPlaneResult.ok(member);
    }

    public static ControlPlaneResult getMembers(String snapshotId) {
        if (!isReadable(Deployment_Snapshot_Member__c.SObjectType)) {
            return unauthorized('Deployment_Snapshot_Member__c');
        }
        Deployment_Snapshot__c snapshot = getSnapshotRecord(snapshotId);
        if (snapshot == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Snapshot not found.');
        }
        return ControlPlaneResult.okList(
            [
                SELECT
                    Id,
                    Member_Key__c,
                    Metadata_Type__c,
                    Metadata_Name__c,
                    File_Path__c,
                    Change_Class__c,
                    Existed_Before__c,
                    Destination_Before_Hash__c,
                    Expected_After_Hash__c,
                    Artifact_Id__c,
                    Artifact_Size__c,
                    Capture_Status__c,
                    Content_Document_Id__c,
                    Snapshot_Is_Sealed__c
                FROM Deployment_Snapshot_Member__c
                WHERE Deployment_Snapshot__c = :snapshot.Id
                ORDER BY Metadata_Type__c, Metadata_Name__c
            ]
        );
    }

    public static ControlPlaneResult sealSnapshot(String snapshotId) {
        if (!isUpdateable(Deployment_Snapshot__c.SObjectType)) {
            return unauthorized('Deployment_Snapshot__c');
        }

        Deployment_Snapshot__c record = getSnapshotRecord(snapshotId);
        if (record == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Snapshot not found.');
        }
        if (record.Status__c == STATUS_SEALED) {
            return ControlPlaneResult.ok(record);
        }
        if (record.Status__c == STATUS_FAILED) {
            return ControlPlaneResult.fail(
                'INVALID_STATE',
                'FAILED snapshots cannot be sealed.'
            );
        }

        record.Status__c = STATUS_SEALED;
        record.Sealed_At__c = Datetime.now();
        if (record.Completed_At__c == null) {
            record.Completed_At__c = record.Sealed_At__c;
        }

        try {
            update record;
            return ControlPlaneResult.ok(getSnapshotRecord(snapshotId));
        } catch (DmlException e) {
            return dmlFailure(e, null);
        }
    }

    public static Boolean isSealed(String snapshotId) {
        Deployment_Snapshot__c record = getSnapshotRecord(snapshotId);
        return record != null && record.Status__c == STATUS_SEALED;
    }

    public static String buildMemberKey(
        String snapshotId,
        String metadataType,
        String metadataName
    ) {
        String key =
            String.valueOf(snapshotId) +
            '|' +
            String.valueOf(metadataType) +
            '|' +
            String.valueOf(metadataName);
        return key.length() <= 255 ? key : key.substring(0, 255);
    }

    private static void applySnapshotFields(
        Deployment_Snapshot__c record,
        Map<String, Object> payload,
        Boolean isUpdate
    ) {
        if (payload.containsKey('deploymentId')) {
            record.Deployment_Id__c = textValue(payload.get('deploymentId'));
        }
        if (payload.containsKey('sourceOrgId')) {
            record.Source_Org_Id__c = textValue(payload.get('sourceOrgId'));
        }
        if (payload.containsKey('destinationOrgId')) {
            record.Destination_Org_Id__c =
                textValue(payload.get('destinationOrgId'));
        }
        if (payload.containsKey('sourceBranch')) {
            record.Source_Branch__c = textValue(payload.get('sourceBranch'));
        }
        if (payload.containsKey('destinationBranch')) {
            record.Destination_Branch__c =
                textValue(payload.get('destinationBranch'));
        }
        if (payload.containsKey('createdAt')) {
            record.Created_At__c = datetimeValue(payload.get('createdAt'));
        }
        if (payload.containsKey('completedAt')) {
            record.Completed_At__c = datetimeValue(payload.get('completedAt'));
        }
        if (payload.containsKey('schemaVersion')) {
            record.Schema_Version__c = textValue(payload.get('schemaVersion'));
        }
        if (payload.containsKey('snapshotVersion')) {
            record.Snapshot_Version__c =
                textValue(payload.get('snapshotVersion'));
        }
        if (payload.containsKey('overallIntegrityHash')) {
            record.Overall_Integrity_Hash__c =
                textValue(payload.get('overallIntegrityHash'));
        }
        if (payload.containsKey('rollbackEligible')) {
            record.Rollback_Eligible__c =
                boolValue(payload.get('rollbackEligible'));
        }
        if (payload.containsKey('captureFailureReason')) {
            record.Capture_Failure_Reason__c =
                textValue(payload.get('captureFailureReason'));
        }
        if (payload.containsKey('memberCount')) {
            record.Member_Count__c = decimalValue(payload.get('memberCount'));
        }
        if (payload.containsKey('status')) {
            String status = textValue(payload.get('status'));
            if (SNAPSHOT_STATUSES.contains(status) && status != STATUS_SEALED) {
                record.Status__c = status;
            } else if (status == STATUS_SEALED && !isUpdate) {
                record.Status__c = STATUS_CAPTURING;
            }
        }
    }

    private static Deployment_Snapshot__c getSnapshotRecord(String snapshotId) {
        if (String.isBlank(snapshotId)) {
            return null;
        }
        List<Deployment_Snapshot__c> rows = [
            SELECT
                Id,
                Snapshot_Id__c,
                Deployment_Id__c,
                Source_Org_Id__c,
                Destination_Org_Id__c,
                Source_Branch__c,
                Destination_Branch__c,
                Created_At__c,
                Completed_At__c,
                Sealed_At__c,
                Status__c,
                Schema_Version__c,
                Snapshot_Version__c,
                Overall_Integrity_Hash__c,
                Rollback_Eligible__c,
                Capture_Failure_Reason__c,
                Member_Count__c
            FROM Deployment_Snapshot__c
            WHERE Snapshot_Id__c = :snapshotId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Deployment_Snapshot_Member__c getMemberRecord(
        String memberKey
    ) {
        if (String.isBlank(memberKey)) {
            return null;
        }
        List<Deployment_Snapshot_Member__c> rows = [
            SELECT
                Id,
                Deployment_Snapshot__c,
                Member_Key__c,
                Metadata_Type__c,
                Metadata_Name__c,
                File_Path__c,
                Change_Class__c,
                Existed_Before__c,
                Destination_Before_Hash__c,
                Expected_After_Hash__c,
                Artifact_Id__c,
                Artifact_Size__c,
                Capture_Status__c,
                Content_Document_Id__c,
                Snapshot_Is_Sealed__c
            FROM Deployment_Snapshot_Member__c
            WHERE Member_Key__c = :memberKey
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static ControlPlaneResult sealedFailure() {
        return ControlPlaneResult.fail(
            'SEALED',
            'SEALED snapshots are immutable.'
        );
    }

    private static ControlPlaneResult unauthorized(String objectName) {
        return ControlPlaneResult.fail(
            'UNAUTHORIZED',
            'Insufficient access for ' + objectName + '.'
        );
    }

    private static ControlPlaneResult dmlFailure(
        DmlException e,
        String defaultField
    ) {
        String message = e == null ? 'Unable to save.' : e.getMessage();
        if (e != null && e.getNumDml() > 0 &&
            e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
            return ControlPlaneResult.fail(
                'DUPLICATE_VALUE',
                'Duplicate value rejected.',
                defaultField
            );
        }
        if (message != null && message.contains('SEALED')) {
            return sealedFailure();
        }
        return ControlPlaneResult.fail('INVALID_REQUEST', message, defaultField);
    }

    private static Boolean isCreateable(Schema.SObjectType typeRef) {
        return typeRef.getDescribe().isCreateable();
    }

    private static Boolean isUpdateable(Schema.SObjectType typeRef) {
        return typeRef.getDescribe().isUpdateable();
    }

    private static Boolean isReadable(Schema.SObjectType typeRef) {
        return typeRef.getDescribe().isAccessible();
    }

    private static String textValue(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Boolean boolValue(Object value) {
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return value != null && String.valueOf(value).toLowerCase() == 'true';
    }

    private static Decimal decimalValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static Datetime datetimeValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Datetime) {
            return (Datetime) value;
        }
        try {
            return (Datetime) JSON.deserialize(
                '"' + String.valueOf(value) + '"',
                Datetime.class
            );
        } catch (Exception e) {
            return null;
        }
    }

    private static String normalizePicklist(
        String value,
        Set<String> allowed,
        String fallback
    ) {
        if (String.isBlank(value) || !allowed.contains(value)) {
            return fallback;
        }
        return value;
    }
}