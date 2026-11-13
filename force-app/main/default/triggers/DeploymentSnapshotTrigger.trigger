trigger DeploymentSnapshotTrigger on Deployment_Snapshot__c (
    before update
) {
    DeploymentSnapshotImmutabilityHandler.beforeUpdate(
        Trigger.new,
        Trigger.oldMap
    );
}