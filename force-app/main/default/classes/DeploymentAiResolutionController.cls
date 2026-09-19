/**
 * Phase 18.2 / 17.7 — On-demand AI Resolution Apex entry point.
 * Thin proxy only. Does not execute deployment, Auto Fix, or SAFE_SKIP.
 */
public with sharing class DeploymentAiResolutionController {

    /**
     * Proxy an on-demand AI resolution request to the backend.
     *
     * @param provider Provider id: gemini | openai | gpt
     * @param contextJson JSON object with allowed validation context fields only
     * @return Backend response body JSON string
     */
    @AuraEnabled
    public static String resolveWithAi(String provider, String contextJson) {
        return DeploymentAiResolutionService.requestAiResolution(
            provider,
            contextJson
        );
    }
}