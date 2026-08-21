/**
 * Phase 18.3 / 17.8 — Support Bundle Apex entry point.
 * Diagnostic download proxy only. No email, persistence, deploy, AI, or Auto Fix.
 */
public with sharing class DeploymentSupportBundleController {

    /**
     * Proxy a Support Bundle generation request to the backend.
     *
     * @param requestJson JSON with validationId, validationContext, issueSelection
     * @return Backend response body JSON string
     */
    @AuraEnabled
    public static String createSupportBundle(String requestJson) {
        return DeploymentSupportBundleService.requestSupportBundle(requestJson);
    }
}