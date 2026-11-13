/**
 * Durable Apex Merge artifact retrieval status on Deployment_Plan__c.
 * Serialization and persistence only — no retrieval or Queueable integration.
 */
public with sharing class ApexMergeArtifactStatusService {
    public static final Integer SCHEMA_VERSION = 1;

    public static final String OVERALL_QUEUED = 'QUEUED';
    public static final String OVERALL_PROCESSING = 'PROCESSING';
    public static final String OVERALL_COMPLETED = 'COMPLETED';
    public static final String OVERALL_PARTIALLY_FAILED = 'PARTIALLY_FAILED';
    public static final String OVERALL_FAILED = 'FAILED';

    public static final String UNIT_NOT_STARTED = 'NOT_STARTED';
    public static final String UNIT_COMPLETED = 'COMPLETED';
    public static final String UNIT_FAILED = 'FAILED';

    public static final String ROLE_CLS = 'cls';
    public static final String ROLE_META_XML = 'metaXml';

    private static final Set<String> ALLOWED_OVERALL = new Set<String>{
        OVERALL_QUEUED,
        OVERALL_PROCESSING,
        OVERALL_COMPLETED,
        OVERALL_PARTIALLY_FAILED,
        OVERALL_FAILED
    };

    private static final Set<String> ALLOWED_UNIT = new Set<String>{
        UNIT_NOT_STARTED,
        UNIT_COMPLETED,
        UNIT_FAILED
    };

    private static final Set<String> ALLOWED_ARTIFACT = new Set<String>{
        UNIT_NOT_STARTED,
        UNIT_COMPLETED,
        UNIT_FAILED
    };

    private static final Set<String> TERMINAL_OVERALL = new Set<String>{
        OVERALL_COMPLETED,
        OVERALL_PARTIALLY_FAILED,
        OVERALL_FAILED
    };

    public class StatusSnapshot {
        public Integer schemaVersion;
        public String statusRunId;
        public String mergeManifestId;
        public String mergeSessionId;
        public String comparisonId;
        public String deploymentPlanId;
        public String overallStatus;
        public Integer totalUnits;
        public Integer currentUnitIndex;
        public List<UnitStatus> units;
        public LastError lastError;
        public String startedAt;
        public String completedAt;
        public String updatedAt;
    }

    public class UnitStatus {
        public String metadataName;
        public String status;
        public ArtifactSlotPair artifacts;
    }

    public class ArtifactSlotPair {
        public ArtifactSlot cls;
        public ArtifactSlot metaXml;
    }

    public class ArtifactSlot {
        public String artifactId;
        public String status;
        public String contentDocumentId;
        public String sha256;
        public Integer byteLength;
        public String errorCode;
        public String errorMessage;
    }

    public class LastError {
        public String code;
        public String message;
        public Integer unitIndex;
        public String role;
        public String occurredAt;
    }

    public class ValidationResult {
        public Boolean success;
        public String code;
        public String message;

    }

    public class PersistResult {
        public Boolean success;
        public String code;
        public String message;
        public Id deploymentPlanId;
    }

    public class LoadResult {
        public Boolean success;
        public String code;
        public String message;
        public StatusSnapshot snapshot;
        public String storedOverallStatus;
    }

    /**
     * Loads the durable status snapshot from a deployment plan (read-only SOQL).
     */
    public static LoadResult loadFromDeploymentPlan(Id deploymentPlanId) {
        if (deploymentPlanId == null) {
            return loadFail('INVALID_REQUEST', 'deploymentPlanId is required.');
        }

        Deployment_Plan__c row = loadDeploymentPlanForPersist(deploymentPlanId);
        if (row == null) {
            return loadFail('NOT_FOUND', 'Deployment plan was not found.');
        }
        if (String.isBlank(row.Latest_Apex_Merge_Artifact_JSON__c)) {
            return loadFail(
                'NOT_FOUND',
                'Deployment plan does not have durable artifact status.'
            );
        }

        StatusSnapshot snapshot;
        try {
            snapshot = deserialize(row.Latest_Apex_Merge_Artifact_JSON__c);
        } catch (Exception e) {
            return loadFail(
                'INVALID_REQUEST',
                'Stored artifact status JSON is not valid.'
            );
        }

        LoadResult result = new LoadResult();
        result.success = true;
        result.snapshot = snapshot;
        result.storedOverallStatus = row.Latest_Apex_Merge_Artifact_Status__c;
        return result;
    }

    private static LoadResult loadFail(String code, String message) {
        LoadResult result = new LoadResult();
        result.success = false;
        result.code = code;
        result.message = message;
        return result;
    }

    private static ValidationResult validationOk() {
        ValidationResult r = new ValidationResult();
        r.success = true;
        return r;
    }

    private static ValidationResult validationFail(String code, String message) {
        ValidationResult r = new ValidationResult();
        r.success = false;
        r.code = code;
        r.message = message;
        return r;
    }

    private static PersistResult persistOk(Id deploymentPlanId) {
        PersistResult r = new PersistResult();
        r.success = true;
        r.deploymentPlanId = deploymentPlanId;
        return r;
    }

    private static PersistResult persistFail(String code, String message) {
        PersistResult r = new PersistResult();
        r.success = false;
        r.code = code;
        r.message = message;
        return r;
    }

    /**
     * Build a new run skeleton with all units NOT_STARTED.
     */
    public static StatusSnapshot newQueuedSnapshot(
        String mergeManifestId,
        String mergeSessionId,
        Id comparisonId,
        Id deploymentPlanId,
        List<String> metadataNames
    ) {
        StatusSnapshot snapshot = new StatusSnapshot();
        snapshot.schemaVersion = SCHEMA_VERSION;
        snapshot.statusRunId = newStatusRunId();
        snapshot.mergeManifestId = mergeManifestId;
        snapshot.mergeSessionId = mergeSessionId;
        snapshot.comparisonId = comparisonId == null ? null : String.valueOf(comparisonId);
        snapshot.deploymentPlanId =
            deploymentPlanId == null ? null : String.valueOf(deploymentPlanId);
        snapshot.overallStatus = OVERALL_QUEUED;
        snapshot.totalUnits = metadataNames == null ? 0 : metadataNames.size();
        snapshot.currentUnitIndex = -1;
        snapshot.units = buildUnitSkeletons(metadataNames);
        snapshot.startedAt = nowIsoUtc();
        snapshot.updatedAt = snapshot.startedAt;
        snapshot.completedAt = null;
        return snapshot;
    }

    public static String newStatusRunId() {
        Blob digest = Crypto.generateDigest(
            'SHA-256',
            Blob.valueOf(
                String.valueOf(Crypto.getRandomLong()) +
                    '|' +
                    String.valueOf(System.now().getTime())
            )
        );
        String hex = EncodingUtil.convertToHex(digest);
        return hex.substring(0, 32);
    }

    public static ValidationResult validate(StatusSnapshot snapshot) {
        if (snapshot == null) {
            return validationFail(
                'INVALID_REQUEST',
                'Status snapshot is required.'
            );
        }
        if (
            snapshot.schemaVersion == null ||
            snapshot.schemaVersion != SCHEMA_VERSION
        ) {
            return validationFail(
                'INVALID_REQUEST',
                'Unsupported or missing schemaVersion.'
            );
        }
        if (String.isBlank(snapshot.statusRunId)) {
            return validationFail(
                'INVALID_REQUEST',
                'statusRunId is required.'
            );
        }
        if (String.isBlank(snapshot.mergeManifestId)) {
            return validationFail(
                'INVALID_REQUEST',
                'mergeManifestId is required.'
            );
        }
        if (String.isBlank(snapshot.mergeSessionId)) {
            return validationFail(
                'INVALID_REQUEST',
                'mergeSessionId is required.'
            );
        }
        if (String.isBlank(snapshot.comparisonId)) {
            return validationFail(
                'INVALID_REQUEST',
                'comparisonId is required.'
            );
        }
        if (String.isBlank(snapshot.deploymentPlanId)) {
            return validationFail(
                'INVALID_REQUEST',
                'deploymentPlanId is required.'
            );
        }
        if (String.isBlank(snapshot.overallStatus)) {
            return validationFail(
                'INVALID_REQUEST',
                'overallStatus is required.'
            );
        }
        if (!ALLOWED_OVERALL.contains(snapshot.overallStatus)) {
            return validationFail(
                'INVALID_REQUEST',
                'overallStatus is not allowed.'
            );
        }
        if (snapshot.totalUnits == null || snapshot.totalUnits < 0) {
            return validationFail(
                'INVALID_REQUEST',
                'totalUnits must be zero or greater.'
            );
        }
        if (snapshot.units == null) {
            return validationFail(
                'INVALID_REQUEST',
                'units is required.'
            );
        }
        if (snapshot.units.size() != snapshot.totalUnits) {
            return validationFail(
                'INVALID_REQUEST',
                'units length must match totalUnits.'
            );
        }
        if (snapshot.currentUnitIndex == null) {
            return validationFail(
                'INVALID_REQUEST',
                'currentUnitIndex is required.'
            );
        }
        if (
            snapshot.currentUnitIndex < -1 ||
            snapshot.currentUnitIndex >= snapshot.totalUnits
        ) {
            return validationFail(
                'INVALID_REQUEST',
                'currentUnitIndex is out of range.'
            );
        }

        Set<String> seenNames = new Set<String>();
        for (Integer i = 0; i < snapshot.units.size(); i++) {
            UnitStatus unit = snapshot.units[i];
            ValidationResult unitResult = validateUnit(unit, i);
            if (unitResult.success != true) {
                return unitResult;
            }
            String name = unit.metadataName == null
                ? null
                : unit.metadataName.trim().toLowerCase();
            if (seenNames.contains(name)) {
                return validationFail(
                    'INVALID_REQUEST',
                    'Duplicate metadataName: ' + unit.metadataName
                );
            }
            seenNames.add(name);
        }

        if (String.isBlank(snapshot.startedAt)) {
            return validationFail(
                'INVALID_REQUEST',
                'startedAt is required.'
            );
        }
        if (!isValidIsoUtc(snapshot.startedAt)) {
            return validationFail(
                'INVALID_REQUEST',
                'startedAt must be UTC ISO-8601.'
            );
        }
        if (String.isBlank(snapshot.updatedAt)) {
            return validationFail(
                'INVALID_REQUEST',
                'updatedAt is required.'
            );
        }
        if (!isValidIsoUtc(snapshot.updatedAt)) {
            return validationFail(
                'INVALID_REQUEST',
                'updatedAt must be UTC ISO-8601.'
            );
        }

        Boolean terminal = TERMINAL_OVERALL.contains(snapshot.overallStatus);
        if (terminal) {
            if (String.isBlank(snapshot.completedAt)) {
                return validationFail(
                    'INVALID_REQUEST',
                    'completedAt is required for terminal overallStatus.'
                );
            }
            if (!isValidIsoUtc(snapshot.completedAt)) {
                return validationFail(
                    'INVALID_REQUEST',
                    'completedAt must be UTC ISO-8601.'
                );
            }
        } else if (String.isNotBlank(snapshot.completedAt)) {
            return validationFail(
                'INVALID_REQUEST',
                'completedAt must be null for non-terminal overallStatus.'
            );
        }

        if (snapshot.lastError != null) {
            ValidationResult errResult = validateLastError(snapshot.lastError);
            if (errResult.success != true) {
                return errResult;
            }
        }

        return validationOk();
    }

    public static ValidationResult validateTransition(
        String previousOverallStatus,
        String nextOverallStatus
    ) {
        if (String.isBlank(nextOverallStatus)) {
            return validationFail(
                'INVALID_REQUEST',
                'Next overallStatus is required.'
            );
        }
        if (!ALLOWED_OVERALL.contains(nextOverallStatus)) {
            return validationFail(
                'INVALID_REQUEST',
                'Next overallStatus is not allowed.'
            );
        }
        if (String.isBlank(previousOverallStatus)) {
            return validationOk();
        }
        if (!ALLOWED_OVERALL.contains(previousOverallStatus)) {
            return validationFail(
                'INVALID_REQUEST',
                'Previous overallStatus is not allowed.'
            );
        }
        if (
            TERMINAL_OVERALL.contains(previousOverallStatus) &&
            previousOverallStatus != nextOverallStatus
        ) {
            return validationFail(
                'INVALID_REQUEST',
                'Cannot transition from a terminal overall status.'
            );
        }
        if (!isAllowedTransition(previousOverallStatus, nextOverallStatus)) {
            return validationFail(
                'INVALID_REQUEST',
                'Disallowed overall status transition.'
            );
        }
        return validationOk();
    }

    public static String serialize(StatusSnapshot snapshot) {
        ValidationResult validated = validate(snapshot);
        if (validated.success != true) {
            throw new IllegalArgumentException(validated.message);
        }
        return JSON.serialize(snapshotToMap(snapshot));
    }

    public static StatusSnapshot deserialize(String statusJson) {
        if (String.isBlank(statusJson)) {
            throw new IllegalArgumentException('Status JSON is required.');
        }
        Map<String, Object> root;
        try {
            root = (Map<String, Object>) JSON.deserializeUntyped(statusJson);
        } catch (Exception e) {
            throw new IllegalArgumentException('Status JSON is not valid.');
        }
        StatusSnapshot snapshot = mapToSnapshot(root);
        ValidationResult validated = validate(snapshot);
        if (validated.success != true) {
            throw new IllegalArgumentException(validated.message);
        }
        return snapshot;
    }

    /**
     * Persists validated snapshot to the four Latest_Apex_Merge_Artifact_* fields only.
     * Sets updatedAt to the current UTC time before validation, serialization, and DML.
     * Transition validation uses Latest_Apex_Merge_Artifact_Status__c on the plan record.
     */
    public static PersistResult persist(StatusSnapshot snapshot) {
        if (snapshot == null) {
            return persistFail(
                'INVALID_REQUEST',
                'Status snapshot is required.'
            );
        }

        snapshot.updatedAt = nowIsoUtc();

        ValidationResult validated = validate(snapshot);
        if (validated.success != true) {
            return persistFail(validated.code, validated.message);
        }

        Id planId;
        try {
            planId = Id.valueOf(snapshot.deploymentPlanId);
        } catch (Exception e) {
            return persistFail(
                'INVALID_REQUEST',
                'deploymentPlanId is not a valid Salesforce Id.'
            );
        }

        Deployment_Plan__c existingPlan = loadDeploymentPlanForPersist(planId);
        if (existingPlan == null) {
            return persistFail('NOT_FOUND', 'Deployment plan was not found.');
        }

        ValidationResult transition = validateTransition(
            existingPlan.Latest_Apex_Merge_Artifact_Status__c,
            snapshot.overallStatus
        );
        if (transition.success != true) {
            return persistFail(transition.code, transition.message);
        }

        String jsonPayload;
        try {
            jsonPayload = JSON.serialize(snapshotToMap(snapshot));
        } catch (Exception e) {
            return persistFail(
                'INVALID_REQUEST',
                'Unable to serialize status snapshot.'
            );
        }

        Deployment_Plan__c updateRow = new Deployment_Plan__c(Id = planId);
        updateRow.Latest_Apex_Merge_Artifact_Status__c = truncateStatus(
            snapshot.overallStatus
        );
        updateRow.Latest_Apex_Merge_Artifact_JSON__c = jsonPayload;
        updateRow.Latest_Apex_Merge_Artifact_Started_At__c = parseIsoToDatetime(
            snapshot.startedAt
        );
        if (TERMINAL_OVERALL.contains(snapshot.overallStatus)) {
            updateRow.Latest_Apex_Merge_Artifact_Completed_At__c = parseIsoToDatetime(
                snapshot.completedAt
            );
        } else {
            updateRow.Latest_Apex_Merge_Artifact_Completed_At__c = null;
        }

        try {
            update updateRow;
        } catch (DmlException e) {
            return persistFail(
                'INVALID_REQUEST',
                'Unable to persist status snapshot.'
            );
        }

        return persistOk(planId);
    }

    /**
     * Persists a new QUEUED run while caller holds Deployment_Plan__c FOR UPDATE.
     * Requires genuinely blank durable status fields on the locked row.
     */
    public static PersistResult persistNewQueuedRun(
        Deployment_Plan__c lockedPlan,
        StatusSnapshot snapshot
    ) {
        if (lockedPlan == null) {
            return persistFail(
                'INVALID_REQUEST',
                'lockedPlan is required.'
            );
        }
        if (snapshot == null) {
            return persistFail(
                'INVALID_REQUEST',
                'Status snapshot is required.'
            );
        }
        if (
            String.isNotBlank(lockedPlan.Latest_Apex_Merge_Artifact_JSON__c) ||
            String.isNotBlank(lockedPlan.Latest_Apex_Merge_Artifact_Status__c)
        ) {
            return persistFail(
                CODE_STATUS_STORE_AMBIGUOUS,
                'Durable artifact status fields must be blank for a new queued run.'
            );
        }
        if (String.isBlank(snapshot.statusRunId)) {
            return persistFail(
                'INVALID_REQUEST',
                'statusRunId is required.'
            );
        }
        if (!planIdMatchesLockedRow(lockedPlan, snapshot)) {
            return persistFail(
                'INVALID_REQUEST',
                'deploymentPlanId does not match locked deployment plan.'
            );
        }
        return writeStatusSnapshotToLockedPlan(
            lockedPlan,
            snapshot
        );
    }

    /**
     * Guarded persist while caller holds Deployment_Plan__c FOR UPDATE.
     * Does not issue a separate locking query.
     */
    public static PersistResult persist(
        Deployment_Plan__c lockedPlan,
        StatusSnapshot snapshot,
        String expectedStatusRunId
    ) {
        if (lockedPlan == null) {
            return persistFail(
                'INVALID_REQUEST',
                'lockedPlan is required.'
            );
        }
        if (snapshot == null) {
            return persistFail(
                'INVALID_REQUEST',
                'Status snapshot is required.'
            );
        }
        if (String.isBlank(expectedStatusRunId)) {
            return persistFail(
                CODE_OWNERSHIP_REQUIRED,
                'expectedStatusRunId is required.'
            );
        }
        if (expectedStatusRunId != snapshot.statusRunId) {
            return persistFail(
                CODE_RUN_OWNERSHIP_LOST,
                'Incoming snapshot statusRunId does not match expected run ownership.'
            );
        }
        if (!planIdMatchesLockedRow(lockedPlan, snapshot)) {
            return persistFail(
                'INVALID_REQUEST',
                'deploymentPlanId does not match locked deployment plan.'
            );
        }

        PersistResult consistency = validateLockedRowConsistency(lockedPlan);
        if (consistency.success != true) {
            return consistency;
        }

        StatusSnapshot storedSnapshot;
        try {
            storedSnapshot = deserialize(
                lockedPlan.Latest_Apex_Merge_Artifact_JSON__c
            );
        } catch (Exception e) {
            return persistFail(
                CODE_INVALID_STORED_STATUS,
                'Stored artifact status JSON is not valid.'
            );
        }
        if (storedSnapshot.statusRunId != expectedStatusRunId) {
            return persistFail(
                CODE_RUN_OWNERSHIP_LOST,
                'Stored statusRunId does not match expected run ownership.'
            );
        }

        return writeStatusSnapshotToLockedPlan(
            lockedPlan,
            snapshot
        );
    }

    public static final String CODE_RUN_OWNERSHIP_LOST = 'RUN_OWNERSHIP_LOST';
    public static final String CODE_OWNERSHIP_REQUIRED = 'OWNERSHIP_REQUIRED';
    public static final String CODE_STATUS_STORE_AMBIGUOUS =
        'STATUS_STORE_AMBIGUOUS';
    public static final String CODE_INVALID_STORED_STATUS =
        'INVALID_STORED_STATUS';
    public static final String CODE_STATUS_STORE_MISMATCH =
        'STATUS_STORE_MISMATCH';

    private static Boolean planIdMatchesLockedRow(
        Deployment_Plan__c lockedPlan,
        StatusSnapshot snapshot
    ) {
        if (lockedPlan == null || snapshot == null) {
            return false;
        }
        try {
            return lockedPlan.Id == Id.valueOf(snapshot.deploymentPlanId);
        } catch (Exception e) {
            return false;
        }
    }

    private static PersistResult validateLockedRowConsistency(
        Deployment_Plan__c lockedPlan
    ) {
        Boolean jsonBlank = String.isBlank(
            lockedPlan.Latest_Apex_Merge_Artifact_JSON__c
        );
        Boolean statusBlank = String.isBlank(
            lockedPlan.Latest_Apex_Merge_Artifact_Status__c
        );
        if (jsonBlank || statusBlank) {
            return persistFail(
                CODE_STATUS_STORE_AMBIGUOUS,
                'Durable artifact status fields are incomplete.'
            );
        }
        StatusSnapshot storedSnapshot;
        try {
            storedSnapshot = deserialize(
                lockedPlan.Latest_Apex_Merge_Artifact_JSON__c
            );
        } catch (Exception e) {
            return persistFail(
                CODE_INVALID_STORED_STATUS,
                'Stored artifact status JSON is not valid.'
            );
        }
        String picklistOverall =
            lockedPlan.Latest_Apex_Merge_Artifact_Status__c == null
                ? null
                : lockedPlan.Latest_Apex_Merge_Artifact_Status__c.trim();
        String jsonOverall = storedSnapshot.overallStatus == null
            ? null
            : storedSnapshot.overallStatus.trim();
        if (picklistOverall != jsonOverall) {
            return persistFail(
                CODE_STATUS_STORE_MISMATCH,
                'Deployment plan artifact status picklist does not match stored JSON overallStatus.'
            );
        }
        return persistOk(lockedPlan.Id);
    }

    private static PersistResult writeStatusSnapshotToLockedPlan(
        Deployment_Plan__c lockedPlan,
        StatusSnapshot snapshot
    ) {
        snapshot.updatedAt = nowIsoUtc();

        ValidationResult validated = validate(snapshot);
        if (validated.success != true) {
            return persistFail(validated.code, validated.message);
        }

        ValidationResult transition = validateTransition(
            lockedPlan.Latest_Apex_Merge_Artifact_Status__c,
            snapshot.overallStatus
        );
        if (transition.success != true) {
            return persistFail(transition.code, transition.message);
        }

        String jsonPayload;
        try {
            jsonPayload = JSON.serialize(snapshotToMap(snapshot));
        } catch (Exception e) {
            return persistFail(
                'INVALID_REQUEST',
                'Unable to serialize status snapshot.'
            );
        }

        Deployment_Plan__c updateRow = new Deployment_Plan__c(Id = lockedPlan.Id);
        updateRow.Latest_Apex_Merge_Artifact_Status__c = truncateStatus(
            snapshot.overallStatus
        );
        updateRow.Latest_Apex_Merge_Artifact_JSON__c = jsonPayload;
        updateRow.Latest_Apex_Merge_Artifact_Started_At__c = parseIsoToDatetime(
            snapshot.startedAt
        );
        if (TERMINAL_OVERALL.contains(snapshot.overallStatus)) {
            updateRow.Latest_Apex_Merge_Artifact_Completed_At__c = parseIsoToDatetime(
                snapshot.completedAt
            );
        } else {
            updateRow.Latest_Apex_Merge_Artifact_Completed_At__c = null;
        }

        try {
            update updateRow;
        } catch (DmlException e) {
            return persistFail(
                'INVALID_REQUEST',
                'Unable to persist status snapshot.'
            );
        }

        lockedPlan.Latest_Apex_Merge_Artifact_Status__c =
            updateRow.Latest_Apex_Merge_Artifact_Status__c;
        lockedPlan.Latest_Apex_Merge_Artifact_JSON__c =
            updateRow.Latest_Apex_Merge_Artifact_JSON__c;

        return persistOk(lockedPlan.Id);
    }

    @TestVisible
    private static List<UnitStatus> buildUnitSkeletons(List<String> metadataNames) {
        List<UnitStatus> units = new List<UnitStatus>();
        if (metadataNames == null) {
            return units;
        }
        for (String name : metadataNames) {
            UnitStatus unit = new UnitStatus();
            unit.metadataName = name;
            unit.status = UNIT_NOT_STARTED;
            unit.artifacts = new ArtifactSlotPair();
            unit.artifacts.cls = notStartedArtifactSlot();
            unit.artifacts.metaXml = notStartedArtifactSlot();
            units.add(unit);
        }
        return units;
    }

    private static ArtifactSlot notStartedArtifactSlot() {
        ArtifactSlot slot = new ArtifactSlot();
        slot.status = UNIT_NOT_STARTED;
        return slot;
    }

    @TestVisible
    private static Boolean isAllowedTransition(String fromStatus, String toStatus) {
        if (fromStatus == toStatus) {
            return true;
        }
        if (fromStatus == OVERALL_QUEUED) {
            return toStatus == OVERALL_PROCESSING || toStatus == OVERALL_FAILED;
        }
        if (fromStatus == OVERALL_PROCESSING) {
            return toStatus == OVERALL_COMPLETED ||
                toStatus == OVERALL_PARTIALLY_FAILED ||
                toStatus == OVERALL_FAILED;
        }
        return false;
    }

    @TestVisible
    private static ValidationResult validateUnit(UnitStatus unit, Integer index) {
        if (unit == null) {
            return validationFail(
                'INVALID_REQUEST',
                'units[' + String.valueOf(index) + '] is required.'
            );
        }
        if (String.isBlank(unit.metadataName)) {
            return validationFail(
                'INVALID_REQUEST',
                'units[' + String.valueOf(index) + '].metadataName is required.'
            );
        }
        if (String.isBlank(unit.status) || !ALLOWED_UNIT.contains(unit.status)) {
            return validationFail(
                'INVALID_REQUEST',
                'units[' + String.valueOf(index) + '].status is invalid.'
            );
        }
        if (unit.artifacts == null) {
            return validationFail(
                'INVALID_REQUEST',
                'units[' + String.valueOf(index) + '].artifacts is required.'
            );
        }
        ValidationResult clsResult = validateArtifactSlot(
            unit.artifacts.cls,
            ROLE_CLS,
            index
        );
        if (clsResult.success != true) {
            return clsResult;
        }
        ValidationResult metaResult = validateArtifactSlot(
            unit.artifacts.metaXml,
            ROLE_META_XML,
            index
        );
        if (metaResult.success != true) {
            return metaResult;
        }
        return validationOk();
    }

    @TestVisible
    private static ValidationResult validateArtifactSlot(
        ArtifactSlot slot,
        String role,
        Integer unitIndex
    ) {
        if (slot == null) {
            return validationFail(
                'INVALID_REQUEST',
                'units[' +
                    String.valueOf(unitIndex) +
                    '].artifacts.' +
                    role +
                    ' is required.'
            );
        }
        if (String.isBlank(slot.status) || !ALLOWED_ARTIFACT.contains(slot.status)) {
            return validationFail(
                'INVALID_REQUEST',
                'Invalid artifact status for role ' + role + '.'
            );
        }
        if (String.isNotBlank(slot.sha256) && !isValidSha256(slot.sha256)) {
            return validationFail(
                'INVALID_REQUEST',
                'Invalid sha256 for role ' + role + '.'
            );
        }
        if (slot.byteLength != null && slot.byteLength < 0) {
            return validationFail(
                'INVALID_REQUEST',
                'byteLength cannot be negative for role ' + role + '.'
            );
        }
        if (
            String.isNotBlank(slot.contentDocumentId) &&
            !isValidSalesforceId(slot.contentDocumentId)
        ) {
            return validationFail(
                'INVALID_REQUEST',
                'Invalid contentDocumentId for role ' + role + '.'
            );
        }
        return validationOk();
    }

    private static ValidationResult validateLastError(LastError err) {
        if (String.isBlank(err.code)) {
            return validationFail(
                'INVALID_REQUEST',
                'lastError.code is required when lastError is present.'
            );
        }
        if (String.isBlank(err.message)) {
            return validationFail(
                'INVALID_REQUEST',
                'lastError.message is required when lastError is present.'
            );
        }
        if (
            err.role != null &&
            err.role != ROLE_CLS &&
            err.role != ROLE_META_XML
        ) {
            return validationFail(
                'INVALID_REQUEST',
                'lastError.role must be cls or metaXml.'
            );
        }
        if (
            String.isNotBlank(err.occurredAt) &&
            !isValidIsoUtc(err.occurredAt)
        ) {
            return validationFail(
                'INVALID_REQUEST',
                'lastError.occurredAt must be UTC ISO-8601.'
            );
        }
        return validationOk();
    }

    public static String nowIsoUtc() {
        return Datetime.now()
            .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    @TestVisible
    private static Boolean isValidIsoUtc(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        if (!value.endsWith('Z')) {
            return false;
        }
        try {
            parseIsoToDatetime(value);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    @TestVisible
    private static Datetime parseIsoToDatetime(String isoUtc) {
        String normalized = isoUtc == null ? '' : isoUtc.trim();
        if (normalized.endsWith('Z')) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        normalized = normalized.replace('T', ' ');
        Integer dotIndex = normalized.indexOf('.');
        if (dotIndex > 0) {
            normalized = normalized.substring(0, dotIndex);
        }
        if (normalized.length() != 19) {
            throw new IllegalArgumentException('Timestamp is not UTC ISO-8601.');
        }
        return Datetime.valueOfGmt(normalized);
    }

    @TestVisible
    private static Boolean isValidSha256(String value) {
        if (String.isBlank(value) || value.length() != 64) {
            return false;
        }
        String lower = value.toLowerCase();
        for (Integer i = 0; i < lower.length(); i++) {
            String ch = lower.substring(i, i + 1);
            if (
                !(
                    (ch >= '0' && ch <= '9') ||
                    (ch >= 'a' && ch <= 'f')
                )
            ) {
                return false;
            }
        }
        return true;
    }

    @TestVisible
    private static Boolean isValidSalesforceId(String idText) {
        try {
            Id parsed = Id.valueOf(idText);
            return parsed != null;
        } catch (Exception e) {
            return false;
        }
    }

    private static Deployment_Plan__c loadDeploymentPlanForPersist(
        Id deploymentPlanId
    ) {
        List<Deployment_Plan__c> rows = [
            SELECT
                Id,
                Latest_Apex_Merge_Artifact_Status__c,
                Latest_Apex_Merge_Artifact_JSON__c
            FROM Deployment_Plan__c
            WHERE Id = :deploymentPlanId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    @TestVisible
    private static String truncateStatus(String status) {
        if (status == null) {
            return null;
        }
        return status.length() > 80 ? status.substring(0, 80) : status;
    }

    private static Map<String, Object> snapshotToMap(StatusSnapshot snapshot) {
        Map<String, Object> root = new Map<String, Object>();
        root.put('schemaVersion', snapshot.schemaVersion);
        root.put('statusRunId', snapshot.statusRunId);
        root.put('mergeManifestId', snapshot.mergeManifestId);
        root.put('mergeSessionId', snapshot.mergeSessionId);
        root.put('comparisonId', snapshot.comparisonId);
        root.put('deploymentPlanId', snapshot.deploymentPlanId);
        root.put('overallStatus', snapshot.overallStatus);
        root.put('totalUnits', snapshot.totalUnits);
        root.put('currentUnitIndex', snapshot.currentUnitIndex);
        root.put('units', unitsToMaps(snapshot.units));
        root.put('lastError', lastErrorToMap(snapshot.lastError));
        root.put('startedAt', snapshot.startedAt);
        root.put('completedAt', snapshot.completedAt);
        root.put('updatedAt', snapshot.updatedAt);
        return root;
    }

    private static List<Object> unitsToMaps(List<UnitStatus> units) {
        List<Object> rows = new List<Object>();
        if (units == null) {
            return rows;
        }
        for (UnitStatus unit : units) {
            Map<String, Object> row = new Map<String, Object>{
                'metadataName' => unit.metadataName,
                'status' => unit.status
            };
            Map<String, Object> artifacts = new Map<String, Object>();
            if (unit.artifacts != null) {
                artifacts.put('cls', artifactToMap(unit.artifacts.cls));
                artifacts.put('metaXml', artifactToMap(unit.artifacts.metaXml));
            }
            row.put('artifacts', artifacts);
            rows.add(row);
        }
        return rows;
    }

    private static Map<String, Object> artifactToMap(ArtifactSlot slot) {
        if (slot == null) {
            return null;
        }
        Map<String, Object> m = new Map<String, Object>{
            'status' => slot.status
        };
        if (String.isNotBlank(slot.artifactId)) {
            m.put('artifactId', slot.artifactId);
        }
        if (String.isNotBlank(slot.contentDocumentId)) {
            m.put('contentDocumentId', slot.contentDocumentId);
        }
        if (String.isNotBlank(slot.sha256)) {
            m.put('sha256', slot.sha256);
        }
        if (slot.byteLength != null) {
            m.put('byteLength', slot.byteLength);
        }
        if (String.isNotBlank(slot.errorCode)) {
            m.put('errorCode', slot.errorCode);
        }
        if (String.isNotBlank(slot.errorMessage)) {
            m.put('errorMessage', slot.errorMessage);
        }
        return m;
    }

    private static Map<String, Object> lastErrorToMap(LastError err) {
        if (err == null) {
            return null;
        }
        Map<String, Object> m = new Map<String, Object>{
            'code' => err.code,
            'message' => err.message
        };
        if (err.unitIndex != null) {
            m.put('unitIndex', err.unitIndex);
        }
        if (String.isNotBlank(err.role)) {
            m.put('role', err.role);
        }
        if (String.isNotBlank(err.occurredAt)) {
            m.put('occurredAt', err.occurredAt);
        }
        return m;
    }

    @TestVisible
    private static StatusSnapshot mapToSnapshot(Map<String, Object> root) {
        StatusSnapshot snapshot = new StatusSnapshot();
        snapshot.schemaVersion = intValue(root.get('schemaVersion'));
        snapshot.statusRunId = textValue(root.get('statusRunId'));
        snapshot.mergeManifestId = textValue(root.get('mergeManifestId'));
        snapshot.mergeSessionId = textValue(root.get('mergeSessionId'));
        snapshot.comparisonId = textValue(root.get('comparisonId'));
        snapshot.deploymentPlanId = textValue(root.get('deploymentPlanId'));
        snapshot.overallStatus = textValue(root.get('overallStatus'));
        snapshot.totalUnits = intValue(root.get('totalUnits'));
        snapshot.currentUnitIndex = intValue(root.get('currentUnitIndex'));
        snapshot.startedAt = textValue(root.get('startedAt'));
        snapshot.completedAt = textValue(root.get('completedAt'));
        snapshot.updatedAt = textValue(root.get('updatedAt'));

        Object unitsObj = root.get('units');
        snapshot.units = new List<UnitStatus>();
        if (unitsObj instanceof List<Object>) {
            for (Object row : (List<Object>) unitsObj) {
                if (row instanceof Map<String, Object>) {
                    snapshot.units.add(
                        mapToUnit((Map<String, Object>) row)
                    );
                }
            }
        }

        Object errObj = root.get('lastError');
        if (errObj instanceof Map<String, Object>) {
            snapshot.lastError = mapToLastError((Map<String, Object>) errObj);
        }
        return snapshot;
    }

    private static UnitStatus mapToUnit(Map<String, Object> row) {
        UnitStatus unit = new UnitStatus();
        unit.metadataName = textValue(row.get('metadataName'));
        unit.status = textValue(row.get('status'));
        Object artifactsObj = row.get('artifacts');
        if (artifactsObj instanceof Map<String, Object>) {
            Map<String, Object> artifacts = (Map<String, Object>) artifactsObj;
            unit.artifacts = new ArtifactSlotPair();
            unit.artifacts.cls = mapToArtifact(
                (Map<String, Object>) artifacts.get('cls')
            );
            unit.artifacts.metaXml = mapToArtifact(
                (Map<String, Object>) artifacts.get('metaXml')
            );
        }
        return unit;
    }

    private static ArtifactSlot mapToArtifact(Map<String, Object> row) {
        if (row == null) {
            return null;
        }
        ArtifactSlot slot = new ArtifactSlot();
        slot.artifactId = textValue(row.get('artifactId'));
        slot.status = textValue(row.get('status'));
        slot.contentDocumentId = textValue(row.get('contentDocumentId'));
        slot.sha256 = textValue(row.get('sha256'));
        slot.byteLength = intValue(row.get('byteLength'));
        slot.errorCode = textValue(row.get('errorCode'));
        slot.errorMessage = textValue(row.get('errorMessage'));
        return slot;
    }

    private static LastError mapToLastError(Map<String, Object> row) {
        LastError err = new LastError();
        err.code = textValue(row.get('code'));
        err.message = textValue(row.get('message'));
        err.unitIndex = intValue(row.get('unitIndex'));
        err.role = textValue(row.get('role'));
        err.occurredAt = textValue(row.get('occurredAt'));
        return err;
    }

    private static String textValue(Object raw) {
        return raw == null ? null : String.valueOf(raw);
    }

    private static Integer intValue(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof Integer) {
            return (Integer) raw;
        }
        if (raw instanceof Long) {
            return ((Long) raw).intValue();
        }
        if (raw instanceof Decimal) {
            return ((Decimal) raw).intValue();
        }
        if (raw instanceof String && String.isNotBlank((String) raw)) {
            return Integer.valueOf((String) raw);
        }
        return null;
    }
}