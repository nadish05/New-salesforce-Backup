/**
 * Processes one sealed manifest unit per queueable execution (2 GET + 2 DML).
 * Manifest JSON carries descriptors only — never artifact Blobs.
 */
public class ApexMergeArtifactRetrievalQueueable implements Queueable, Database.AllowsCallouts {
    private final Id comparisonId;
    private final Id deploymentPlanId;
    private final String mergeSessionId;
    private final String sealedManifestJson;
    private final Integer unitIndex;
    private final String statusRunId;

    public ApexMergeArtifactRetrievalQueueable(
        Id comparisonId,
        Id deploymentPlanId,
        String mergeSessionId,
        String sealedManifestJson,
        Integer unitIndex,
        String statusRunId
    ) {
        this.comparisonId = comparisonId;
        this.deploymentPlanId = deploymentPlanId;
        this.mergeSessionId = mergeSessionId;
        this.sealedManifestJson = sealedManifestJson;
        this.unitIndex = unitIndex;
        this.statusRunId = statusRunId;
    }

    public void execute(QueueableContext context) {
        ApexMergeArtifactRetrievalService.processQueuedUnit(
            comparisonId,
            deploymentPlanId,
            mergeSessionId,
            sealedManifestJson,
            unitIndex,
            statusRunId
        );
    }
}