/**
 * Aura-enabled entry point for Backend snapshotExport persistence.
 */
public with sharing class SnapshotPersistenceController {

    @AuraEnabled
    public static Map<String, Object> persistSnapshotExport(
        String snapshotExportJson,
        String historyId
    ) {
        SnapshotPersistenceService.PersistResult result =
            SnapshotPersistenceService.persistSnapshotExport(
                snapshotExportJson,
                historyId
            );
        return result.toMap();
    }
}