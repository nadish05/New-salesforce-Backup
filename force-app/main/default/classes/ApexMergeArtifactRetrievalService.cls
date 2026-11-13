/**
 * Retrieves sealed Apex merge artifacts from the backend and persists them as Salesforce Files.
 * Does not update deployment plan manifests or expose credentials to LWC.
 */
public with sharing class ApexMergeArtifactRetrievalService {
    private static final String SESSIONS_PATH = '/api/merge/apex/sessions';
    private static final Integer LONG_TIMEOUT_MS = 120000;

    /**
     * Synchronous path processes at most one unit (cls + metaXml) to bound heap.
     * Multiple units are processed through ApexMergeArtifactRetrievalQueueable.
     */
    public static final Integer MAX_UNITS_PER_SYNCHRONOUS_REQUEST = 1;

    /**
     * One queueable job per unit, each enqueueing at most one successor.
     * Salesforce allows at most five chained queueable jobs in a single chain (platform limit).
     */
    public static final Integer MAX_UNITS_PER_ASYNC_CHAIN = 5;

    /**
     * Sync descriptor-byte budget (cls + metaXml manifest byteLength sum).
     * 6 MB Apex heap must cover two downloaded blobs, HTTP buffers, digest work, and ContentVersion DML.
     * 1 MiB keeps ~4+ MB headroom for platform overhead on realistic merge units.
     */
    public static final Integer MAX_SYNC_UNIT_DESCRIPTOR_BYTES = 1048576;

    /**
     * Async/queueable descriptor-byte budget per unit (still below practical per-artifact limits).
     */
    public static final Integer MAX_ASYNC_UNIT_DESCRIPTOR_BYTES = 5000000;

    /**
     * Stop processing before a manifest-provided session deadline (authorize + 2 GETs + DML).
     */
    @TestVisible
    private static final Long SESSION_EXPIRY_BUFFER_MS = 120000;

    public class ChainFailureRecord {
        public String mergeSessionId;
        public String mergeManifestId;
        public Id deploymentPlanId;
        public Integer unitIndex;
        public String code;
        public String message;
        public Boolean partialChain;
    }

    @TestVisible
    private static ChainFailureRecord lastChainFailure;

    private static final Set<String> FORBIDDEN_MANIFEST_ROOT_KEYS = new Set<String>{
        'artifacts',
        'classes',
        'entries',
        'mergedClasses'
    };

    public class ArtifactDescriptor {
        public String artifactId;
        public String metadataName;
        public String role;
        public String sha256;
        public Integer byteLength;
    }

    public class ManifestUnit {
        public String metadataName;
        public List<ArtifactDescriptor> descriptors;
    }

    public class ManifestParseResult {
        public Boolean success;
        public String code;
        public String message;
        public String mergeManifestId;
        public List<ManifestUnit> units;
    }

    @TestVisible
    private static Integer lastInvokedCalloutCount;

    @TestVisible
    private static String lastEnqueuedStatusRunId;

    @TestVisible
    private static Boolean blockQueuedStatusPersistForTest;

    @TestVisible
    private static Boolean blockQueuedUnitStatusPersistForTest;

    @TestVisible
    private static Boolean blockSuccessorEnqueueForTest;

    @TestVisible
    private static final String CODE_RUN_TERMINATED = 'RUN_TERMINATED';
    @TestVisible
    private static final String CODE_RUN_IN_PROGRESS = 'RUN_IN_PROGRESS';
    @TestVisible
    private static final String CODE_STATUS_STORE_AMBIGUOUS =
        'STATUS_STORE_AMBIGUOUS';
    @TestVisible
    private static final String CODE_INVALID_STORED_STATUS =
        'INVALID_STORED_STATUS';
    @TestVisible
    private static final String CODE_STATUS_STORE_MISMATCH =
        'STATUS_STORE_MISMATCH';

    private class AsyncAcceptanceInspection {
        public Boolean failClosed;
        public String failCode;
        public String failMessage;
        public Boolean blankDurableState;
        public Boolean terminal;
        public Boolean active;
        public ApexMergeArtifactStatusService.StatusSnapshot snapshot;
    }

    private class RunOwnershipExpectation {
        public Id comparisonId;
        public Id deploymentPlanId;
        public String mergeSessionId;
        public String mergeManifestId;
        public String statusRunId;
    }

    private class RunOwnershipInspection {
        public Boolean ownershipValid;
        public Boolean failClosed;
        public String failCode;
        public String failMessage;
        public ApexMergeArtifactStatusService.StatusSnapshot snapshot;
    }

    private class SyncPersistGateResult {
        public Boolean allowPersist;
        public Boolean failClosed;
        public String failCode;
        public String failMessage;
    }

    private class UnitRetrievalOutcome {
        public Boolean success;
        public String code;
        public String message;
        public String failedArtifactId;
        public String failedMetadataName;
        public List<RetrievedArtifact> retrieved;
    }

    /**
     * @return JSON envelope with success, persistedArtifacts, or error fields. No raw blobs.
     */
    public static String retrieveAndPersist(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String sealedManifestJson
    ) {
        lastInvokedCalloutCount = 0;

        if (String.isBlank(mergeSessionId)) {
            return failureEnvelope(
                'INVALID_REQUEST',
                'mergeSessionId is required.',
                null,
                null,
                null,
                deploymentPlanId,
                mergeSessionId,
                null
            );
        }
        if (String.isBlank(sealedManifestJson)) {
            return failureEnvelope(
                'INVALID_REQUEST',
                'sealedManifestJson is required.',
                null,
                null,
                null,
                deploymentPlanId,
                mergeSessionId.trim(),
                null
            );
        }

        Map<String, Object> manifest;
        try {
            manifest = (Map<String, Object>) JSON.deserializeUntyped(
                sealedManifestJson
            );
        } catch (Exception e) {
            return failureEnvelope(
                'INVALID_REQUEST',
                'sealedManifestJson is not valid JSON.',
                null,
                null,
                null,
                deploymentPlanId,
                mergeSessionId.trim(),
                null
            );
        }

        ManifestParseResult parsedManifest = parseCanonicalManifest(manifest);
        if (parsedManifest.success != true) {
            return failureEnvelope(
                parsedManifest.code,
                parsedManifest.message,
                null,
                null,
                parsedManifest.mergeManifestId,
                deploymentPlanId,
                mergeSessionId.trim(),
                null
            );
        }

        String mergeManifestId = parsedManifest.mergeManifestId;
        List<ManifestUnit> units = parsedManifest.units;

        String manifestSessionId = textValue(manifest.get('mergeSessionId'));
        if (
            String.isNotBlank(manifestSessionId) &&
            manifestSessionId != mergeSessionId.trim()
        ) {
            return failureEnvelope(
                'INVALID_REQUEST',
                'mergeSessionId does not match the sealed manifest.',
                null,
                null,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId.trim(),
                null
            );
        }

        DestinationContext destination;
        try {
            destination = loadAndValidateDestination(
                comparisonId,
                deploymentPlanId
            );
        } catch (AuraHandledException e) {
            return failureEnvelope(
                'INVALID_REQUEST',
                e.getMessage(),
                null,
                null,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId.trim(),
                null
            );
        }

        if (units.size() > MAX_UNITS_PER_ASYNC_CHAIN) {
            return failureEnvelope(
                'INVALID_REQUEST',
                'Manifest unit count exceeds the supported processing limit of ' +
                    String.valueOf(MAX_UNITS_PER_ASYNC_CHAIN) +
                    '.',
                null,
                null,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId.trim(),
                null
            );
        }

        if (requiresAsyncProcessing(units)) {
            if (isBackendSessionExpired(resolveSessionExpiresAtMs(manifest))) {
                return failureEnvelope(
                    'EXPIRED',
                    'Merge session is no longer available on the backend.',
                    null,
                    null,
                    mergeManifestId,
                    deploymentPlanId,
                    mergeSessionId.trim(),
                    null
                );
            }
            return enqueueAsyncProcessing(
                comparisonId,
                deploymentPlanId,
                mergeSessionId.trim(),
                sealedManifestJson,
                mergeManifestId,
                units,
                manifest
            );
        }

        UnitRetrievalOutcome retrieval = retrieveManifestUnitBytes(
            comparisonId,
            deploymentPlanId,
            mergeSessionId.trim(),
            mergeManifestId,
            units[0],
            destination,
            true,
            MAX_SYNC_UNIT_DESCRIPTOR_BYTES,
            resolveSessionExpiresAtMs(manifest)
        );
        if (retrieval.success != true) {
            return failureEnvelope(
                retrieval.code,
                retrieval.message,
                null,
                retrieval.failedArtifactId,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId.trim(),
                retrieval.failedMetadataName
            );
        }

        Deployment_Plan__c lockedPlan =
            lockDeploymentPlanForMutation(deploymentPlanId);
        if (lockedPlan == null) {
            return failureEnvelope(
                'NOT_FOUND',
                'Deployment plan was not found.',
                null,
                null,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId.trim(),
                null
            );
        }

        SyncPersistGateResult syncGate =
            inspectDurableStateForSyncPersist(lockedPlan);
        if (syncGate.failClosed == true) {
            return failureEnvelope(
                syncGate.failCode,
                syncGate.failMessage,
                null,
                null,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId.trim(),
                null
            );
        }
        if (syncGate.allowPersist != true) {
            return failureEnvelope(
                CODE_RUN_IN_PROGRESS,
                'An artifact retrieval run is already in progress for this deployment plan.',
                null,
                null,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId.trim(),
                null
            );
        }

        UnitProcessingOutcome outcome = persistRetrievedUnitArtifacts(
            deploymentPlanId,
            mergeManifestId,
            units[0],
            retrieval.retrieved
        );
        if (outcome.success != true) {
            return failureEnvelope(
                outcome.code,
                outcome.message,
                outcome.persistedArtifacts,
                outcome.failedArtifactId,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId.trim(),
                outcome.failedMetadataName
            );
        }

        return successEnvelope(
            mergeSessionId.trim(),
            mergeManifestId,
            deploymentPlanId,
            outcome.persistedArtifacts
        );
    }

    /**
     * Queueable entry: one manifest unit per execution, chained for remaining units.
     */
    public static void processQueuedUnit(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String sealedManifestJson,
        Integer unitIndex
    ) {
        processQueuedUnit(
            comparisonId,
            deploymentPlanId,
            mergeSessionId,
            sealedManifestJson,
            unitIndex,
            null
        );
    }

    public static void processQueuedUnit(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String sealedManifestJson,
        Integer unitIndex,
        String statusRunId
    ) {
        lastInvokedCalloutCount = 0;
        if (
            unitIndex == null ||
            unitIndex < 0 ||
            String.isBlank(sealedManifestJson) ||
            String.isBlank(mergeSessionId) ||
            String.isBlank(statusRunId)
        ) {
            return;
        }

        Map<String, Object> manifest;
        try {
            manifest = (Map<String, Object>) JSON.deserializeUntyped(
                sealedManifestJson
            );
        } catch (Exception e) {
            return;
        }

        ManifestParseResult parsedManifest = parseCanonicalManifest(manifest);
        if (
            parsedManifest.success != true ||
            parsedManifest.units == null ||
            unitIndex >= parsedManifest.units.size()
        ) {
            return;
        }

        ManifestUnit currentUnit = parsedManifest.units[unitIndex];
        RunOwnershipExpectation expected = buildRunOwnershipExpectation(
            comparisonId,
            deploymentPlanId,
            mergeSessionId.trim(),
            parsedManifest.mergeManifestId,
            statusRunId
        );

        RunOwnershipInspection preOwnership =
            inspectRunOwnershipReadOnly(deploymentPlanId, expected);
        if (preOwnership.ownershipValid != true) {
            return;
        }

        if (isBackendSessionExpired(resolveSessionExpiresAtMs(manifest))) {
            recordChainFailure(
                mergeSessionId.trim(),
                parsedManifest.mergeManifestId,
                deploymentPlanId,
                unitIndex,
                'EXPIRED',
                'Merge session is no longer available on the backend.',
                unitIndex > 0
            );
            persistHandledQueuedFailureUnderLock(
                deploymentPlanId,
                expected,
                unitIndex,
                currentUnit,
                'EXPIRED',
                'Merge session is no longer available on the backend.',
                null,
                null
            );
            return;
        }

        DestinationContext destination;
        try {
            destination = loadAndValidateDestination(
                comparisonId,
                deploymentPlanId
            );
        } catch (Exception e) {
            recordChainFailure(
                mergeSessionId.trim(),
                parsedManifest.mergeManifestId,
                deploymentPlanId,
                unitIndex,
                'INVALID_REQUEST',
                'Destination validation failed during queued processing.',
                unitIndex > 0
            );
            persistHandledQueuedFailureUnderLock(
                deploymentPlanId,
                expected,
                unitIndex,
                currentUnit,
                'INVALID_REQUEST',
                'Destination validation failed during queued processing.',
                null,
                null
            );
            return;
        }

        UnitRetrievalOutcome retrieval = retrieveManifestUnitBytes(
            comparisonId,
            deploymentPlanId,
            mergeSessionId.trim(),
            parsedManifest.mergeManifestId,
            currentUnit,
            destination,
            true,
            MAX_ASYNC_UNIT_DESCRIPTOR_BYTES,
            resolveSessionExpiresAtMs(manifest)
        );

        Deployment_Plan__c lockedPlan =
            lockDeploymentPlanForMutation(deploymentPlanId);
        if (lockedPlan == null) {
            return;
        }

        RunOwnershipInspection postOwnership =
            inspectRunOwnershipOnLockedRow(lockedPlan, expected);
        if (postOwnership.ownershipValid != true) {
            return;
        }

        if (blockQueuedUnitStatusPersistForTest == true) {
            throw new AuraHandledException(
                'Queued artifact unit status persistence is unavailable.'
            );
        }

        Integer unitCount = parsedManifest.units.size();
        Boolean isFinalUnit = unitIndex == unitCount - 1;
        UnitProcessingOutcome outcome;

        if (retrieval.success != true) {
            outcome = mapRetrievalFailureToUnitOutcome(retrieval);
        } else {
            outcome = persistRetrievedUnitArtifacts(
                deploymentPlanId,
                parsedManifest.mergeManifestId,
                currentUnit,
                retrieval.retrieved
            );
        }

        if (outcome.success != true) {
            recordChainFailure(
                mergeSessionId.trim(),
                parsedManifest.mergeManifestId,
                deploymentPlanId,
                unitIndex,
                outcome.code,
                outcome.message,
                unitIndex > 0 ||
                    (outcome.persistedArtifacts != null &&
                        !outcome.persistedArtifacts.isEmpty())
            );
            String failedRole = resolveFailedArtifactRole(
                currentUnit,
                outcome
            );
            persistHandledQueuedFailureOnLockedPlan(
                lockedPlan,
                expected,
                unitIndex,
                currentUnit,
                outcome.code,
                outcome.message,
                failedRole,
                outcome.persistedArtifacts
            );
            return;
        }

        ApexMergeArtifactStatusService.StatusSnapshot persistedSnapshot =
            persistSuccessfulUnitStatusOnLockedPlan(
                lockedPlan,
                unitIndex,
                currentUnit,
                outcome,
                isFinalUnit,
                statusRunId
            );

        Integer nextIndex = unitIndex + 1;
        if (nextIndex < unitCount) {
            if (isBackendSessionExpired(resolveSessionExpiresAtMs(manifest))) {
                recordChainFailure(
                    mergeSessionId.trim(),
                    parsedManifest.mergeManifestId,
                    deploymentPlanId,
                    nextIndex,
                    'EXPIRED',
                    'Merge session expired before remaining units could be processed.',
                    true
                );
                applyTerminalChainInterruptToSnapshot(
                    persistedSnapshot,
                    nextIndex,
                    'EXPIRED',
                    'Merge session expired before remaining units could be processed.',
                    null
                );
                persistQueuedStatusSnapshotOrThrow(
                    lockedPlan,
                    persistedSnapshot,
                    statusRunId
                );
                return;
            }
            if (blockSuccessorEnqueueForTest == true) {
                throw new AuraHandledException(
                    'Successor queueable enqueue is unavailable.'
                );
            }
            lastEnqueuedStatusRunId = persistedSnapshot.statusRunId;
            System.enqueueJob(
                new ApexMergeArtifactRetrievalQueueable(
                    comparisonId,
                    deploymentPlanId,
                    mergeSessionId,
                    sealedManifestJson,
                    nextIndex,
                    persistedSnapshot.statusRunId
                )
            );
            return;
        }

        lastChainFailure = null;
    }

    @TestVisible
    private static ManifestParseResult parseCanonicalManifest(
        Map<String, Object> manifest
    ) {
        ManifestParseResult result = new ManifestParseResult();
        if (manifest == null) {
            result.success = false;
            result.code = 'INVALID_REQUEST';
            result.message = 'sealedManifestJson is required.';
            return result;
        }

        for (String forbiddenKey : FORBIDDEN_MANIFEST_ROOT_KEYS) {
            if (manifest.containsKey(forbiddenKey)) {
                result.success = false;
                result.code = 'UNSUPPORTED_MANIFEST';
                result.message =
                    'Manifest structure is not supported. Use apexMergeManifest.units[].';
                result.mergeManifestId = resolveMergeManifestId(manifest);
                return result;
            }
        }

        String mergeManifestId = resolveMergeManifestId(manifest);
        if (String.isBlank(mergeManifestId)) {
            result.success = false;
            result.code = 'INVALID_REQUEST';
            result.message = 'mergeManifestId is required in the sealed manifest.';
            return result;
        }

        Object unitRows = manifest.get('units');
        if (!(unitRows instanceof List<Object>)) {
            result.success = false;
            result.code = 'INVALID_REQUEST';
            result.message = 'apexMergeManifest.units is required.';
            result.mergeManifestId = mergeManifestId;
            return result;
        }

        List<ManifestUnit> units = new List<ManifestUnit>();
        Integer unitNumber = 0;
        for (Object row : (List<Object>) unitRows) {
            unitNumber++;
            if (!(row instanceof Map<String, Object>)) {
                result.success = false;
                result.code = 'INVALID_REQUEST';
                result.message =
                    'units[' + String.valueOf(unitNumber - 1) + '] must be an object.';
                result.mergeManifestId = mergeManifestId;
                return result;
            }
            ManifestUnit unit = parseCanonicalUnit(
                (Map<String, Object>) row,
                unitNumber
            );
            if (unit == null) {
                result.success = false;
                result.code = 'INVALID_REQUEST';
                result.message =
                    'units[' +
                    String.valueOf(unitNumber - 1) +
                    '] is missing metadataName, cls, or metaXml artifact descriptors.';
                result.mergeManifestId = mergeManifestId;
                return result;
            }
            units.add(unit);
        }

        if (units.isEmpty()) {
            result.success = false;
            result.code = 'INVALID_REQUEST';
            result.message = 'apexMergeManifest.units must include at least one entry.';
            result.mergeManifestId = mergeManifestId;
            return result;
        }

        result.success = true;
        result.mergeManifestId = mergeManifestId;
        result.units = units;
        return result;
    }

    @TestVisible
    private static ManifestUnit parseCanonicalUnit(
        Map<String, Object> unit,
        Integer unitNumber
    ) {
        String metadataName = textValue(unit.get('metadataName'));
        if (String.isBlank(metadataName)) {
            return null;
        }

        ArtifactDescriptor clsDescriptor = parseRoleDescriptor(
            unit.get('cls'),
            metadataName,
            ApexMergeArtifactService.ROLE_CLS
        );
        ArtifactDescriptor metaDescriptor = parseRoleDescriptor(
            unit.get('metaXml'),
            metadataName,
            ApexMergeArtifactService.ROLE_META_XML
        );
        if (clsDescriptor == null || metaDescriptor == null) {
            return null;
        }

        ManifestUnit parsed = new ManifestUnit();
        parsed.metadataName = metadataName;
        parsed.descriptors = new List<ArtifactDescriptor>{
            clsDescriptor,
            metaDescriptor
        };
        return parsed;
    }

    @TestVisible
    private static ArtifactDescriptor parseRoleDescriptor(
        Object rolePayload,
        String metadataName,
        String role
    ) {
        if (!(rolePayload instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> roleMap = (Map<String, Object>) rolePayload;
        String artifactId = textValue(roleMap.get('artifactId'));
        String sha256 = textValue(roleMap.get('sha256'));
        Integer byteLength = toInteger(roleMap.get('byteLength'));
        if (
            String.isBlank(artifactId) ||
            String.isBlank(sha256) ||
            byteLength == null ||
            byteLength < 0
        ) {
            return null;
        }

        ArtifactDescriptor descriptor = new ArtifactDescriptor();
        descriptor.artifactId = artifactId;
        descriptor.metadataName = metadataName;
        descriptor.role = role;
        descriptor.sha256 = sha256;
        descriptor.byteLength = byteLength;
        return descriptor;
    }

    @TestVisible
    private static DestinationContext loadAndValidateDestination(
        Id comparisonId,
        Id deploymentPlanId
    ) {
        if (comparisonId == null) {
            throw new AuraHandledException('comparisonId is required.');
        }
        if (deploymentPlanId == null) {
            throw new AuraHandledException('deploymentPlanId is required.');
        }

        List<Deployment_Plan__c> plans = [
            SELECT Id, Metadata_Comparison__c, Destination_Org__c
            FROM Deployment_Plan__c
            WHERE Id = :deploymentPlanId
            LIMIT 1
        ];
        if (plans.isEmpty()) {
            throw new AuraHandledException('Deployment Plan was not found.');
        }
        if (plans[0].Metadata_Comparison__c != comparisonId) {
            throw new AuraHandledException(
                'Deployment Plan does not belong to the selected comparison.'
            );
        }

        List<Metadata_Comparison__c> comparisons = [
            SELECT
                Destination_Org__c,
                Destination_Org__r.Refresh_Token__c,
                Destination_Org__r.Instance_URL__c,
                Destination_Org__r.Org_ID__c
            FROM Metadata_Comparison__c
            WHERE Id = :comparisonId
            LIMIT 1
        ];
        if (comparisons.isEmpty()) {
            throw new AuraHandledException('Metadata Comparison was not found.');
        }

        Metadata_Comparison__c comparison = comparisons[0];
        if (comparison.Destination_Org__c != plans[0].Destination_Org__c) {
            throw new AuraHandledException(
                'Deployment Plan destination org does not match the comparison.'
            );
        }

        String refreshToken = comparison.Destination_Org__r.Refresh_Token__c;
        String instanceUrl = comparison.Destination_Org__r.Instance_URL__c;
        String orgId = comparison.Destination_Org__r.Org_ID__c;
        if (
            String.isBlank(refreshToken) ||
            String.isBlank(instanceUrl) ||
            String.isBlank(orgId)
        ) {
            throw new AuraHandledException(
                'Destination org credentials are not available for merge artifact handoff.'
            );
        }

        DestinationContext ctx = new DestinationContext();
        ctx.refreshToken = refreshToken;
        ctx.instanceUrl = instanceUrl;
        ctx.orgId = orgId;
        return ctx;
    }

    @TestVisible
    private static Boolean requiresAsyncProcessing(List<ManifestUnit> units) {
        if (units == null || units.isEmpty()) {
            return false;
        }
        if (units.size() > MAX_UNITS_PER_SYNCHRONOUS_REQUEST) {
            return true;
        }
        return unitDescriptorBytes(units[0]) > MAX_SYNC_UNIT_DESCRIPTOR_BYTES;
    }

    @TestVisible
    private static Integer unitDescriptorBytes(ManifestUnit unit) {
        if (unit == null || unit.descriptors == null) {
            return 0;
        }
        Integer total = 0;
        for (ArtifactDescriptor descriptor : unit.descriptors) {
            total += descriptor.byteLength == null ? 0 : descriptor.byteLength;
        }
        return total;
    }

    @TestVisible
    private static Long resolveSessionExpiresAtMs(Map<String, Object> manifest) {
        if (manifest == null) {
            return null;
        }

        Long fromSession = parseExpiresAtMs(manifest.get('sessionExpiresAt'));
        if (fromSession == null) {
            fromSession = parseExpiresAtMs(manifest.get('mergeSessionExpiresAt'));
        }
        return fromSession;
    }

    @TestVisible
    private static Boolean isBackendSessionExpired(Long sessionExpiresAtMs) {
        if (sessionExpiresAtMs == null) {
            return false;
        }
        Long latestSafeStart =
            sessionExpiresAtMs - SESSION_EXPIRY_BUFFER_MS;
        return System.now().getTime() >= latestSafeStart;
    }

    private static void recordChainFailure(
        String mergeSessionId,
        String mergeManifestId,
        Id deploymentPlanId,
        Integer unitIndex,
        String code,
        String message,
        Boolean partialChain
    ) {
        ChainFailureRecord failure = new ChainFailureRecord();
        failure.mergeSessionId = mergeSessionId;
        failure.mergeManifestId = mergeManifestId;
        failure.deploymentPlanId = deploymentPlanId;
        failure.unitIndex = unitIndex;
        failure.code = code;
        failure.message = message;
        failure.partialChain = partialChain == true;
        lastChainFailure = failure;

        System.debug(
            LoggingLevel.ERROR,
            'Apex merge artifact queue failed at unit ' +
                String.valueOf(unitIndex) +
                ': ' +
                code +
                ' - ' +
                message
        );
    }

    private static void persistQueuedStatusSnapshotOrThrow(
        Deployment_Plan__c lockedPlan,
        ApexMergeArtifactStatusService.StatusSnapshot snapshot,
        String expectedStatusRunId
    ) {
        ApexMergeArtifactStatusService.PersistResult persistResult =
            ApexMergeArtifactStatusService.persist(
                lockedPlan,
                snapshot,
                expectedStatusRunId
            );
        if (persistResult.success != true) {
            String detail = String.isNotBlank(persistResult.message)
                ? persistResult.message
                : 'Unable to persist durable artifact status.';
            throw new AuraHandledException(detail);
        }
    }

    private static ApexMergeArtifactStatusService.StatusSnapshot
        snapshotFromLockedPlan(Deployment_Plan__c lockedPlan) {
        ApexMergeArtifactStatusService.LoadResult loaded =
            loadDurableStatusFromLockedRow(lockedPlan);
        if (loaded.success != true) {
            throw new AuraHandledException(
                String.isNotBlank(loaded.message)
                    ? loaded.message
                    : 'Unable to load durable artifact status.'
            );
        }
        return loaded.snapshot;
    }

    private static ApexMergeArtifactStatusService.StatusSnapshot
        persistSuccessfulUnitStatusOnLockedPlan(
        Deployment_Plan__c lockedPlan,
        Integer unitIndex,
        ManifestUnit manifestUnit,
        UnitProcessingOutcome outcome,
        Boolean isFinalUnit,
        String expectedStatusRunId
    ) {
        ApexMergeArtifactStatusService.StatusSnapshot snapshot =
            snapshotFromLockedPlan(lockedPlan);
        applySuccessfulUnitToStatusSnapshot(
            snapshot,
            unitIndex,
            manifestUnit,
            outcome,
            isFinalUnit
        );

        Boolean bridgeQueuedToCompleted =
            isFinalUnit == true &&
            ApexMergeArtifactStatusService.OVERALL_QUEUED.equals(
                lockedPlan.Latest_Apex_Merge_Artifact_Status__c
            );
        if (bridgeQueuedToCompleted == true) {
            snapshot.overallStatus =
                ApexMergeArtifactStatusService.OVERALL_PROCESSING;
            snapshot.completedAt = null;
            persistQueuedStatusSnapshotOrThrow(
                lockedPlan,
                snapshot,
                expectedStatusRunId
            );
            snapshot.overallStatus =
                ApexMergeArtifactStatusService.OVERALL_COMPLETED;
            snapshot.completedAt = ApexMergeArtifactStatusService.nowIsoUtc();
        }

        persistQueuedStatusSnapshotOrThrow(
            lockedPlan,
            snapshot,
            expectedStatusRunId
        );
        return snapshot;
    }

    private static void persistHandledQueuedFailureOnLockedPlan(
        Deployment_Plan__c lockedPlan,
        RunOwnershipExpectation expected,
        Integer unitIndex,
        ManifestUnit manifestUnit,
        String code,
        String message,
        String failedRole,
        List<Map<String, Object>> persistedArtifacts
    ) {
        ApexMergeArtifactStatusService.StatusSnapshot snapshot =
            snapshotFromLockedPlan(lockedPlan);
        applyFailedUnitToStatusSnapshot(
            snapshot,
            unitIndex,
            manifestUnit,
            code,
            message,
            failedRole,
            persistedArtifacts
        );
        persistQueuedStatusSnapshotOrThrow(
            lockedPlan,
            snapshot,
            expected.statusRunId
        );
    }

    private static void persistHandledQueuedFailureUnderLock(
        Id deploymentPlanId,
        RunOwnershipExpectation expected,
        Integer unitIndex,
        ManifestUnit manifestUnit,
        String code,
        String message,
        String failedRole,
        List<Map<String, Object>> persistedArtifacts
    ) {
        Deployment_Plan__c lockedPlan =
            lockDeploymentPlanForMutation(deploymentPlanId);
        if (lockedPlan == null) {
            return;
        }
        RunOwnershipInspection postOwnership =
            inspectRunOwnershipOnLockedRow(lockedPlan, expected);
        if (postOwnership.ownershipValid != true) {
            return;
        }
        persistHandledQueuedFailureOnLockedPlan(
            lockedPlan,
            expected,
            unitIndex,
            manifestUnit,
            code,
            message,
            failedRole,
            persistedArtifacts
        );
    }

    private static UnitProcessingOutcome mapRetrievalFailureToUnitOutcome(
        UnitRetrievalOutcome retrieval
    ) {
        UnitProcessingOutcome outcome = new UnitProcessingOutcome();
        outcome.success = false;
        outcome.code = retrieval.code;
        outcome.message = retrieval.message;
        outcome.failedArtifactId = retrieval.failedArtifactId;
        outcome.failedMetadataName = retrieval.failedMetadataName;
        outcome.persistedArtifacts = new List<Map<String, Object>>();
        return outcome;
    }

    private static void applySuccessfulUnitToStatusSnapshot(
        ApexMergeArtifactStatusService.StatusSnapshot snapshot,
        Integer unitIndex,
        ManifestUnit manifestUnit,
        UnitProcessingOutcome outcome,
        Boolean isFinalUnit
    ) {
        ApexMergeArtifactStatusService.UnitStatus unitRow =
            snapshot.units[unitIndex];
        unitRow.status = ApexMergeArtifactStatusService.UNIT_COMPLETED;
        applyPersistedArtifactsToUnit(
            unitRow,
            manifestUnit,
            outcome.persistedArtifacts
        );
        snapshot.currentUnitIndex = unitIndex;
        snapshot.lastError = null;

        if (isFinalUnit == true) {
            snapshot.overallStatus =
                ApexMergeArtifactStatusService.OVERALL_COMPLETED;
            snapshot.completedAt = ApexMergeArtifactStatusService.nowIsoUtc();
        } else {
            snapshot.overallStatus =
                ApexMergeArtifactStatusService.OVERALL_PROCESSING;
            snapshot.completedAt = null;
        }
    }

    private static void applyFailedUnitToStatusSnapshot(
        ApexMergeArtifactStatusService.StatusSnapshot snapshot,
        Integer unitIndex,
        ManifestUnit manifestUnit,
        String code,
        String message,
        String failedRole,
        List<Map<String, Object>> persistedArtifacts
    ) {
        if (
            unitIndex != null &&
            unitIndex >= 0 &&
            snapshot.units != null &&
            unitIndex < snapshot.units.size()
        ) {
            ApexMergeArtifactStatusService.UnitStatus unitRow =
                snapshot.units[unitIndex];
            unitRow.status = ApexMergeArtifactStatusService.UNIT_FAILED;
            applyPersistedArtifactsToUnit(
                unitRow,
                manifestUnit,
                persistedArtifacts
            );
            applyFailedRoleToUnit(
                unitRow,
                manifestUnit,
                failedRole,
                code,
                message
            );
            snapshot.currentUnitIndex = unitIndex;
        }

        snapshot.lastError = buildStatusLastError(
            code,
            message,
            unitIndex,
            failedRole
        );
        snapshot.overallStatus = resolveTerminalOverallAfterFailure(snapshot);
        snapshot.completedAt = ApexMergeArtifactStatusService.nowIsoUtc();
    }

    private static void applyTerminalChainInterruptToSnapshot(
        ApexMergeArtifactStatusService.StatusSnapshot snapshot,
        Integer blockedUnitIndex,
        String code,
        String message,
        String role
    ) {
        snapshot.lastError = buildStatusLastError(
            code,
            message,
            blockedUnitIndex,
            role
        );
        snapshot.overallStatus = resolveTerminalOverallAfterFailure(snapshot);
        snapshot.completedAt = ApexMergeArtifactStatusService.nowIsoUtc();
        snapshot.currentUnitIndex = blockedUnitIndex;
    }

    private static String resolveTerminalOverallAfterFailure(
        ApexMergeArtifactStatusService.StatusSnapshot snapshot
    ) {
        Integer completedCount = countFullyCompletedUnits(snapshot);
        return completedCount > 0
            ? ApexMergeArtifactStatusService.OVERALL_PARTIALLY_FAILED
            : ApexMergeArtifactStatusService.OVERALL_FAILED;
    }

    private static Integer countFullyCompletedUnits(
        ApexMergeArtifactStatusService.StatusSnapshot snapshot
    ) {
        Integer count = 0;
        if (snapshot == null || snapshot.units == null) {
            return count;
        }
        for (ApexMergeArtifactStatusService.UnitStatus unit : snapshot.units) {
            if (
                unit != null &&
                ApexMergeArtifactStatusService.UNIT_COMPLETED.equals(unit.status)
            ) {
                count++;
            }
        }
        return count;
    }

    private static ApexMergeArtifactStatusService.LastError buildStatusLastError(
        String code,
        String message,
        Integer unitIndex,
        String role
    ) {
        ApexMergeArtifactStatusService.LastError err =
            new ApexMergeArtifactStatusService.LastError();
        err.code = String.isBlank(code) ? 'PROCESSING_FAILED' : code;
        err.message = String.isBlank(message)
            ? 'Queued artifact processing failed.'
            : message;
        err.unitIndex = unitIndex;
        err.role = role;
        err.occurredAt = ApexMergeArtifactStatusService.nowIsoUtc();
        return err;
    }

    private static void applyPersistedArtifactsToUnit(
        ApexMergeArtifactStatusService.UnitStatus unitRow,
        ManifestUnit manifestUnit,
        List<Map<String, Object>> persistedArtifacts
    ) {
        if (
            unitRow == null ||
            unitRow.artifacts == null ||
            persistedArtifacts == null
        ) {
            return;
        }
        for (Map<String, Object> artifact : persistedArtifacts) {
            String role = textValue(artifact.get('role'));
            ApexMergeArtifactStatusService.ArtifactSlot slot = slotForRole(
                unitRow,
                role
            );
            if (slot == null) {
                continue;
            }
            slot.status = ApexMergeArtifactStatusService.UNIT_COMPLETED;
            slot.artifactId = textValue(artifact.get('artifactId'));
            slot.contentDocumentId = textValue(
                artifact.get('contentDocumentId')
            );
            slot.sha256 = textValue(artifact.get('sha256'));
            slot.byteLength = toInteger(artifact.get('byteLength'));
            slot.errorCode = null;
            slot.errorMessage = null;
            if (
                slot.byteLength == null &&
                manifestUnit != null &&
                manifestUnit.descriptors != null
            ) {
                for (ArtifactDescriptor descriptor : manifestUnit.descriptors) {
                    if (descriptor.role == role) {
                        slot.artifactId = descriptor.artifactId;
                        slot.sha256 = descriptor.sha256;
                        slot.byteLength = descriptor.byteLength;
                    }
                }
            }
        }
    }

    private static void applyFailedRoleToUnit(
        ApexMergeArtifactStatusService.UnitStatus unitRow,
        ManifestUnit manifestUnit,
        String failedRole,
        String code,
        String message
    ) {
        if (unitRow == null || String.isBlank(failedRole)) {
            return;
        }
        ApexMergeArtifactStatusService.ArtifactSlot slot = slotForRole(
            unitRow,
            failedRole
        );
        if (slot == null) {
            return;
        }
        if (
            !ApexMergeArtifactStatusService.UNIT_COMPLETED.equals(slot.status)
        ) {
            slot.status = ApexMergeArtifactStatusService.UNIT_FAILED;
            slot.errorCode = String.isBlank(code)
                ? 'PROCESSING_FAILED'
                : code;
            slot.errorMessage = String.isBlank(message)
                ? 'Artifact persistence failed.'
                : message;
        }
        if (
            String.isBlank(slot.artifactId) &&
            manifestUnit != null &&
            manifestUnit.descriptors != null
        ) {
            for (ArtifactDescriptor descriptor : manifestUnit.descriptors) {
                if (descriptor.role == failedRole) {
                    slot.artifactId = descriptor.artifactId;
                    break;
                }
            }
        }
    }

    private static ApexMergeArtifactStatusService.ArtifactSlot slotForRole(
        ApexMergeArtifactStatusService.UnitStatus unitRow,
        String role
    ) {
        if (unitRow == null || unitRow.artifacts == null) {
            return null;
        }
        if (role == ApexMergeArtifactService.ROLE_CLS) {
            return unitRow.artifacts.cls;
        }
        if (role == ApexMergeArtifactService.ROLE_META_XML) {
            return unitRow.artifacts.metaXml;
        }
        return null;
    }

    private static String resolveFailedArtifactRole(
        ManifestUnit unit,
        UnitProcessingOutcome outcome
    ) {
        if (unit == null || outcome == null) {
            return null;
        }
        if (String.isBlank(outcome.failedArtifactId)) {
            return null;
        }
        if (unit.descriptors == null) {
            return null;
        }
        for (ArtifactDescriptor descriptor : unit.descriptors) {
            if (descriptor.artifactId == outcome.failedArtifactId) {
                return descriptor.role;
            }
        }
        return null;
    }

    @TestVisible
    private static UnitRetrievalOutcome retrieveManifestUnitBytes(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String mergeManifestId,
        ManifestUnit unit,
        DestinationContext destination,
        Boolean authorizeBeforeFetch,
        Integer maxDescriptorBytes,
        Long sessionExpiresAtMs
    ) {
        UnitRetrievalOutcome outcome = new UnitRetrievalOutcome();
        outcome.retrieved = new List<RetrievedArtifact>();
        if (unit == null || unit.descriptors == null || unit.descriptors.size() != 2) {
            outcome.success = false;
            outcome.code = 'INVALID_REQUEST';
            outcome.message = 'Each manifest unit must contain cls and metaXml descriptors.';
            return outcome;
        }

        Integer aggregateDescriptorBytes = unitDescriptorBytes(unit);
        Integer descriptorLimit = maxDescriptorBytes == null
            ? MAX_SYNC_UNIT_DESCRIPTOR_BYTES
            : maxDescriptorBytes;
        if (aggregateDescriptorBytes > descriptorLimit) {
            outcome.success = false;
            outcome.code = 'ARTIFACT_TOO_LARGE';
            outcome.message =
                'Manifest unit byteLength exceeds the processing heap budget.';
            outcome.failedMetadataName = unit.metadataName;
            return outcome;
        }

        if (isBackendSessionExpired(sessionExpiresAtMs)) {
            outcome.success = false;
            outcome.code = 'EXPIRED';
            outcome.message = 'Merge session is no longer available on the backend.';
            outcome.failedMetadataName = unit.metadataName;
            return outcome;
        }

        if (authorizeBeforeFetch == true) {
            AuthorizationOutcome auth = authorizeHandoff(
                mergeSessionId,
                mergeManifestId,
                comparisonId,
                deploymentPlanId,
                destination,
                sessionExpiresAtMs
            );
            if (auth.success != true) {
                outcome.success = false;
                outcome.code = auth.code;
                outcome.message = auth.message;
                return outcome;
            }
        }

        for (ArtifactDescriptor descriptor : unit.descriptors) {
            RetrievalOutcome fetchOutcome = fetchArtifactBytes(
                mergeSessionId,
                mergeManifestId,
                comparisonId,
                deploymentPlanId,
                descriptor
            );
            if (fetchOutcome.success != true) {
                outcome.success = false;
                outcome.code = fetchOutcome.code;
                outcome.message = fetchOutcome.message;
                outcome.failedArtifactId = fetchOutcome.artifactId;
                outcome.failedMetadataName = descriptor.metadataName;
                return outcome;
            }
            outcome.retrieved.add(
                new RetrievedArtifact(descriptor, fetchOutcome.bytes)
            );
        }

        outcome.success = true;
        return outcome;
    }

    @TestVisible
    private static UnitProcessingOutcome persistRetrievedUnitArtifacts(
        Id deploymentPlanId,
        String mergeManifestId,
        ManifestUnit unit,
        List<RetrievedArtifact> retrieved
    ) {
        UnitProcessingOutcome outcome = new UnitProcessingOutcome();
        if (retrieved == null || retrieved.isEmpty()) {
            outcome.success = false;
            outcome.code = 'INVALID_REQUEST';
            outcome.message = 'Retrieved artifact bytes are required.';
            return outcome;
        }

        List<Map<String, Object>> persisted = new List<Map<String, Object>>();
        for (RetrievedArtifact row : retrieved) {
            ApexMergeArtifactService.PersistRequest request =
                buildPersistRequest(
                    deploymentPlanId,
                    mergeManifestId,
                    row.descriptor,
                    row.bytes
                );
            ApexMergeArtifactService.PersistResult persistResult =
                ApexMergeArtifactService.persistArtifact(request);
            if (persistResult.success != true) {
                outcome.success = false;
                outcome.code = persistResult.code != null
                    ? persistResult.code
                    : 'PERSISTENCE_FAILED';
                outcome.message = persistResult.message;
                outcome.failedArtifactId = row.descriptor.artifactId;
                outcome.failedMetadataName = row.descriptor.metadataName;
                outcome.persistedArtifacts = persisted;
                return outcome;
            }
            persisted.add(toPersistedArtifactMap(persistResult));
        }

        outcome.success = true;
        outcome.persistedArtifacts = persisted;
        return outcome;
    }

    private static String enqueueAsyncProcessing(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String sealedManifestJson,
        String mergeManifestId,
        List<ManifestUnit> units,
        Map<String, Object> manifest
    ) {
        lastChainFailure = null;
        lastEnqueuedStatusRunId = null;

        Deployment_Plan__c lockedPlan =
            lockDeploymentPlanForAsyncAcceptance(deploymentPlanId);
        if (lockedPlan == null) {
            return failureEnvelope(
                'NOT_FOUND',
                'Deployment plan was not found.',
                null,
                null,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId,
                null
            );
        }

        AsyncAcceptanceInspection inspection =
            inspectDurableAcceptanceState(lockedPlan);
        if (inspection.failClosed == true) {
            return failureEnvelope(
                inspection.failCode,
                inspection.failMessage,
                null,
                null,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId,
                null
            );
        }
        if (inspection.terminal == true) {
            return failureEnvelope(
                CODE_RUN_TERMINATED,
                'A terminal artifact retrieval run already exists for this deployment plan.',
                null,
                null,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId,
                null
            );
        }
        if (inspection.active == true) {
            ApexMergeArtifactStatusService.StatusSnapshot stored =
                inspection.snapshot;
            Boolean sameIdentity = isSameAsyncAcceptanceIdentity(
                mergeManifestId,
                mergeSessionId,
                stored.mergeManifestId,
                stored.mergeSessionId
            );
            if (sameIdentity == true) {
                return asyncAcceptedEnvelope(
                    stored.mergeSessionId,
                    stored.mergeManifestId,
                    deploymentPlanId,
                    stored.totalUnits,
                    manifest,
                    stored.statusRunId
                );
            }
            return failureEnvelope(
                CODE_RUN_IN_PROGRESS,
                'An artifact retrieval run is already in progress for this deployment plan.',
                null,
                null,
                mergeManifestId,
                deploymentPlanId,
                mergeSessionId,
                null
            );
        }

        String statusRunId = ApexMergeArtifactStatusService.newStatusRunId();
        ApexMergeArtifactStatusService.StatusSnapshot queuedSnapshot =
            buildQueuedStatusSnapshot(
                statusRunId,
                mergeManifestId,
                mergeSessionId,
                comparisonId,
                deploymentPlanId,
                units
            );

        if (blockQueuedStatusPersistForTest == true) {
            throw new AuraHandledException(
                'Queued artifact status persistence is unavailable.'
            );
        }

        ApexMergeArtifactStatusService.PersistResult persistResult =
            ApexMergeArtifactStatusService.persistNewQueuedRun(
                lockedPlan,
                queuedSnapshot
            );
        if (persistResult.success != true) {
            String detail = String.isNotBlank(persistResult.message)
                ? persistResult.message
                : 'Unable to persist queued artifact processing status.';
            throw new AuraHandledException(detail);
        }

        System.enqueueJob(
            new ApexMergeArtifactRetrievalQueueable(
                comparisonId,
                deploymentPlanId,
                mergeSessionId,
                sealedManifestJson,
                0,
                statusRunId
            )
        );
        lastEnqueuedStatusRunId = statusRunId;

        return asyncAcceptedEnvelope(
            mergeSessionId,
            mergeManifestId,
            deploymentPlanId,
            units.size(),
            manifest,
            statusRunId
        );
    }

    @TestVisible
    private static Deployment_Plan__c lockDeploymentPlanForAsyncAcceptance(
        Id deploymentPlanId
    ) {
        if (deploymentPlanId == null) {
            return null;
        }
        List<Deployment_Plan__c> plans = [
            SELECT
                Id,
                Latest_Apex_Merge_Artifact_Status__c,
                Latest_Apex_Merge_Artifact_JSON__c
            FROM Deployment_Plan__c
            WHERE Id = :deploymentPlanId
            LIMIT 1
            FOR UPDATE
        ];
        return plans.isEmpty() ? null : plans[0];
    }

    private static Deployment_Plan__c lockDeploymentPlanForMutation(
        Id deploymentPlanId
    ) {
        return lockDeploymentPlanForAsyncAcceptance(deploymentPlanId);
    }

    private static RunOwnershipExpectation buildRunOwnershipExpectation(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String mergeManifestId,
        String statusRunId
    ) {
        RunOwnershipExpectation expected = new RunOwnershipExpectation();
        expected.comparisonId = comparisonId;
        expected.deploymentPlanId = deploymentPlanId;
        expected.mergeSessionId = mergeSessionId;
        expected.mergeManifestId = mergeManifestId;
        expected.statusRunId = statusRunId;
        return expected;
    }

    private static RunOwnershipInspection inspectRunOwnershipReadOnly(
        Id deploymentPlanId,
        RunOwnershipExpectation expected
    ) {
        if (deploymentPlanId == null || expected == null) {
            return ownershipInspectionInvalid(
                true,
                'INVALID_REQUEST',
                'Deployment plan and ownership expectation are required.'
            );
        }
        List<Deployment_Plan__c> rows = [
            SELECT
                Id,
                Latest_Apex_Merge_Artifact_Status__c,
                Latest_Apex_Merge_Artifact_JSON__c
            FROM Deployment_Plan__c
            WHERE Id = :deploymentPlanId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return ownershipInspectionInvalid(
                true,
                'NOT_FOUND',
                'Deployment plan was not found.'
            );
        }
        return inspectRunOwnershipOnLockedRow(rows[0], expected);
    }

    private static RunOwnershipInspection inspectRunOwnershipOnLockedRow(
        Deployment_Plan__c planRow,
        RunOwnershipExpectation expected
    ) {
        if (expected == null || String.isBlank(expected.statusRunId)) {
            return ownershipInspectionInvalid(
                true,
                ApexMergeArtifactStatusService.CODE_OWNERSHIP_REQUIRED,
                'statusRunId is required.'
            );
        }
        RunOwnershipInspection inspection = inspectDurableRunConsistency(planRow);
        if (inspection.failClosed == true) {
            return inspection;
        }
        if (inspection.snapshot == null) {
            return ownershipInspectionInvalid(
                true,
                CODE_STATUS_STORE_AMBIGUOUS,
                'Durable artifact status is not available for run ownership.'
            );
        }
        if (!isActiveArtifactOverall(
            inspection.snapshot.overallStatus
        )) {
            return ownershipInspectionInvalid(
                false,
                null,
                null
            );
        }
        if (!runIdentityMatchesSnapshot(expected, inspection.snapshot)) {
            return ownershipInspectionInvalid(
                false,
                null,
                null
            );
        }
        inspection.ownershipValid = true;
        return inspection;
    }

    private static RunOwnershipInspection inspectDurableRunConsistency(
        Deployment_Plan__c planRow
    ) {
        RunOwnershipInspection inspection = new RunOwnershipInspection();
        if (planRow == null) {
            inspection.failClosed = true;
            inspection.failCode = 'INVALID_REQUEST';
            inspection.failMessage = 'Deployment plan row is required.';
            return inspection;
        }
        Boolean jsonBlank = String.isBlank(planRow.Latest_Apex_Merge_Artifact_JSON__c);
        Boolean statusBlank = String.isBlank(
            planRow.Latest_Apex_Merge_Artifact_Status__c
        );
        if (jsonBlank != statusBlank) {
            inspection.failClosed = true;
            inspection.failCode = CODE_STATUS_STORE_AMBIGUOUS;
            inspection.failMessage =
                'Durable artifact status fields are inconsistent.';
            return inspection;
        }
        if (jsonBlank) {
            inspection.failClosed = true;
            inspection.failCode = CODE_STATUS_STORE_AMBIGUOUS;
            inspection.failMessage =
                'Durable artifact status fields are not populated.';
            return inspection;
        }
        try {
            inspection.snapshot = ApexMergeArtifactStatusService.deserialize(
                planRow.Latest_Apex_Merge_Artifact_JSON__c
            );
        } catch (Exception e) {
            inspection.failClosed = true;
            inspection.failCode = CODE_INVALID_STORED_STATUS;
            inspection.failMessage =
                'Stored artifact status JSON is not valid.';
            return inspection;
        }
        String picklistOverall =
            planRow.Latest_Apex_Merge_Artifact_Status__c == null
                ? null
                : planRow.Latest_Apex_Merge_Artifact_Status__c.trim();
        String jsonOverall = inspection.snapshot.overallStatus == null
            ? null
            : inspection.snapshot.overallStatus.trim();
        if (picklistOverall != jsonOverall) {
            inspection.failClosed = true;
            inspection.failCode = CODE_STATUS_STORE_MISMATCH;
            inspection.failMessage =
                'Deployment plan artifact status picklist does not match stored JSON overallStatus.';
            return inspection;
        }
        return inspection;
    }

    private static SyncPersistGateResult inspectDurableStateForSyncPersist(
        Deployment_Plan__c lockedPlan
    ) {
        SyncPersistGateResult result = new SyncPersistGateResult();
        if (lockedPlan == null) {
            result.failClosed = true;
            result.failCode = 'INVALID_REQUEST';
            result.failMessage = 'Deployment plan row is required.';
            return result;
        }
        Boolean jsonBlank = String.isBlank(
            lockedPlan.Latest_Apex_Merge_Artifact_JSON__c
        );
        Boolean statusBlank = String.isBlank(
            lockedPlan.Latest_Apex_Merge_Artifact_Status__c
        );
        if (jsonBlank && statusBlank) {
            result.allowPersist = true;
            return result;
        }
        if (jsonBlank != statusBlank) {
            result.failClosed = true;
            result.failCode = CODE_STATUS_STORE_AMBIGUOUS;
            result.failMessage =
                'Durable artifact status fields are inconsistent.';
            return result;
        }

        RunOwnershipInspection inspection =
            inspectDurableRunConsistency(lockedPlan);
        if (inspection.failClosed == true) {
            result.failClosed = true;
            result.failCode = inspection.failCode;
            result.failMessage = inspection.failMessage;
            return result;
        }
        String overall = lockedPlan.Latest_Apex_Merge_Artifact_Status__c == null
            ? null
            : lockedPlan.Latest_Apex_Merge_Artifact_Status__c.trim();
        if (isActiveArtifactOverall(overall)) {
            result.allowPersist = false;
            return result;
        }
        if (
            isTerminalArtifactOverall(overall) ||
            (jsonBlank && statusBlank)
        ) {
            result.allowPersist = true;
            return result;
        }
        result.failClosed = true;
        result.failCode = CODE_STATUS_STORE_AMBIGUOUS;
        result.failMessage =
            'Stored artifact overall status is not recognized for synchronous persistence.';
        return result;
    }

    private static ApexMergeArtifactStatusService.LoadResult
        loadDurableStatusFromLockedRow(Deployment_Plan__c lockedPlan) {
        ApexMergeArtifactStatusService.LoadResult result =
            new ApexMergeArtifactStatusService.LoadResult();
        if (lockedPlan == null) {
            result.success = false;
            result.code = 'INVALID_REQUEST';
            result.message = 'lockedPlan is required.';
            return result;
        }
        RunOwnershipInspection inspection =
            inspectDurableRunConsistency(lockedPlan);
        if (inspection.failClosed == true) {
            result.success = false;
            result.code = inspection.failCode;
            result.message = inspection.failMessage;
            return result;
        }
        result.success = true;
        result.snapshot = inspection.snapshot;
        result.storedOverallStatus =
            lockedPlan.Latest_Apex_Merge_Artifact_Status__c;
        return result;
    }

    private static Boolean runIdentityMatchesSnapshot(
        RunOwnershipExpectation expected,
        ApexMergeArtifactStatusService.StatusSnapshot snapshot
    ) {
        if (expected == null || snapshot == null) {
            return false;
        }
        if (expected.statusRunId != snapshot.statusRunId) {
            return false;
        }
        if (
            expected.deploymentPlanId == null ||
            snapshot.deploymentPlanId !=
            String.valueOf(expected.deploymentPlanId)
        ) {
            return false;
        }
        if (
            expected.comparisonId == null ||
            snapshot.comparisonId != String.valueOf(expected.comparisonId)
        ) {
            return false;
        }
        if (
            expected.mergeManifestId == null ||
            !textEquals(
                expected.mergeManifestId,
                snapshot.mergeManifestId
            )
        ) {
            return false;
        }
        if (
            expected.mergeSessionId == null ||
            !textEquals(expected.mergeSessionId, snapshot.mergeSessionId)
        ) {
            return false;
        }
        return true;
    }

    private static Boolean textEquals(String left, String right) {
        String l = left == null ? null : left.trim();
        String r = right == null ? null : right.trim();
        return l == r;
    }

    private static RunOwnershipInspection ownershipInspectionInvalid(
        Boolean failClosed,
        String failCode,
        String failMessage
    ) {
        RunOwnershipInspection inspection = new RunOwnershipInspection();
        inspection.ownershipValid = false;
        inspection.failClosed = failClosed;
        inspection.failCode = failCode;
        inspection.failMessage = failMessage;
        return inspection;
    }

    @TestVisible
    private static AsyncAcceptanceInspection inspectDurableAcceptanceState(
        Deployment_Plan__c planRow
    ) {
        AsyncAcceptanceInspection inspection = new AsyncAcceptanceInspection();
        if (planRow == null) {
            inspection.failClosed = true;
            inspection.failCode = 'INVALID_REQUEST';
            inspection.failMessage = 'Deployment plan row is required.';
            return inspection;
        }

        Boolean jsonBlank = String.isBlank(planRow.Latest_Apex_Merge_Artifact_JSON__c);
        Boolean statusBlank = String.isBlank(
            planRow.Latest_Apex_Merge_Artifact_Status__c
        );
        if (jsonBlank && statusBlank) {
            inspection.blankDurableState = true;
            return inspection;
        }
        if (jsonBlank != statusBlank) {
            inspection.failClosed = true;
            inspection.failCode = CODE_STATUS_STORE_AMBIGUOUS;
            inspection.failMessage =
                'Durable artifact status fields are inconsistent.';
            return inspection;
        }

        ApexMergeArtifactStatusService.StatusSnapshot snapshot;
        try {
            snapshot = ApexMergeArtifactStatusService.deserialize(
                planRow.Latest_Apex_Merge_Artifact_JSON__c
            );
        } catch (Exception e) {
            inspection.failClosed = true;
            inspection.failCode = CODE_INVALID_STORED_STATUS;
            inspection.failMessage =
                'Stored artifact status JSON is not valid.';
            return inspection;
        }

        String picklistOverall =
            planRow.Latest_Apex_Merge_Artifact_Status__c == null
                ? null
                : planRow.Latest_Apex_Merge_Artifact_Status__c.trim();
        String jsonOverall = snapshot.overallStatus == null
            ? null
            : snapshot.overallStatus.trim();
        if (picklistOverall != jsonOverall) {
            inspection.failClosed = true;
            inspection.failCode = CODE_STATUS_STORE_MISMATCH;
            inspection.failMessage =
                'Deployment plan artifact status picklist does not match stored JSON overallStatus.';
            return inspection;
        }

        inspection.snapshot = snapshot;
        inspection.terminal = isTerminalArtifactOverall(picklistOverall);
        inspection.active = isActiveArtifactOverall(picklistOverall);

        if (inspection.terminal != true && inspection.active != true) {
            inspection.failClosed = true;
            inspection.failCode = CODE_STATUS_STORE_AMBIGUOUS;
            inspection.failMessage =
                'Stored artifact overall status is not recognized for async acceptance.';
            return inspection;
        }

        return inspection;
    }

    private static Boolean isActiveArtifactOverall(String overallStatus) {
        return ApexMergeArtifactStatusService.OVERALL_QUEUED.equals(overallStatus) ||
            ApexMergeArtifactStatusService.OVERALL_PROCESSING.equals(overallStatus);
    }

    private static Boolean isTerminalArtifactOverall(String overallStatus) {
        return ApexMergeArtifactStatusService.OVERALL_COMPLETED.equals(
                overallStatus
            ) ||
            ApexMergeArtifactStatusService.OVERALL_FAILED.equals(overallStatus) ||
            ApexMergeArtifactStatusService.OVERALL_PARTIALLY_FAILED.equals(
                overallStatus
            );
    }

    private static Boolean isSameAsyncAcceptanceIdentity(
        String requestManifestId,
        String requestSessionId,
        String storedManifestId,
        String storedSessionId
    ) {
        String reqManifest = requestManifestId == null
            ? null
            : requestManifestId.trim();
        String reqSession = requestSessionId == null ? null : requestSessionId.trim();
        String storedManifest = storedManifestId == null
            ? null
            : storedManifestId.trim();
        String storedSession = storedSessionId == null
            ? null
            : storedSessionId.trim();
        return reqManifest == storedManifest && reqSession == storedSession;
    }

    private static ApexMergeArtifactStatusService.StatusSnapshot buildQueuedStatusSnapshot(
        String statusRunId,
        String mergeManifestId,
        String mergeSessionId,
        Id comparisonId,
        Id deploymentPlanId,
        List<ManifestUnit> units
    ) {
        List<String> metadataNames = new List<String>();
        if (units != null) {
            for (ManifestUnit unit : units) {
                if (unit != null && String.isNotBlank(unit.metadataName)) {
                    metadataNames.add(unit.metadataName);
                }
            }
        }
        ApexMergeArtifactStatusService.StatusSnapshot snapshot =
            ApexMergeArtifactStatusService.newQueuedSnapshot(
                mergeManifestId,
                mergeSessionId,
                comparisonId,
                deploymentPlanId,
                metadataNames
            );
        snapshot.statusRunId = statusRunId;
        return snapshot;
    }

    @TestVisible
    private static String asyncAcceptedEnvelope(
        String mergeSessionId,
        String mergeManifestId,
        Id deploymentPlanId,
        Integer unitCount,
        Map<String, Object> manifest,
        String statusRunId
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'success' => true,
            'async' => true,
            'mergeSessionId' => mergeSessionId,
            'mergeManifestId' => mergeManifestId,
            'deploymentPlanId' => String.valueOf(deploymentPlanId),
            'queuedUnitCount' => unitCount,
            'statusRunId' => statusRunId,
            'message' =>
                'Artifact persistence continues asynchronously by manifest unit.'
        };
        Long sessionExpiresAtMs = resolveSessionExpiresAtMs(manifest);
        if (sessionExpiresAtMs != null) {
            payload.put('sessionExpiresAtMs', sessionExpiresAtMs);
        } else {
            payload.put(
                'warning',
                'Manifest did not include sessionExpiresAt or mergeSessionExpiresAt; Salesforce will not pre-check backend session lifetime.'
            );
        }
        return JSON.serialize(payload);
    }

    private static AuthorizationOutcome authorizeHandoff(
        String mergeSessionId,
        String mergeManifestId,
        Id comparisonId,
        Id deploymentPlanId,
        DestinationContext destination,
        Long sessionExpiresAtMs
    ) {
        String encodedSession = EncodingUtil.urlEncode(
            mergeSessionId,
            'UTF-8'
        );
        String endpoint =
            System.Label.Backend_Base_URL +
            SESSIONS_PATH +
            '/' +
            encodedSession +
            '/artifact-handoff/authorize';

        Map<String, Object> body = new Map<String, Object>{
            'refreshToken' => destination.refreshToken,
            'instanceUrl' => destination.instanceUrl,
            'orgId' => destination.orgId,
            'comparisonId' => String.valueOf(comparisonId),
            'deploymentPlanId' => String.valueOf(deploymentPlanId),
            'mergeManifestId' => mergeManifestId
        };

        HttpResponse res = sendJsonPost(endpoint, body, LONG_TIMEOUT_MS);
        recordCalloutInvocation();

        if (res.getStatusCode() != 200) {
            return authorizationOutcomeFail(
                mapHttpFailureCode(res.getStatusCode()),
                safeBackendMessage(res)
            );
        }

        Map<String, Object> payload;
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(
                res.getBody()
            );
        } catch (Exception e) {
            return authorizationOutcomeFail(
                'INVALID_RESPONSE',
                'Artifact handoff authorization response was not valid JSON.'
            );
        }

        if (asBoolean(payload.get('success')) != true) {
            return authorizationOutcomeFail(
                textValue(payload.get('code'), 'AUTHORIZATION_FAILED'),
                textValue(payload.get('error'), textValue(payload.get('message'), 'Artifact handoff was not authorized.'))
            );
        }
        if (asBoolean(payload.get('authorized')) != true) {
            return authorizationOutcomeFail(
                'UNAUTHORIZED',
                'Artifact handoff was not authorized.'
            );
        }

        String responseSessionId = textValue(payload.get('mergeSessionId'));
        String responseManifestId = textValue(payload.get('mergeManifestId'));
        String verifiedOrgId = textValue(payload.get('verifiedOrgId'));

        if (responseSessionId != mergeSessionId) {
            return authorizationOutcomeFail(
                'INVALID_RESPONSE',
                'Authorization response mergeSessionId did not match.'
            );
        }
        if (responseManifestId != mergeManifestId) {
            return authorizationOutcomeFail(
                'INVALID_RESPONSE',
                'Authorization response mergeManifestId did not match.'
            );
        }
        if (String.isBlank(verifiedOrgId) || verifiedOrgId != destination.orgId) {
            return authorizationOutcomeFail(
                'INVALID_RESPONSE',
                'Authorization response verifiedOrgId did not match the destination org.'
            );
        }

        Long grantExpiresAtMs = parseExpiresAtMs(payload.get('grantExpiresAt'));
        if (grantExpiresAtMs == null) {
            grantExpiresAtMs = parseExpiresAtMs(payload.get('expiresAt'));
        }
        if (
            grantExpiresAtMs != null &&
            System.now().getTime() >= grantExpiresAtMs
        ) {
            return authorizationOutcomeFail(
                'UNAUTHORIZED',
                'Artifact handoff grant has expired.'
            );
        }

        AuthorizationOutcome outcome = new AuthorizationOutcome();
        outcome.success = true;
        return outcome;
    }

    @TestVisible
    private static Long parseExpiresAtMs(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        if (rawValue instanceof Long) {
            return (Long) rawValue;
        }
        if (rawValue instanceof Integer) {
            return (Long) rawValue;
        }
        if (rawValue instanceof Decimal) {
            return ((Decimal) rawValue).longValue();
        }

        String text = String.valueOf(rawValue).trim();
        if (String.isBlank(text)) {
            return null;
        }

        if (text.isNumeric()) {
            return Long.valueOf(text);
        }

        try {
            String normalized = text.replace('T', ' ').replace('Z', '');
            if (normalized.contains('.')) {
                normalized = normalized.substring(0, normalized.indexOf('.'));
            }
            return Datetime.valueOfGmt(normalized).getTime();
        } catch (Exception e) {
            return null;
        }
    }

    private static RetrievalOutcome fetchArtifactBytes(
        String mergeSessionId,
        String mergeManifestId,
        Id comparisonId,
        Id deploymentPlanId,
        ArtifactDescriptor descriptor
    ) {
        String encodedSession = EncodingUtil.urlEncode(
            mergeSessionId,
            'UTF-8'
        );
        String encodedArtifactId = EncodingUtil.urlEncode(
            descriptor.artifactId,
            'UTF-8'
        );
        String endpoint =
            System.Label.Backend_Base_URL +
            SESSIONS_PATH +
            '/' +
            encodedSession +
            '/artifacts/' +
            encodedArtifactId +
            '?comparisonId=' +
            EncodingUtil.urlEncode(String.valueOf(comparisonId), 'UTF-8') +
            '&deploymentPlanId=' +
            EncodingUtil.urlEncode(String.valueOf(deploymentPlanId), 'UTF-8') +
            '&mergeManifestId=' +
            EncodingUtil.urlEncode(mergeManifestId, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(LONG_TIMEOUT_MS);

        HttpResponse res = new Http().send(req);
        recordCalloutInvocation();

        Integer statusCode = res.getStatusCode();
        if (statusCode != 200) {
            return retrievalOutcomeFail(
                descriptor.artifactId,
                mapHttpFailureCode(statusCode),
                safeBackendMessage(res)
            );
        }

        Blob bytes = res.getBodyAsBlob();
        if (bytes == null || bytes.size() == 0) {
            return retrievalOutcomeFail(
                descriptor.artifactId,
                'ARTIFACT_EMPTY',
                'Artifact response was empty.'
            );
        }

        String contentLengthHeader = res.getHeader('Content-Length');
        if (String.isNotBlank(contentLengthHeader)) {
            Integer contentLength = toInteger(contentLengthHeader);
            if (contentLength != null && contentLength != bytes.size()) {
                return retrievalOutcomeFail(
                    descriptor.artifactId,
                    'INTEGRITY_MISMATCH',
                    'Artifact Content-Length does not match the response body.'
                );
            }
        }

        if (descriptor.byteLength != null && bytes.size() != descriptor.byteLength) {
            return retrievalOutcomeFail(
                descriptor.artifactId,
                'INTEGRITY_MISMATCH',
                'Artifact byte length does not match the manifest.'
            );
        }

        if (bytes.size() >
            DeploymentSnapshotArtifactService.PRACTICAL_APEX_BYTE_LIMIT) {
            return retrievalOutcomeFail(
                descriptor.artifactId,
                'ARTIFACT_TOO_LARGE',
                'Artifact exceeds the practical Apex byte limit.'
            );
        }

        String actualHash = sha256Hex(bytes);
        String expectedHash = normalizeHash(descriptor.sha256);
        if (String.isBlank(expectedHash) || actualHash != expectedHash) {
            return retrievalOutcomeFail(
                descriptor.artifactId,
                'INTEGRITY_MISMATCH',
                'Artifact SHA-256 does not match the manifest.'
            );
        }

        RetrievalOutcome outcome = new RetrievalOutcome();
        outcome.success = true;
        outcome.artifactId = descriptor.artifactId;
        outcome.bytes = bytes;
        return outcome;
    }

    private static ApexMergeArtifactService.PersistRequest buildPersistRequest(
        Id deploymentPlanId,
        String mergeManifestId,
        ArtifactDescriptor descriptor,
        Blob bytes
    ) {
        ApexMergeArtifactService.PersistRequest request =
            new ApexMergeArtifactService.PersistRequest();
        request.deploymentPlanId = deploymentPlanId;
        request.mergeManifestId = mergeManifestId;
        request.artifactId = descriptor.artifactId;
        request.metadataName = descriptor.metadataName;
        request.role = descriptor.role;
        request.artifactContent = bytes;
        request.expectedByteLength = bytes.size();
        request.expectedSha256 = descriptor.sha256;
        return request;
    }

    private static String resolveMergeManifestId(Map<String, Object> manifest) {
        return textValue(
            manifest.get('mergeManifestId'),
            textValue(manifest.get('manifestId'))
        );
    }

    private static Map<String, Object> toPersistedArtifactMap(
        ApexMergeArtifactService.PersistResult persistResult
    ) {
        return new Map<String, Object>{
            'artifactId' => persistResult.artifactId,
            'contentDocumentId' => persistResult.contentDocumentId == null
                ? null
                : String.valueOf(persistResult.contentDocumentId),
            'sha256' => persistResult.sha256,
            'byteLength' => persistResult.byteLength,
            'metadataName' => persistResult.metadataName,
            'role' => persistResult.role,
            'idempotentReuse' => persistResult.idempotentReuse == true
        };
    }

    private static String successEnvelope(
        String mergeSessionId,
        String mergeManifestId,
        Id deploymentPlanId,
        List<Map<String, Object>> persistedArtifacts
    ) {
        return JSON.serialize(
            new Map<String, Object>{
                'success' => true,
                'mergeSessionId' => mergeSessionId,
                'mergeManifestId' => mergeManifestId,
                'deploymentPlanId' => String.valueOf(deploymentPlanId),
                'persistedArtifacts' => persistedArtifacts
            }
        );
    }

    @TestVisible
    private static String failureEnvelope(
        String code,
        String message,
        List<Map<String, Object>> persistedArtifacts,
        String failedArtifactId,
        String mergeManifestId,
        Id deploymentPlanId,
        String mergeSessionId,
        String failedMetadataName
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'success' => false,
            'code' => code,
            'error' => message,
            'mergeSessionId' => mergeSessionId,
            'mergeManifestId' => mergeManifestId,
            'deploymentPlanId' => deploymentPlanId == null
                ? null
                : String.valueOf(deploymentPlanId)
        };
        if (persistedArtifacts != null && !persistedArtifacts.isEmpty()) {
            payload.put('persistedArtifacts', persistedArtifacts);
        }
        if (String.isNotBlank(failedArtifactId)) {
            payload.put('failedArtifactId', failedArtifactId);
        }
        if (String.isNotBlank(failedMetadataName)) {
            payload.put('failedMetadataName', failedMetadataName);
        }
        return JSON.serialize(payload);
    }

    @TestVisible
    private static void recordCalloutInvocation() {
        Integer prior = lastInvokedCalloutCount;
        lastInvokedCalloutCount = (prior == null ? 0 : prior) + 1;
    }

    private static HttpResponse sendJsonPost(
        String endpoint,
        Map<String, Object> payload,
        Integer timeoutMs
    ) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(timeoutMs);
        req.setBody(JSON.serialize(payload));
        return new Http().send(req);
    }

    private static String safeBackendMessage(HttpResponse res) {
        String body = res.getBody();
        if (String.isBlank(body)) {
            return 'Backend request failed with status ' +
                String.valueOf(res.getStatusCode()) +
                '.';
        }

        String contentType = res.getHeader('Content-Type');
        if (contentType != null && contentType.contains('application/json')) {
            try {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
                    body
                );
                String message = textValue(
                    parsed.get('error'),
                    textValue(parsed.get('message'))
                );
                if (String.isNotBlank(message)) {
                    return message;
                }
                String code = textValue(parsed.get('code'));
                if (String.isNotBlank(code)) {
                    return code;
                }
            } catch (Exception e) {
                return 'Backend request failed.';
            }
        }
        return 'Backend request failed.';
    }

    private static String mapHttpFailureCode(Integer statusCode) {
        if (statusCode == 401 || statusCode == 403) {
            return 'UNAUTHORIZED';
        }
        if (statusCode == 404) {
            return 'NOT_FOUND';
        }
        if (statusCode == 410) {
            return 'EXPIRED';
        }
        if (statusCode >= 500) {
            return 'BACKEND_UNAVAILABLE';
        }
        return 'BACKEND_HTTP_ERROR';
    }

    private static String textValue(Object value) {
        return textValue(value, null);
    }

    private static String textValue(Object value, String fallback) {
        if (value == null) {
            return fallback;
        }
        String text = String.valueOf(value).trim();
        return String.isBlank(text) ? fallback : text;
    }

    private static Boolean asBoolean(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return 'true'.equalsIgnoreCase(String.valueOf(value));
    }

    @TestVisible
    private static Integer toInteger(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Long) {
            return Integer.valueOf(String.valueOf(value));
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).intValue();
        }
        try {
            return Integer.valueOf(String.valueOf(value).trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static String sha256Hex(Blob value) {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', value)
        ).toLowerCase();
    }

    private static String normalizeHash(String expectedSha256) {
        return expectedSha256 == null
            ? null
            : expectedSha256.trim().toLowerCase();
    }

    @TestVisible
    private static AuthorizationOutcome authorizationOutcomeFail(
        String code,
        String message
    ) {
        AuthorizationOutcome outcome = new AuthorizationOutcome();
        outcome.success = false;
        outcome.code = code;
        outcome.message = message;
        return outcome;
    }

    @TestVisible
    private static RetrievalOutcome retrievalOutcomeFail(
        String artifactId,
        String code,
        String message
    ) {
        RetrievalOutcome outcome = new RetrievalOutcome();
        outcome.success = false;
        outcome.artifactId = artifactId;
        outcome.code = code;
        outcome.message = message;
        return outcome;
    }

    private class DestinationContext {
        public String refreshToken;
        public String instanceUrl;
        public String orgId;
    }

    private class AuthorizationOutcome {
        public Boolean success;
        public String code;
        public String message;
    }

    private class UnitProcessingOutcome {
        public Boolean success;
        public String code;
        public String message;
        public String failedArtifactId;
        public String failedMetadataName;
        public List<Map<String, Object>> persistedArtifacts;
    }

    private class RetrievalOutcome {
        public Boolean success;
        public String code;
        public String message;
        public String artifactId;
        public Blob bytes;
    }

    private class RetrievedArtifact {
        public ArtifactDescriptor descriptor;
        public Blob bytes;

        public RetrievedArtifact(
            ArtifactDescriptor descriptor,
            Blob bytes
        ) {
            this.descriptor = descriptor;
            this.bytes = bytes;
        }
    }
}