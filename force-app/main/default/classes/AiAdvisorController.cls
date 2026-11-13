/**
 * Phase 10F — AuraEnabled entry point for the AI Deployment Advisor.
 * Thin proxy to AiAdvisorService. No planner logic.
 */
public with sharing class AiAdvisorController {

    /**
     * Proxy an AI Advisor request to the backend.
     *
     * @param requestJson Existing planner / deployment review state as JSON
     * @return Backend response body JSON string
     */
    @AuraEnabled
    public static String getAiAdvisor(String requestJson) {
        return AiAdvisorService.requestAdvisor(requestJson);
    }

}