/**
 * Orchestrates durable Application Org persistence of Backend snapshotExport.
 * Reuses DeploymentSnapshotService and DeploymentSnapshotArtifactService only.
 */
public with sharing class SnapshotPersistenceService {

    public class PersistResult {
        public Boolean success;
        public String code;
        public String message;
        public String snapshotId;

        public Map<String, Object> toMap() {
            return new Map<String, Object>{
                'success' => success == true,
                'code' => code,
                'message' => message,
                'snapshotId' => snapshotId
            };
        }
    }

    private class ArtifactFetch {
        public String artifactId;
        public String metadataType;
        public String metadataName;
        public Blob bytes;
        public String destinationBeforeHash;
    }

    /**
     * Parses a deployment validate response and persists snapshotExport when present.
     * Returns the original response enriched with snapshotPersistence when applicable.
     */
    public static String applyToDeploymentResponse(String responseBody) {
        if (String.isBlank(responseBody)) {
            return responseBody;
        }

        Map<String, Object> parsed;

        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        } catch (Exception e) {
            return responseBody;
        }

        if (
            parsed == null ||
            !parsed.containsKey('snapshotExport') ||
            parsed.get('snapshotExport') == null
        ) {
            return responseBody;
        }

        String historyId = resolveHistoryId(parsed);
        PersistResult result = persistSnapshotExport(
            JSON.serialize(parsed.get('snapshotExport')),
            historyId
        );
        parsed.put('snapshotPersistence', result.toMap());
        return JSON.serialize(parsed);
    }

    /**
     * Persists a Backend snapshotExport payload into Application Org records.
     */
    public static PersistResult persistSnapshotExport(
        String snapshotExportJson,
        String historyId
    ) {
        PersistResult result = new PersistResult();
        result.success = false;

        if (String.isBlank(snapshotExportJson)) {
            result.code = 'SNAPSHOT_EXPORT_MISSING';
            result.message = 'snapshotExport is required.';
            return result;
        }

        Map<String, Object> snapshotExport;

        try {
            snapshotExport = (Map<String, Object>) JSON.deserializeUntyped(
                snapshotExportJson
            );
        } catch (Exception e) {
            result.code = 'SNAPSHOT_EXPORT_INVALID';
            result.message = 'snapshotExport JSON is invalid.';
            return result;
        }

        String snapshotId;
        List<Object> membersRaw;
        Integer memberCount;

        ValidationFailure validationFailure = validateExportShape(snapshotExport);
        if (validationFailure != null) {
            result.code = validationFailure.code;
            result.message = validationFailure.detail;
            return result;
        }

        snapshotId = text(snapshotExport.get('snapshotId'));
        memberCount = integerValue(snapshotExport.get('memberCount'));
        membersRaw = (List<Object>) snapshotExport.get('members');

        result.snapshotId = snapshotId;

        if (!DeploymentSnapshotService.STATUS_SEALED.equals(
            String.valueOf(snapshotExport.get('status')).trim()
        )) {
            result.code = 'SNAPSHOT_STATUS_INVALID';
            result.message =
                'snapshotExport must have status SEALED before persistence.';
            return result;
        }

        if (membersRaw.size() != memberCount) {
            result.code = 'SNAPSHOT_MEMBER_COUNT_MISMATCH';
            result.message = 'memberCount does not match members length.';
            return result;
        }

        String resolvedHistoryId = resolveHistoryId(snapshotExport, historyId);
        PersistResult idempotent = handleExistingSealedSnapshot(snapshotExport, snapshotId);
        if (idempotent != null) {
            correlateSnapshotHistory(resolvedHistoryId, snapshotId);
            return idempotent;
        }

        List<Map<String, Object>> members = new List<Map<String, Object>>();
        List<ArtifactFetch> artifactFetches = new List<ArtifactFetch>();

        for (Object memberObj : membersRaw) {
            if (!(memberObj instanceof Map<String, Object>)) {
                result.code = 'SNAPSHOT_MEMBER_INVALID';
                result.message = 'Each snapshot member must be an object.';
                return result;
            }

            Map<String, Object> member = (Map<String, Object>) memberObj;
            String validationError = validateMember(member, snapshotId);

            if (validationError != null) {
                result.code = 'SNAPSHOT_MEMBER_INVALID';
                result.message = validationError;
                return result;
            }

            members.add(member);

            if (isModifiedMember(member) && hasArtifactId(member)) {
                ArtifactFetch fetch = new ArtifactFetch();
                fetch.artifactId = text(member.get('artifactId'));
                fetch.metadataType = text(member.get('metadataType'));
                fetch.metadataName = text(member.get('metadataName'));
                fetch.destinationBeforeHash = text(
                    member.get('destinationBeforeHash')
                );
                artifactFetches.add(fetch);
            }
        }

        for (ArtifactFetch fetch : artifactFetches) {
            BlobFetchOutcome fetchOutcome = fetchArtifactBytes(
                snapshotId,
                fetch.artifactId,
                resolvedHistoryId
            );

            if (!fetchOutcome.success) {
                result.code = fetchOutcome.code;
                result.message = fetchOutcome.message;
                return result;
            }

            fetch.bytes = fetchOutcome.bytes;

            if (!hashMatches(fetch.bytes, fetch.destinationBeforeHash)) {
                result.code = 'SNAPSHOT_INTEGRITY_MISMATCH';
                result.message =
                    'Artifact bytes do not match destinationBeforeHash for ' +
                    fetch.metadataType +
                    ':' +
                    fetch.metadataName +
                    '.';
                return result;
            }
        }

        Boolean createdSnapshot = false;

        try {
            ControlPlaneResult created = DeploymentSnapshotService.createSnapshot(
                buildSnapshotPayload(snapshotExport, snapshotId, false)
            );

            if (created.success != true) {
                if (created.code == 'DUPLICATE_VALUE') {
                    PersistResult duplicate = handleExistingSealedSnapshot(
                        snapshotExport,
                        snapshotId
                    );
                    if (duplicate != null) {
                        correlateSnapshotHistory(resolvedHistoryId, snapshotId);
                        return duplicate;
                    }
                }

                result.code = created.code != null
                    ? created.code
                    : 'SNAPSHOT_CREATE_FAILED';
                result.message = created.message != null
                    ? created.message
                    : 'Unable to create deployment snapshot.';
                return result;
            }

            createdSnapshot = true;

            for (ArtifactFetch fetch : artifactFetches) {
                ControlPlaneResult stored =
                    DeploymentSnapshotArtifactService.storeArtifactById(
                        snapshotId,
                        fetch.artifactId,
                        fetch.bytes
                    );

                if (stored.success != true) {
                    markSnapshotFailed(
                        snapshotId,
                        stored.message != null
                            ? stored.message
                            : 'Artifact persistence failed.'
                    );
                    result.code = stored.code != null
                        ? stored.code
                        : 'SNAPSHOT_ARTIFACT_STORE_FAILED';
                    result.message = stored.message;
                    return result;
                }
            }

            for (Map<String, Object> member : members) {
                ControlPlaneResult added = DeploymentSnapshotService.addMember(
                    snapshotId,
                    buildMemberPayload(member)
                );

                if (added.success != true) {
                    markSnapshotFailed(
                        snapshotId,
                        added.message != null
                            ? added.message
                            : 'Snapshot member persistence failed.'
                    );
                    result.code = added.code != null
                        ? added.code
                        : 'SNAPSHOT_MEMBER_PERSIST_FAILED';
                    result.message = added.message;
                    return result;
                }
            }

            if (!integrityEligible(snapshotExport)) {
                markSnapshotFailed(
                    snapshotId,
                    'Snapshot export is not rollback eligible or integrity metadata is incomplete.'
                );
                result.code = 'SNAPSHOT_INTEGRITY_MISMATCH';
                result.message =
                    'Snapshot export failed integrity eligibility checks.';
                return result;
            }

            ControlPlaneResult sealed =
                DeploymentSnapshotService.sealSnapshot(snapshotId);

            if (sealed.success != true) {
                markSnapshotFailed(
                    snapshotId,
                    sealed.message != null
                        ? sealed.message
                        : 'Unable to seal deployment snapshot.'
                );
                result.code = sealed.code != null
                    ? sealed.code
                    : 'SNAPSHOT_SEAL_FAILED';
                result.message = sealed.message;
                return result;
            }

            Deployment_Snapshot__c sealedRecord =
                (Deployment_Snapshot__c) sealed.record;

            if (
                text(snapshotExport.get('overallIntegrityHash')) !=
                sealedRecord.Overall_Integrity_Hash__c
            ) {
                markSnapshotFailed(
                    snapshotId,
                    'Persisted overallIntegrityHash does not match snapshot export.'
                );
                result.code = 'SNAPSHOT_INTEGRITY_MISMATCH';
                result.message =
                    'Persisted snapshot integrity hash does not match export.';
                return result;
            }

            if (
                snapshotExport.get('rollbackEligible') == true &&
                sealedRecord.Rollback_Eligible__c != true
            ) {
                markSnapshotFailed(
                    snapshotId,
                    'Persisted snapshot is not rollback eligible.'
                );
                result.code = 'SNAPSHOT_INTEGRITY_MISMATCH';
                result.message =
                    'Snapshot export declared rollbackEligible but persisted snapshot is not eligible.';
                return result;
            }

            correlateSnapshotHistory(resolvedHistoryId, snapshotId);

            result.success = true;
            result.code = 'PERSISTED';
            result.message = 'Deployment snapshot persisted.';
            return result;
        } catch (Exception e) {
            if (createdSnapshot) {
                markSnapshotFailed(
                    snapshotId,
                    e.getMessage() != null
                        ? e.getMessage()
                        : 'Unexpected snapshot persistence failure.'
                );
            }

            result.code = 'SNAPSHOT_PERSISTENCE_ERROR';
            result.message =
                e.getMessage() != null
                    ? e.getMessage()
                    : 'Unexpected snapshot persistence failure.';
            return result;
        }
    }

    private class BlobFetchOutcome {
        public Boolean success;
        public String code;
        public String message;
        public Blob bytes;
    }

    private class ValidationFailure {
        public String code;
        public String detail;
    }

    private static ValidationFailure validateExportShape(
        Map<String, Object> snapshotExport
    ) {
        if (String.isBlank(text(snapshotExport.get('snapshotId')))) {
            return failure(
                'SNAPSHOT_EXPORT_INVALID',
                'snapshotId is required.'
            );
        }

        if (String.isBlank(text(snapshotExport.get('status')))) {
            return failure(
                'SNAPSHOT_EXPORT_INVALID',
                'status is required.'
            );
        }

        Integer memberCount = integerValue(snapshotExport.get('memberCount'));
        if (memberCount == null) {
            return failure(
                'SNAPSHOT_MEMBER_COUNT_INVALID',
                'memberCount is required.'
            );
        }

        if (!(snapshotExport.get('members') instanceof List<Object>)) {
            return failure(
                'SNAPSHOT_MEMBERS_INVALID',
                'members must be an array.'
            );
        }

        return null;
    }

    private static ValidationFailure failure(String code, String detail) {
        ValidationFailure failure = new ValidationFailure();
        failure.code = code;
        failure.detail = detail;
        return failure;
    }

    private static PersistResult handleExistingSealedSnapshot(
        Map<String, Object> snapshotExport,
        String snapshotId
    ) {
        ControlPlaneResult existing =
            DeploymentSnapshotService.getSnapshot(snapshotId);

        if (existing.success != true || existing.record == null) {
            return null;
        }

        Deployment_Snapshot__c record =
            (Deployment_Snapshot__c) existing.record;

        if (record.Status__c != DeploymentSnapshotService.STATUS_SEALED) {
            return null;
        }

        if (
            text(snapshotExport.get('overallIntegrityHash')) !=
            record.Overall_Integrity_Hash__c
        ) {
            PersistResult conflict = new PersistResult();
            conflict.success = false;
            conflict.code = 'SNAPSHOT_INTEGRITY_MISMATCH';
            conflict.message =
                'Existing sealed snapshot integrity hash does not match export.';
            conflict.snapshotId = snapshotId;
            return conflict;
        }

        Integer expectedCount = integerValue(snapshotExport.get('memberCount'));
        ControlPlaneResult members =
            DeploymentSnapshotService.getMembers(snapshotId);

        if (
            members.success != true ||
            members.records == null ||
            members.records.size() != expectedCount
        ) {
            PersistResult conflict = new PersistResult();
            conflict.success = false;
            conflict.code = 'SNAPSHOT_MEMBER_COUNT_MISMATCH';
            conflict.message =
                'Existing sealed snapshot member count does not match export.';
            conflict.snapshotId = snapshotId;
            return conflict;
        }

        PersistResult ok = new PersistResult();
        ok.success = true;
        ok.code = 'ALREADY_PERSISTED';
        ok.message = 'Deployment snapshot already persisted.';
        ok.snapshotId = snapshotId;
        return ok;
    }

    private static Map<String, Object> buildSnapshotPayload(
        Map<String, Object> snapshotExport,
        String snapshotId,
        Boolean includeSealedStatus
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'snapshotId' => snapshotId,
            'deploymentId' => snapshotExport.get('deploymentId'),
            'sourceOrgId' => snapshotExport.get('sourceOrgId'),
            'destinationOrgId' => snapshotExport.get('destinationOrgId'),
            'sourceBranch' => snapshotExport.get('sourceBranch'),
            'destinationBranch' => snapshotExport.get('destinationBranch'),
            'createdAt' => snapshotExport.get('createdAt'),
            'completedAt' => snapshotExport.get('completedAt'),
            'schemaVersion' => snapshotExport.get('schemaVersion'),
            'snapshotVersion' => snapshotExport.get('snapshotVersion'),
            'overallIntegrityHash' => snapshotExport.get('overallIntegrityHash'),
            'rollbackEligible' => snapshotExport.get('rollbackEligible'),
            'captureFailureReason' => snapshotExport.get('captureFailureReason'),
            'memberCount' => snapshotExport.get('memberCount'),
            'status' => includeSealedStatus == true
                ? snapshotExport.get('status')
                : DeploymentSnapshotService.STATUS_CAPTURING
        };
        return payload;
    }

    private static Map<String, Object> buildMemberPayload(
        Map<String, Object> member
    ) {
        return new Map<String, Object>{
            'metadataType' => member.get('metadataType'),
            'metadataName' => member.get('metadataName'),
            'filePath' => member.get('filePath'),
            'changeClass' => member.get('changeClass'),
            'existedBefore' => member.get('existedBefore'),
            'destinationBeforeHash' => member.get('destinationBeforeHash'),
            'expectedAfterHash' => member.get('expectedAfterHash'),
            'artifactId' => member.get('artifactId'),
            'artifactSize' => member.get('artifactSize'),
            'captureStatus' => mapCaptureStatus(
                text(member.get('captureStatus'))
            )
        };
    }

    private static BlobFetchOutcome fetchArtifactBytes(
        String snapshotId,
        String artifactId,
        String historyId
    ) {
        BlobFetchOutcome outcome = new BlobFetchOutcome();
        outcome.success = false;

        ControlPlaneResult validation =
            DeploymentSnapshotArtifactService.validateArtifactId(
                snapshotId,
                artifactId
            );

        if (validation.success != true) {
            outcome.code = validation.code != null
                ? validation.code
                : 'SNAPSHOT_ARTIFACT_INVALID';
            outcome.message = validation.message;
            return outcome;
        }

        if (String.isBlank(historyId)) {
            outcome.code = 'SNAPSHOT_HISTORY_ID_REQUIRED';
            outcome.message = 'historyId is required to fetch snapshot artifacts.';
            return outcome;
        }

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setTimeout(120000);
        req.setEndpoint(buildArtifactEndpoint(snapshotId, artifactId, historyId));

        Http http = new Http();
        HttpResponse res;

        try {
            res = http.send(req);
        } catch (Exception e) {
            outcome.code = 'SNAPSHOT_ARTIFACT_HTTP_ERROR';
            outcome.message = 'Unable to retrieve snapshot artifact from backend.';
            return outcome;
        }

        Integer statusCode = res.getStatusCode();

        if (statusCode == 404) {
            outcome.code = 'SNAPSHOT_ARTIFACT_NOT_FOUND';
            outcome.message = 'Snapshot artifact was not found on backend.';
            return outcome;
        }

        if (statusCode == 400) {
            outcome.code = 'SNAPSHOT_ARTIFACT_INVALID';
            outcome.message = 'Snapshot artifact request was rejected by backend.';
            return outcome;
        }

        if (statusCode == 503 || statusCode >= 500) {
            outcome.code = 'SNAPSHOT_ARTIFACT_UNAVAILABLE';
            outcome.message = 'Snapshot artifact is unavailable on backend.';
            return outcome;
        }

        if (statusCode < 200 || statusCode >= 300) {
            outcome.code = 'SNAPSHOT_ARTIFACT_HTTP_ERROR';
            outcome.message = 'Snapshot artifact request failed.';
            return outcome;
        }

        Blob bytes = res.getBodyAsBlob();

        if (bytes == null || bytes.size() == 0) {
            outcome.code = 'SNAPSHOT_ARTIFACT_EMPTY';
            outcome.message = 'Snapshot artifact response was empty.';
            return outcome;
        }

        if (bytes.size() >
            DeploymentSnapshotArtifactService.PRACTICAL_APEX_BYTE_LIMIT) {
            outcome.code = 'SNAPSHOT_ARTIFACT_TOO_LARGE';
            outcome.message =
                'Snapshot artifact exceeds the practical Apex byte limit.';
            return outcome;
        }

        outcome.success = true;
        outcome.bytes = bytes;
        return outcome;
    }

    private static String buildArtifactEndpoint(
        String snapshotId,
        String artifactId,
        String historyId
    ) {
        return System.Label.Backend_Base_URL +
            '/api/deployment/snapshot-artifact' +
            '?snapshotId=' +
            EncodingUtil.urlEncode(snapshotId, 'UTF-8') +
            '&artifactId=' +
            EncodingUtil.urlEncode(artifactId, 'UTF-8') +
            '&historyId=' +
            EncodingUtil.urlEncode(historyId, 'UTF-8');
    }

    private static void correlateSnapshotHistory(
        String historyId,
        String snapshotId
    ) {
        if (String.isBlank(historyId) || String.isBlank(snapshotId)) {
            return;
        }

        if (!Schema.sObjectType.Deployment_History__c.isAccessible() ||
            !Schema.sObjectType.Deployment_History__c.isUpdateable()) {
            return;
        }

        List<Deployment_History__c> rows = [
            SELECT Id, Snapshot_Id__c
            FROM Deployment_History__c
            WHERE Backend_History_Id__c = :historyId
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            return;
        }

        if (
            String.isNotBlank(rows[0].Snapshot_Id__c) &&
            rows[0].Snapshot_Id__c != snapshotId
        ) {
            return;
        }

        if (rows[0].Snapshot_Id__c == snapshotId) {
            return;
        }

        rows[0].Snapshot_Id__c = snapshotId;
        update rows[0];
    }

    private static void markSnapshotFailed(
        String snapshotId,
        String reason
    ) {
        if (String.isBlank(snapshotId)) {
            return;
        }

        DeploymentSnapshotService.updateSnapshot(
            snapshotId,
            new Map<String, Object>{
                'status' => DeploymentSnapshotService.STATUS_FAILED,
                'rollbackEligible' => false,
                'captureFailureReason' => truncateReason(reason)
            }
        );
    }

    private static Boolean integrityEligible(Map<String, Object> snapshotExport) {
        return String.isNotBlank(text(snapshotExport.get('overallIntegrityHash')));
    }

    private static String validateMember(
        Map<String, Object> member,
        String snapshotId
    ) {
        if (String.isBlank(text(member.get('metadataType')))) {
            return 'metadataType is required on each snapshot member.';
        }

        if (String.isBlank(text(member.get('metadataName')))) {
            return 'metadataName is required on each snapshot member.';
        }

        if (String.isBlank(text(member.get('changeClass')))) {
            return 'changeClass is required on each snapshot member.';
        }

        if (mapCaptureStatus(text(member.get('captureStatus'))) == null) {
            return 'captureStatus cannot be mapped for snapshot member.';
        }

        if (isModifiedMember(member)) {
            if (String.isBlank(text(member.get('destinationBeforeHash')))) {
                return 'destinationBeforeHash is required for MODIFIED members.';
            }

            if (String.isBlank(text(member.get('expectedAfterHash')))) {
                return 'expectedAfterHash is required for MODIFIED members.';
            }

            if (
                'COMPLETE'.equalsIgnoreCase(text(member.get('captureStatus'))) &&
                !hasArtifactId(member)
            ) {
                return 'artifactId is required for COMPLETE MODIFIED members.';
            }

            if (hasArtifactId(member)) {
                String artifactId = text(member.get('artifactId'));
                ControlPlaneResult validation =
                    DeploymentSnapshotArtifactService.validateArtifactId(
                        snapshotId,
                        artifactId
                    );

                if (validation.success != true) {
                    return validation.message;
                }
            }
        }

        return null;
    }

    private static Boolean isModifiedMember(Map<String, Object> member) {
        return 'MODIFIED'.equalsIgnoreCase(text(member.get('changeClass')));
    }

    private static Boolean hasArtifactId(Map<String, Object> member) {
        return String.isNotBlank(text(member.get('artifactId')));
    }

    private static Boolean hashMatches(Blob bytes, String expectedHash) {
        if (bytes == null || String.isBlank(expectedHash)) {
            return false;
        }

        Blob digest = Crypto.generateDigest('SHA-256', bytes);
        String actual = EncodingUtil.convertToHex(digest).toLowerCase();
        return actual == expectedHash.trim().toLowerCase();
    }

    private static String mapCaptureStatus(String nodeStatus) {
        if (String.isBlank(nodeStatus)) {
            return null;
        }

        if (nodeStatus == 'COMPLETE') {
            return 'CAPTURED';
        }

        if (nodeStatus == 'ABSENT_PROVEN') {
            return 'NOT_REQUIRED';
        }

        if (nodeStatus == 'UNKNOWN') {
            return 'SKIPPED';
        }

        if (nodeStatus == 'FAILED') {
            return 'FAILED';
        }

        if (nodeStatus == 'CAPTURED' ||
            nodeStatus == 'NOT_REQUIRED' ||
            nodeStatus == 'SKIPPED' ||
            nodeStatus == 'PENDING' ||
            nodeStatus == 'CAPTURING') {
            return nodeStatus;
        }

        return null;
    }

    private static String resolveHistoryId(Map<String, Object> parsed) {
        if (parsed == null) {
            return null;
        }

        if (parsed.containsKey('deploymentHistory') &&
            parsed.get('deploymentHistory') instanceof Map<String, Object>) {
            Map<String, Object> history =
                (Map<String, Object>) parsed.get('deploymentHistory');
            String historyId = text(history.get('historyId'));

            if (String.isNotBlank(historyId)) {
                return historyId;
            }
        }

        if (parsed.containsKey('snapshotExport') &&
            parsed.get('snapshotExport') instanceof Map<String, Object>) {
            Map<String, Object> snapshotExport =
                (Map<String, Object>) parsed.get('snapshotExport');
            return text(snapshotExport.get('deploymentId'));
        }

        return null;
    }

    private static String resolveHistoryId(
        Map<String, Object> snapshotExport,
        String historyId
    ) {
        if (String.isNotBlank(historyId)) {
            return historyId;
        }

        return text(snapshotExport.get('deploymentId'));
    }

    private static Integer integerValue(Object rawCount) {
        if (rawCount == null) {
            return null;
        }

        if (rawCount instanceof Integer) {
            return (Integer) rawCount;
        }

        if (rawCount instanceof Long) {
            return Integer.valueOf(String.valueOf(rawCount));
        }

        if (rawCount instanceof Decimal) {
            return ((Decimal) rawCount).intValue();
        }

        try {
            return Integer.valueOf(String.valueOf(rawCount));
        } catch (Exception e) {
            return null;
        }
    }

    private static String text(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static String truncateReason(String reason) {
        if (String.isBlank(reason)) {
            return 'Snapshot persistence failed.';
        }

        return reason.length() > 2000
            ? reason.substring(0, 2000)
            : reason;
    }
}