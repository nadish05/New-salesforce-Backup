trigger DeploymentSnapshotMemberTrigger on Deployment_Snapshot_Member__c (
    before insert,
    before update,
    before delete
) {
    List<Deployment_Snapshot_Member__c> rows =
        Trigger.isDelete ? Trigger.old : Trigger.new;
    DeploymentSnapshotImmutabilityHandler.beforeMemberChange(rows);
}