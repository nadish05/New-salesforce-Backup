/**
 * Aura-enabled rollback boundary for the migration product.
 * Reads sealed snapshot state from the Application Org and POSTs to Azure.
 * Does not modify snapshots, artifacts, or destination org credentials.
 */
public with sharing class DeploymentRollbackController {

    private static final Integer CALLOUT_TIMEOUT_MS = 120000;
    private static final String ROLLBACK_PATH = '/api/deployment/rollback';
    @TestVisible
    private static final Integer PRACTICAL_AGGREGATE_ARTIFACT_BYTE_LIMIT = 3000000;

    @AuraEnabled
    public static String executeRollback(
        String snapshotId,
        String historyId,
        String refreshToken,
        String instanceUrl,
        String orgId
    ) {
        try {
            if (String.isBlank(snapshotId)) {
                return failureJson('snapshotId is required.');
            }
            if (String.isBlank(refreshToken)) {
                return failureJson('refreshToken is required.');
            }
            if (String.isBlank(instanceUrl)) {
                return failureJson('instanceUrl is required.');
            }
            if (String.isBlank(orgId)) {
                return failureJson('orgId is required.');
            }

            String normalizedSnapshotId = snapshotId.trim();

            ControlPlaneResult snapshotResult =
                DeploymentSnapshotService.getSnapshot(normalizedSnapshotId);

            if (snapshotResult.success != true || snapshotResult.record == null) {
                return failureJson('Snapshot not found.');
            }

            Deployment_Snapshot__c snapshot =
                (Deployment_Snapshot__c) snapshotResult.record;

            if (snapshot.Status__c != DeploymentSnapshotService.STATUS_SEALED) {
                return failureJson('Snapshot is not eligible for rollback.');
            }

            if (snapshot.Rollback_Eligible__c != true) {
                return failureJson('Snapshot is not eligible for rollback.');
            }

            ControlPlaneResult membersResult =
                DeploymentSnapshotService.getMembers(normalizedSnapshotId);

            if (membersResult.success != true) {
                String message = String.isNotBlank(membersResult.message)
                    ? membersResult.message
                    : 'Unable to load snapshot members.';
                return failureJson(message);
            }

            HistoryResolution historyResolution = resolveHistoryId(
                normalizedSnapshotId,
                historyId,
                snapshot
            );

            if (historyResolution.error != null) {
                return failureJson(historyResolution.error);
            }

            Map<String, Object> snapshotExport = buildSnapshotExport(
                snapshot,
                membersResult.records
            );

            ArtifactMapResult artifactResult = buildArtifactsMap(
                normalizedSnapshotId,
                membersResult.records
            );

            if (artifactResult.error != null) {
                return failureJson(artifactResult.error);
            }

            Map<String, Object> payload = new Map<String, Object>{
                'historyId' => historyResolution.historyId,
                'refreshToken' => refreshToken,
                'instanceUrl' => instanceUrl,
                'orgId' => orgId,
                'snapshotId' => normalizedSnapshotId,
                'snapshotExport' => snapshotExport,
                'artifacts' => artifactResult.artifacts
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint(System.Label.Backend_Base_URL + ROLLBACK_PATH);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(payload));
            req.setTimeout(CALLOUT_TIMEOUT_MS);

            HttpResponse res = new Http().send(req);

            return normalizeHttpBody(res);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'DeploymentRollbackController.executeRollback failed: ' +
                e.getTypeName()
            );
            return failureJson('Unable to execute rollback.');
        }
    }

    private class HistoryResolution {
        public String historyId;
        public String error;
    }

    private class ArtifactMapResult {
        public Map<String, Object> artifacts;
        public String error;
    }

    @TestVisible
    private static HistoryResolution resolveHistoryId(
        String snapshotId,
        String suppliedHistoryId,
        Deployment_Snapshot__c snapshot
    ) {
        HistoryResolution resolution = new HistoryResolution();
        String trimmed = String.isBlank(suppliedHistoryId)
            ? null
            : suppliedHistoryId.trim();

        if (String.isNotBlank(trimmed)) {
            if (Schema.sObjectType.Deployment_History__c.isAccessible()) {
                List<Deployment_History__c> correlated = [
                    SELECT Id, Backend_History_Id__c, Snapshot_Id__c
                    FROM Deployment_History__c
                    WHERE Snapshot_Id__c = :snapshotId
                    AND Backend_History_Id__c = :trimmed
                    LIMIT 1
                ];

                if (!correlated.isEmpty()) {
                    resolution.historyId = trimmed;
                    return resolution;
                }

                List<Deployment_History__c> snapshotHistories = [
                    SELECT Id, Backend_History_Id__c, Snapshot_Id__c
                    FROM Deployment_History__c
                    WHERE Snapshot_Id__c = :snapshotId
                    AND Backend_History_Id__c != null
                    LIMIT 1
                ];

                if (
                    !snapshotHistories.isEmpty() &&
                    snapshotHistories[0].Backend_History_Id__c != trimmed
                ) {
                    resolution.error =
                        'historyId does not match the selected snapshot.';
                    return resolution;
                }
            }

            resolution.historyId = trimmed;
            return resolution;
        }

        DeploymentHistoryService.RecordResult historyResult =
            DeploymentHistoryService.findBySnapshotId(snapshotId);

        if (
            historyResult.success == true &&
            historyResult.record != null &&
            String.isNotBlank(historyResult.record.Backend_History_Id__c)
        ) {
            resolution.historyId = historyResult.record.Backend_History_Id__c;
            return resolution;
        }

        if (String.isNotBlank(snapshot.Deployment_Id__c)) {
            resolution.historyId = snapshot.Deployment_Id__c;
            return resolution;
        }

        resolution.error = 'historyId is required.';
        return resolution;
    }

    @TestVisible
    private static Map<String, Object> buildSnapshotExport(
        Deployment_Snapshot__c snapshot,
        List<SObject> memberRecords
    ) {
        List<Object> members = new List<Object>();

        if (memberRecords != null) {
            for (SObject memberObject : memberRecords) {
                Deployment_Snapshot_Member__c member =
                    (Deployment_Snapshot_Member__c) memberObject;
                members.add(buildMemberExport(member));
            }
        }

        Map<String, Object> exportPayload = new Map<String, Object>{
            'snapshotId' => snapshot.Snapshot_Id__c,
            'deploymentId' => snapshot.Deployment_Id__c,
            'sourceOrgId' => snapshot.Source_Org_Id__c,
            'destinationOrgId' => snapshot.Destination_Org_Id__c,
            'sourceBranch' => snapshot.Source_Branch__c,
            'destinationBranch' => snapshot.Destination_Branch__c,
            'createdAt' => formatIsoDatetime(snapshot.Created_At__c),
            'completedAt' => formatIsoDatetime(snapshot.Completed_At__c),
            'schemaVersion' => snapshot.Schema_Version__c,
            'snapshotVersion' => snapshot.Snapshot_Version__c,
            'overallIntegrityHash' => snapshot.Overall_Integrity_Hash__c,
            'rollbackEligible' => snapshot.Rollback_Eligible__c == true,
            'captureFailureReason' => snapshot.Capture_Failure_Reason__c,
            'memberCount' => members.size(),
            'status' => snapshot.Status__c,
            'members' => members
        };

        if (snapshot.Sealed_At__c != null) {
            exportPayload.put(
                'sealedAt',
                formatIsoDatetime(snapshot.Sealed_At__c)
            );
        }

        return exportPayload;
    }

    @TestVisible
    private static Map<String, Object> buildMemberExport(
        Deployment_Snapshot_Member__c member
    ) {
        Map<String, Object> memberPayload = new Map<String, Object>{
            'memberKey' => member.Member_Key__c,
            'metadataType' => member.Metadata_Type__c,
            'metadataName' => member.Metadata_Name__c,
            'filePath' => member.File_Path__c,
            'changeClass' => member.Change_Class__c,
            'existedBefore' => member.Existed_Before__c,
            'destinationBeforeHash' => member.Destination_Before_Hash__c,
            'expectedAfterHash' => member.Expected_After_Hash__c,
            'artifactId' => member.Artifact_Id__c,
            'artifactSize' => member.Artifact_Size__c,
            'captureStatus' => member.Capture_Status__c,
            'contentDocumentId' => member.Content_Document_Id__c
        };
        return memberPayload;
    }

    @TestVisible
    private static ArtifactMapResult buildArtifactsMap(
        String snapshotId,
        List<SObject> memberRecords
    ) {
        ArtifactMapResult result = new ArtifactMapResult();
        result.artifacts = new Map<String, Object>();
        Set<String> seenArtifactIds = new Set<String>();
        Integer aggregateBytes = 0;

        if (memberRecords == null) {
            return result;
        }

        for (SObject memberObject : memberRecords) {
            Deployment_Snapshot_Member__c member =
                (Deployment_Snapshot_Member__c) memberObject;

            if (!isModifiedMember(member)) {
                continue;
            }

            if (String.isBlank(member.Artifact_Id__c)) {
                result.error = artifactErrorMessage(
                    member,
                    'Artifact Id is required.'
                );
                return result;
            }

            if (String.isBlank(member.Content_Document_Id__c)) {
                result.error = artifactErrorMessage(
                    member,
                    'Artifact file is not associated.'
                );
                return result;
            }

            if (seenArtifactIds.contains(member.Artifact_Id__c)) {
                result.error = 'Duplicate artifact Id found in snapshot members.';
                return result;
            }
            seenArtifactIds.add(member.Artifact_Id__c);

            ControlPlaneResult bytesResult =
                DeploymentSnapshotArtifactService.getArtifactBytesById(
                    snapshotId,
                    member.Artifact_Id__c
                );

            if (bytesResult.success != true) {
                result.error = artifactErrorMessage(
                    member,
                    String.isNotBlank(bytesResult.message)
                        ? bytesResult.message
                        : 'Artifact file is not associated.'
                );
                return result;
            }

            Blob artifactBytes = bytesResult.artifactBytes;
            if (artifactBytes == null || artifactBytes.size() == 0) {
                result.error = artifactErrorMessage(
                    member,
                    'Artifact bytes are required.'
                );
                return result;
            }

            Integer blobSize = artifactBytes.size();
            if (blobSize >
                DeploymentSnapshotArtifactService.PRACTICAL_APEX_BYTE_LIMIT) {
                result.error = artifactErrorMessage(
                    member,
                    'Artifact exceeds the allowed size limit.'
                );
                return result;
            }

            if (
                member.Artifact_Size__c != null &&
                member.Artifact_Size__c.intValue() != blobSize
            ) {
                result.error = artifactErrorMessage(
                    member,
                    'Artifact size does not match snapshot member metadata.'
                );
                return result;
            }

            aggregateBytes += blobSize;
            if (aggregateBytes > PRACTICAL_AGGREGATE_ARTIFACT_BYTE_LIMIT) {
                result.error =
                    'Rollback artifacts exceed the allowed aggregate size limit.';
                return result;
            }

            if (
                bytesResult.contentDocumentId != null &&
                member.Content_Document_Id__c != bytesResult.contentDocumentId
            ) {
                result.error = artifactErrorMessage(
                    member,
                    'Artifact file is not associated.'
                );
                return result;
            }

            result.artifacts.put(
                member.Artifact_Id__c,
                new Map<String, Object>{
                    'contentBase64' => EncodingUtil.base64Encode(artifactBytes),
                    'size' => blobSize
                }
            );
        }

        return result;
    }

    @TestVisible
    private static Boolean isModifiedMember(
        Deployment_Snapshot_Member__c member
    ) {
        return member != null &&
            'MODIFIED'.equalsIgnoreCase(member.Change_Class__c);
    }

    private static String artifactErrorMessage(
        Deployment_Snapshot_Member__c member,
        String detail
    ) {
        return 'Unable to load rollback artifact for ' +
            member.Metadata_Type__c +
            ':' +
            member.Metadata_Name__c +
            '. ' +
            detail;
    }

    @TestVisible
    private static String formatIsoDatetime(Datetime value) {
        if (value == null) {
            return null;
        }
        return value.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    }

    @TestVisible
    private static String failureJson(String message) {
        return JSON.serialize(
            new Map<String, Object>{
                'success' => false,
                'error' => message
            }
        );
    }

    @TestVisible
    private static String normalizeHttpBody(HttpResponse res) {
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            return res.getBody();
        }

        String body = res.getBody();

        if (String.isNotBlank(body)) {
            return body;
        }

        return JSON.serialize(
            new Map<String, Object>{
                'success' => false,
                'statusCode' => res.getStatusCode(),
                'error' => res.getStatus()
            }
        );
    }
}