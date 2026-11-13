/**
 * Salesforce-side SEALED immutability. Complements validation rules.
 * Blocks parent mutation and member delete after Status = SEALED.
 */
public with sharing class DeploymentSnapshotImmutabilityHandler {
    public static void beforeUpdate(
        List<Deployment_Snapshot__c> newRows,
        Map<Id, Deployment_Snapshot__c> oldMap
    ) {
        if (newRows == null || oldMap == null) {
            return;
        }
        for (Deployment_Snapshot__c row : newRows) {
            Deployment_Snapshot__c prior = oldMap.get(row.Id);
            if (prior != null &&
                prior.Status__c == DeploymentSnapshotService.STATUS_SEALED) {
                row.addError('SEALED snapshots are immutable.');
            }
        }
    }

    public static void beforeMemberChange(
        List<Deployment_Snapshot_Member__c> rows
    ) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        Set<Id> snapshotIds = new Set<Id>();
        for (Deployment_Snapshot_Member__c row : rows) {
            if (row.Deployment_Snapshot__c != null) {
                snapshotIds.add(row.Deployment_Snapshot__c);
            }
        }
        if (snapshotIds.isEmpty()) {
            return;
        }

        Map<Id, Deployment_Snapshot__c> snapshots = new Map<Id, Deployment_Snapshot__c>(
            [
                SELECT Id, Status__c
                FROM Deployment_Snapshot__c
                WHERE Id IN :snapshotIds
            ]
        );

        for (Deployment_Snapshot_Member__c row : rows) {
            Deployment_Snapshot__c parent =
                snapshots.get(row.Deployment_Snapshot__c);
            if (parent != null &&
                parent.Status__c == DeploymentSnapshotService.STATUS_SEALED) {
                row.addError('SEALED snapshot members cannot be changed.');
            }
        }
    }
}