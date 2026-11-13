/**
 * Destination-org mutation lock persistence.
 * Uses SELECT ... FOR UPDATE and unique Destination_Org_Id__c.
 * Does not auto-steal, auto-release, or claim distributed-safety by existence.
 */
public with sharing class DestinationOrgLockService {
    public static final String HELD = 'HELD';
    public static final String RELEASED = 'RELEASED';
    private static final Set<String> OPERATION_TYPES = new Set<String>{
        'DEPLOY',
        'ROLLBACK'
    };

    public static ControlPlaneResult acquire(Map<String, Object> raw) {
        if (!hasWriteAccess()) {
            return unauthorized();
        }

        Map<String, Object> payload = ControlPlaneSanitize.sanitize(raw);
        String destinationOrgId = textValue(payload.get('destinationOrgId'));
        String ownerId = textValue(payload.get('ownerId'));
        if (String.isBlank(destinationOrgId) || String.isBlank(ownerId)) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'destinationOrgId and ownerId are required.'
            );
        }

        String operationType = textValue(payload.get('operationType'));
        if (String.isNotBlank(operationType) &&
            !OPERATION_TYPES.contains(operationType)) {
            return ControlPlaneResult.fail(
                'INVALID_REQUEST',
                'operationType must be DEPLOY or ROLLBACK.'
            );
        }

        Datetime now = Datetime.now();
        Datetime expiresAt = datetimeValue(payload.get('expiresAt'));
        if (expiresAt == null) {
            expiresAt = now.addMinutes(15);
        }

        Savepoint sp = Database.setSavepoint();
        try {
            Destination_Org_Lock__c row = lockRow(destinationOrgId);
            if (row == null) {
                Destination_Org_Lock__c created = new Destination_Org_Lock__c();
                applyHold(
                    created,
                    destinationOrgId,
                    ownerId,
                    operationType,
                    payload,
                    1,
                    now,
                    expiresAt
                );
                insert created;
                return success(getRow(destinationOrgId));
            }

            if (row.Status__c == HELD) {
                ControlPlaneResult conflict = ControlPlaneResult.fail(
                    'CONFLICT',
                    'Destination org lock is already held.'
                );
                conflict.leaseGeneration = row.Lease_Generation__c;
                conflict.record = row;
                return conflict;
            }

            Decimal nextGeneration =
                (row.Lease_Generation__c == null
                    ? 0
                    : row.Lease_Generation__c) + 1;
            applyHold(
                row,
                destinationOrgId,
                ownerId,
                operationType,
                payload,
                nextGeneration,
                now,
                expiresAt
            );
            update row;
            return success(getRow(destinationOrgId));
        } catch (DmlException e) {
            Database.rollback(sp);
            if (e.getMessage() != null &&
                e.getMessage().contains('DUPLICATE_VALUE')) {
                Destination_Org_Lock__c existing = lockRow(destinationOrgId);
                if (existing != null && existing.Status__c == HELD) {
                    ControlPlaneResult conflict = ControlPlaneResult.fail(
                        'CONFLICT',
                        'Destination org lock is already held.'
                    );
                    conflict.leaseGeneration = existing.Lease_Generation__c;
                    conflict.record = existing;
                    return conflict;
                }
                return ControlPlaneResult.fail(
                    'DUPLICATE_VALUE',
                    'Duplicate destination org lock rejected.',
                    'Destination_Org_Id__c'
                );
            }
            return ControlPlaneResult.fail('INVALID_REQUEST', e.getMessage());
        }
    }

    public static ControlPlaneResult renew(Map<String, Object> raw) {
        if (!hasWriteAccess()) {
            return unauthorized();
        }
        Map<String, Object> payload = ControlPlaneSanitize.sanitize(raw);
        Destination_Org_Lock__c row = lockRow(
            textValue(payload.get('destinationOrgId'))
        );
        ControlPlaneResult ownership = assertOwner(row, payload);
        if (ownership != null) {
            return ownership;
        }

        Datetime expiresAt = datetimeValue(payload.get('expiresAt'));
        row.Last_Heartbeat_At__c = Datetime.now();
        if (expiresAt != null) {
            row.Expires_At__c = expiresAt;
        }
        update row;
        return success(getRow(row.Destination_Org_Id__c));
    }

    public static ControlPlaneResult release(Map<String, Object> raw) {
        if (!hasWriteAccess()) {
            return unauthorized();
        }
        Map<String, Object> payload = ControlPlaneSanitize.sanitize(raw);
        Destination_Org_Lock__c row = lockRow(
            textValue(payload.get('destinationOrgId'))
        );
        ControlPlaneResult ownership = assertOwner(row, payload);
        if (ownership != null) {
            return ownership;
        }

        row.Status__c = RELEASED;
        row.Last_Heartbeat_At__c = Datetime.now();
        update row;
        return success(getRow(row.Destination_Org_Id__c));
    }

    public static ControlPlaneResult getLock(String destinationOrgId) {
        if (!Schema.sObjectType.Destination_Org_Lock__c.isAccessible()) {
            return unauthorized();
        }
        Destination_Org_Lock__c row = getRow(destinationOrgId);
        if (row == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Lock not found.');
        }
        return success(row);
    }

    /**
     * Internal/admin only. Not exposed on REST or LWC.
     * Increments generation so a stale owner cannot renew.
     */
    public static ControlPlaneResult adminRelease(String destinationOrgId) {
        if (!hasWriteAccess()) {
            return unauthorized();
        }
        Destination_Org_Lock__c row = lockRow(destinationOrgId);
        if (row == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Lock not found.');
        }
        row.Status__c = RELEASED;
        row.Lease_Generation__c =
            (row.Lease_Generation__c == null ? 0 : row.Lease_Generation__c) + 1;
        row.Last_Heartbeat_At__c = Datetime.now();
        update row;
        return success(getRow(destinationOrgId));
    }

    private static void applyHold(
        Destination_Org_Lock__c row,
        String destinationOrgId,
        String ownerId,
        String operationType,
        Map<String, Object> payload,
        Decimal generation,
        Datetime now,
        Datetime expiresAt
    ) {
        row.Destination_Org_Id__c = destinationOrgId;
        row.Owner_Id__c = ownerId;
        row.Lease_Generation__c = generation;
        row.Status__c = HELD;
        row.Operation_Type__c = operationType;
        row.Acquired_At__c = now;
        row.Expires_At__c = expiresAt;
        row.Last_Heartbeat_At__c = now;
        row.History_Id__c = textValue(payload.get('historyId'));
        row.Snapshot_Id__c = textValue(payload.get('snapshotId'));
    }

    private static ControlPlaneResult assertOwner(
        Destination_Org_Lock__c row,
        Map<String, Object> payload
    ) {
        if (row == null) {
            return ControlPlaneResult.fail('NOT_FOUND', 'Lock not found.');
        }
        if (row.Status__c != HELD) {
            return ControlPlaneResult.fail(
                'INVALID_STATE',
                'Lock is not held.'
            );
        }
        String ownerId = textValue(payload.get('ownerId'));
        Decimal generation = decimalValue(payload.get('leaseGeneration'));
        if (row.Owner_Id__c != ownerId ||
            row.Lease_Generation__c != generation) {
            ControlPlaneResult conflict = ControlPlaneResult.fail(
                'CONFLICT',
                'Lease generation or owner does not match.'
            );
            conflict.leaseGeneration = row.Lease_Generation__c;
            conflict.record = row;
            return conflict;
        }
        return null;
    }

    private static Destination_Org_Lock__c lockRow(String destinationOrgId) {
        if (String.isBlank(destinationOrgId)) {
            return null;
        }
        List<Destination_Org_Lock__c> rows = [
            SELECT
                Id,
                Destination_Org_Id__c,
                Owner_Id__c,
                Lease_Generation__c,
                Status__c,
                Operation_Type__c,
                Acquired_At__c,
                Expires_At__c,
                Last_Heartbeat_At__c,
                History_Id__c,
                Snapshot_Id__c
            FROM Destination_Org_Lock__c
            WHERE Destination_Org_Id__c = :destinationOrgId
            LIMIT 1
            FOR UPDATE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Destination_Org_Lock__c getRow(String destinationOrgId) {
        if (String.isBlank(destinationOrgId)) {
            return null;
        }
        List<Destination_Org_Lock__c> rows = [
            SELECT
                Id,
                Destination_Org_Id__c,
                Owner_Id__c,
                Lease_Generation__c,
                Status__c,
                Operation_Type__c,
                Acquired_At__c,
                Expires_At__c,
                Last_Heartbeat_At__c,
                History_Id__c,
                Snapshot_Id__c
            FROM Destination_Org_Lock__c
            WHERE Destination_Org_Id__c = :destinationOrgId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static ControlPlaneResult success(Destination_Org_Lock__c row) {
        ControlPlaneResult result = ControlPlaneResult.ok(row);
        result.leaseGeneration = row == null ? null : row.Lease_Generation__c;
        return result;
    }

    private static Boolean hasWriteAccess() {
        return Schema.sObjectType.Destination_Org_Lock__c.isCreateable() &&
            Schema.sObjectType.Destination_Org_Lock__c.isUpdateable();
    }

    private static ControlPlaneResult unauthorized() {
        return ControlPlaneResult.fail(
            'UNAUTHORIZED',
            'Insufficient access for Destination_Org_Lock__c.'
        );
    }

    private static String textValue(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Decimal decimalValue(Object value) {
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static Datetime datetimeValue(Object value) {
        if (value instanceof Datetime) {
            return (Datetime) value;
        }
        if (value == null) {
            return null;
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
}