/**
 * Durable rollback operation state persistence.
 * Preserves backend state-machine semantics. Does not execute rollback.
 *
 * FAILED must not overwrite SUCCEEDED, UNKNOWN_RESULT, or IN_PROGRESS
 * through create/claim/update. markTerminal(FAILED) is the only
 * IN_PROGRESS/NOT_STARTED → FAILED path and clears Active_Scope_Key__c
 * in the same DML.
 */
public with sharing class RollbackOperationService {
    public static final String NOT_STARTED = 'NOT_STARTED';
    public static final String IN_PROGRESS = 'IN_PROGRESS';
    public static final String SUCCEEDED = 'SUCCEEDED';
    public static final String FAILED = 'FAILED';
    public static final String UNKNOWN_RESULT = 'UNKNOWN_RESULT';

    private static final Set<String> TERMINAL = new Set<String>{
        SUCCEEDED,
        FAILED,
        UNKNOWN_RESULT
    };
    private static final Set<String> IMMUTABLE = new Set<String>{
        SUCCEEDED,
        UNKNOWN_RESULT
    };

    public static ControlPlaneResult createOperation(Map<String, Object> raw) {
        if (!Schema.sObjectType.Rollback_Operation__c.isCreateable()) {
            return unauthorized();
        }

        Map<String, Object> payload = ControlPlaneSanitize.sanitize(raw);
        String operationId = textValue(payload.get('operationId'));
        String destinationOrgId = textValue(payload.get('destinationOrgId'));
        String snapshotId = textValue(payload.get('snapshotId'));
        String scopeKey = textValue(payload.get('rollbackScopeKey'));

        if (String.isBlank(operationId)) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'operationId is required.'
            );
        }
        if (String.isBlank(scopeKey)) {
            scopeKey = buildScopeKey(destinationOrgId, snapshotId);
        }
        if (String.isBlank(scopeKey)) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'rollbackScopeKey or destinationOrgId + snapshotId is required.'
            );
        }

        Rollback_Operation__c record = new Rollback_Operation__c();
        record.Operation_Id__c = operationId;
        record.Destination_Org_Id__c = destinationOrgId;
        record.Snapshot_Id__c = snapshotId;
        record.Rollback_Scope_Key__c = scopeKey;
        record.Active_Scope_Key__c = scopeKey;
        record.Status__c = NOT_STARTED;
        record.Retry_Of_Operation_Id__c =
            textValue(payload.get('retryOfOperationId'));
        record.Created_At__c = Datetime.now();
        record.Updated_At__c = record.Created_At__c;

        try {
            insert record;
            return ControlPlaneResult.ok(getByOperationId(operationId));
        } catch (DmlException e) {
            return classifyDuplicateDml(e, operationId, scopeKey);
        }
    }

    public static ControlPlaneResult getOperation(String operationId) {
        if (!Schema.sObjectType.Rollback_Operation__c.isAccessible()) {
            return unauthorized();
        }
        Rollback_Operation__c record = getByOperationId(operationId);
        if (record == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Operation not found.');
        }
        return ControlPlaneResult.ok(record);
    }

    public static ControlPlaneResult findByDestinationAndSnapshot(
        String destinationOrgId,
        String snapshotId
    ) {
        if (!Schema.sObjectType.Rollback_Operation__c.isAccessible()) {
            return unauthorized();
        }
        List<Rollback_Operation__c> rows =
            listByDestinationAndSnapshot(destinationOrgId, snapshotId);
        if (rows.isEmpty()) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Operation not found.');
        }
        return ControlPlaneResult.okList(rows);
    }

    public static ControlPlaneResult updateOperation(
        String operationId,
        Map<String, Object> raw
    ) {
        if (!Schema.sObjectType.Rollback_Operation__c.isUpdateable()) {
            return unauthorized();
        }

        Rollback_Operation__c record = lockByOperationId(operationId);
        if (record == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Operation not found.');
        }

        Map<String, Object> payload = ControlPlaneSanitize.sanitize(raw);
        if (payload.containsKey('status')) {
            String requested = textValue(payload.get('status'));
            if (!canApplyStatus(record.Status__c, requested)) {
                return ControlPlaneResult.fail(
                    'INVALID_STATE',
                    'Status transition rejected: ' +
                    record.Status__c +
                    ' -> ' +
                    requested
                );
            }
            record.Status__c = requested;
        }

        if (payload.containsKey('resultCode')) {
            record.Result_Code__c = textValue(payload.get('resultCode'));
        }
        if (payload.containsKey('resultMessage')) {
            record.Result_Message__c = textValue(payload.get('resultMessage'));
        }
        if (payload.containsKey('salesforceDeploymentId')) {
            record.Salesforce_Deployment_Id__c =
                textValue(payload.get('salesforceDeploymentId'));
        }
        retainActiveScope(record);
        record.Updated_At__c = Datetime.now();

        try {
            update record;
            return ControlPlaneResult.ok(getByOperationId(operationId));
        } catch (DmlException e) {
            return classifyDuplicateDml(
                e,
                record.Operation_Id__c,
                record.Active_Scope_Key__c
            );
        }
    }

    public static ControlPlaneResult claimOperation(String operationId) {
        Rollback_Operation__c record = lockByOperationId(operationId);
        if (record == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Operation not found.');
        }
        if (record.Status__c != NOT_STARTED) {
            return ControlPlaneResult.fail(
                'CONFLICT',
                'Operation is not available to claim.',
                record.Status__c
            );
        }
        record.Status__c = IN_PROGRESS;
        retainActiveScope(record);
        record.Updated_At__c = Datetime.now();
        update record;
        return ControlPlaneResult.ok(getByOperationId(operationId));
    }

    public static ControlPlaneResult transitionToInProgress(String operationId) {
        return claimOperation(operationId);
    }

    public static ControlPlaneResult markExecutionStarted(String operationId) {
        Rollback_Operation__c record = lockByOperationId(operationId);
        if (record == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Operation not found.');
        }
        if (IMMUTABLE.contains(record.Status__c) || record.Status__c == FAILED) {
            return ControlPlaneResult.fail(
                'INVALID_STATE',
                'Terminal operation cannot start execution.'
            );
        }
        if (record.Status__c == NOT_STARTED) {
            record.Status__c = IN_PROGRESS;
        }
        if (record.Execution_Started_At__c == null) {
            record.Execution_Started_At__c = Datetime.now();
        }
        retainActiveScope(record);
        record.Updated_At__c = Datetime.now();
        update record;
        return ControlPlaneResult.ok(getByOperationId(operationId));
    }

    public static ControlPlaneResult markTerminal(
        String operationId,
        String terminalStatus,
        String resultCode,
        String resultMessage
    ) {
        Rollback_Operation__c record = lockByOperationId(operationId);
        if (record == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Operation not found.');
        }
        if (!TERMINAL.contains(terminalStatus)) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'Terminal status must be SUCCEEDED, FAILED, or UNKNOWN_RESULT.'
            );
        }
        if (!canMarkTerminal(record.Status__c, terminalStatus)) {
            return ControlPlaneResult.fail(
                'INVALID_STATE',
                'Cannot transition ' +
                record.Status__c +
                ' to ' +
                terminalStatus +
                '.'
            );
        }

        record.Status__c = terminalStatus;
        record.Result_Code__c = resultCode;
        record.Result_Message__c = resultMessage;
        record.Completed_At__c = Datetime.now();
        record.Updated_At__c = record.Completed_At__c;
        if (terminalStatus == FAILED) {
            record.Active_Scope_Key__c = null;
        } else {
            retainActiveScope(record);
        }

        try {
            update record;
            return ControlPlaneResult.ok(getByOperationId(operationId));
        } catch (DmlException e) {
            return classifyDuplicateDml(
                e,
                record.Operation_Id__c,
                record.Active_Scope_Key__c
            );
        }
    }

    public static String buildScopeKey(
        String destinationOrgId,
        String snapshotId
    ) {
        if (String.isBlank(destinationOrgId) || String.isBlank(snapshotId)) {
            return null;
        }
        return destinationOrgId.trim() + '|' + snapshotId.trim();
    }

    private static void retainActiveScope(Rollback_Operation__c record) {
        if (record == null || record.Status__c == FAILED) {
            return;
        }
        if (String.isBlank(record.Active_Scope_Key__c)) {
            record.Active_Scope_Key__c = record.Rollback_Scope_Key__c;
        }
    }

    private static Boolean canApplyStatus(String current, String requested) {
        if (String.isBlank(requested) || requested == current) {
            return requested == current;
        }
        if (IMMUTABLE.contains(current) || current == FAILED) {
            return false;
        }
        if (requested == FAILED && current == IN_PROGRESS) {
            return false;
        }
        if (current == NOT_STARTED && requested == IN_PROGRESS) {
            return true;
        }
        return false;
    }

    private static Boolean canMarkTerminal(String current, String requested) {
        if (IMMUTABLE.contains(current)) {
            return false;
        }
        if (current == FAILED) {
            return false;
        }
        if (current == IN_PROGRESS && TERMINAL.contains(requested)) {
            return true;
        }
        if (current == NOT_STARTED &&
            (requested == FAILED || requested == UNKNOWN_RESULT)) {
            return true;
        }
        return false;
    }

    private static Rollback_Operation__c getByOperationId(String operationId) {
        if (String.isBlank(operationId)) {
            return null;
        }
        List<Rollback_Operation__c> rows = [
            SELECT
                Id,
                Operation_Id__c,
                Destination_Org_Id__c,
                Snapshot_Id__c,
                Rollback_Scope_Key__c,
                Active_Scope_Key__c,
                Status__c,
                Retry_Of_Operation_Id__c,
                Created_At__c,
                Updated_At__c,
                Execution_Started_At__c,
                Completed_At__c,
                Salesforce_Deployment_Id__c,
                Result_Code__c,
                Result_Message__c
            FROM Rollback_Operation__c
            WHERE Operation_Id__c = :operationId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Rollback_Operation__c lockByOperationId(String operationId) {
        if (String.isBlank(operationId)) {
            return null;
        }
        List<Rollback_Operation__c> rows = [
            SELECT
                Id,
                Operation_Id__c,
                Destination_Org_Id__c,
                Snapshot_Id__c,
                Rollback_Scope_Key__c,
                Active_Scope_Key__c,
                Status__c,
                Retry_Of_Operation_Id__c,
                Created_At__c,
                Updated_At__c,
                Execution_Started_At__c,
                Completed_At__c,
                Salesforce_Deployment_Id__c,
                Result_Code__c,
                Result_Message__c
            FROM Rollback_Operation__c
            WHERE Operation_Id__c = :operationId
            LIMIT 1
            FOR UPDATE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static List<Rollback_Operation__c> listByDestinationAndSnapshot(
        String destinationOrgId,
        String snapshotId
    ) {
        if (String.isBlank(destinationOrgId) || String.isBlank(snapshotId)) {
            return new List<Rollback_Operation__c>();
        }
        return [
            SELECT
                Id,
                Operation_Id__c,
                Destination_Org_Id__c,
                Snapshot_Id__c,
                Rollback_Scope_Key__c,
                Active_Scope_Key__c,
                Status__c,
                Retry_Of_Operation_Id__c,
                Created_At__c,
                Updated_At__c,
                Execution_Started_At__c,
                Completed_At__c,
                Salesforce_Deployment_Id__c,
                Result_Code__c,
                Result_Message__c
            FROM Rollback_Operation__c
            WHERE Destination_Org_Id__c = :destinationOrgId
            AND Snapshot_Id__c = :snapshotId
            ORDER BY Created_At__c ASC, Operation_Id__c ASC
        ];
    }

    private static ControlPlaneResult unauthorized() {
        return ControlPlaneResult.fail(
            'UNAUTHORIZED',
            'Insufficient access for Rollback_Operation__c.'
        );
    }

    private static ControlPlaneResult classifyDuplicateDml(
        DmlException e,
        String attemptedOperationId,
        String attemptedActiveScopeKey
    ) {
        String message = e == null ? 'Unable to save.' : e.getMessage();
        if (e != null &&
            e.getNumDml() > 0 &&
            e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
            if (dmlFieldsContain(e, 'Operation_Id__c') ||
                dmlMessageContains(e, 'Operation_Id__c', message)) {
                return ControlPlaneResult.fail(
                    'DUPLICATE_VALUE',
                    'Duplicate value rejected.',
                    'Operation_Id__c'
                );
            }
            if (dmlFieldsContain(e, 'Active_Scope_Key__c') ||
                dmlMessageContains(e, 'Active_Scope_Key__c', message)) {
                return ControlPlaneResult.fail(
                    'CONFLICT',
                    'An authoritative rollback operation already exists for this destination and snapshot.',
                    'Active_Scope_Key__c'
                );
            }

            if (String.isNotBlank(attemptedOperationId)) {
                Rollback_Operation__c existingOperation =
                    findExistingOperationId(attemptedOperationId);
                if (existingOperation != null) {
                    return ControlPlaneResult.fail(
                        'DUPLICATE_VALUE',
                        'Duplicate value rejected.',
                        'Operation_Id__c'
                    );
                }
            }

            if (String.isNotBlank(attemptedActiveScopeKey)) {
                Rollback_Operation__c activeScopeHolder =
                    findActiveScopeHolder(attemptedActiveScopeKey);
                if (
                    activeScopeHolder != null &&
                    activeScopeHolder.Operation_Id__c !=
                    attemptedOperationId
                ) {
                    return ControlPlaneResult.fail(
                        'CONFLICT',
                        'An authoritative rollback operation already exists for this destination and snapshot.',
                        'Active_Scope_Key__c'
                    );
                }
            }

            String field = 'Operation_Id__c';
            if (dmlFieldsContain(e, 'Rollback_Scope_Key__c') ||
                dmlMessageContains(e, 'Rollback_Scope_Key__c', message)) {
                field = 'Rollback_Scope_Key__c';
            }
            return ControlPlaneResult.fail(
                'DUPLICATE_VALUE',
                'Duplicate value rejected.',
                field
            );
        }
        return ControlPlaneResult.fail('INVALID_REQUEST', message);
    }

    private static Boolean dmlFieldsContain(DmlException e, String fieldName) {
        if (e == null || e.getNumDml() == 0 || String.isBlank(fieldName)) {
            return false;
        }
        List<Schema.SObjectField> fields = e.getDmlFields(0);
        if (fields == null || fields.isEmpty()) {
            return false;
        }
        for (Schema.SObjectField field : fields) {
            if (
                field != null &&
                fieldName.equalsIgnoreCase(field.getDescribe().getName())
            ) {
                return true;
            }
        }
        return false;
    }

    private static Boolean dmlMessageContains(
        DmlException e,
        String fieldName,
        String message
    ) {
        if (String.isBlank(fieldName)) {
            return false;
        }
        if (message != null && message.contains(fieldName)) {
            return true;
        }
        if (e != null && e.getNumDml() > 0) {
            String dmlMessage = e.getDmlMessage(0);
            return dmlMessage != null && dmlMessage.contains(fieldName);
        }
        return false;
    }

    private static Rollback_Operation__c findExistingOperationId(
        String operationId
    ) {
        if (String.isBlank(operationId)) {
            return null;
        }
        List<Rollback_Operation__c> rows = [
            SELECT Id, Operation_Id__c
            FROM Rollback_Operation__c
            WHERE Operation_Id__c = :operationId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Rollback_Operation__c findActiveScopeHolder(
        String activeScopeKey
    ) {
        if (String.isBlank(activeScopeKey)) {
            return null;
        }
        List<Rollback_Operation__c> rows = [
            SELECT Id, Operation_Id__c, Status__c, Active_Scope_Key__c
            FROM Rollback_Operation__c
            WHERE Active_Scope_Key__c = :activeScopeKey
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static String textValue(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }
}