/**
 * Shared result envelope for Product/Control Org persistence services.
 * Persistence only — does not execute rollback or destination mutation.
 */
public with sharing class ControlPlaneResult {
    public Boolean success;
    public String code;
    public String message;
    public String field;
    public Id recordId;
    public SObject record;
    public List<SObject> records;
    public Blob artifactBytes;
    public Decimal leaseGeneration;

    public static ControlPlaneResult ok(SObject record) {
        ControlPlaneResult result = new ControlPlaneResult();
        result.success = true;
        result.record = record;
        result.recordId = record == null ? null : record.Id;
        return result;
    }

    public static ControlPlaneResult okList(List<SObject> records) {
        ControlPlaneResult result = new ControlPlaneResult();
        result.success = true;
        result.records = records;
        return result;
    }

    public static ControlPlaneResult fail(
        String code,
        String message
    ) {
        return fail(code, message, null);
    }

    public static ControlPlaneResult fail(
        String code,
        String message,
        String field
    ) {
        ControlPlaneResult result = new ControlPlaneResult();
        result.success = false;
        result.code = code;
        result.message = message;
        result.field = field;
        return result;
    }

    public Map<String, Object> toMap() {
        Map<String, Object> payload = new Map<String, Object>{
            'success' => success == true,
            'code' => code,
            'message' => message,
            'field' => field,
            'recordId' => recordId,
            'leaseGeneration' => leaseGeneration
        };
        if (record != null) {
            payload.put('record', record);
        }
        if (records != null) {
            payload.put('records', records);
        }
        return payload;
    }
}