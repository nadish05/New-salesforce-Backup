/**
 * Aura-enabled persistence for Deployment History.
 * Mirrors Comparison Result pattern: receive backend JSON, map, insert.
 * No HTTP callouts, OAuth, or REST.
 */
public with sharing class DeploymentHistoryController {

    /**
     * Saves deployment history JSON into Deployment_History__c.
     * Architecture alignment with MetadataComparisonController.saveComparisonResults.
     *
     * @param deploymentHistoryJson JSON payload returned by the backend
     * @return Map with success, recordId, message
     */
    @AuraEnabled
    public static Map<String, Object> saveDeploymentHistory(
        String deploymentHistoryJson
    ) {
        Map<String, Object> response = new Map<String, Object>{
            'success' => false,
            'recordId' => null,
            'message' => 'Unable to save deployment history.'
        };

        try {
            if (String.isBlank(deploymentHistoryJson)) {
                response.put('message', 'Unable to save deployment history.');
                return response;
            }

            DeploymentHistoryDTO dto =
                (DeploymentHistoryDTO) JSON.deserialize(
                    deploymentHistoryJson,
                    DeploymentHistoryDTO.class
                );

            DeploymentHistoryService.SaveResult result =
                DeploymentHistoryService.save(dto);

            if (result != null && result.success == true) {
                response.put('success', true);
                response.put('recordId', result.recordId);
                response.put('message', result.message);
                return response;
            }

            // TEMP DEBUG: surface exact Salesforce rejection details
            response.put('success', false);
            response.put('recordId', null);
            if (result != null && String.isNotBlank(result.message)) {
                response.put('message', result.message);
            }
            return response;
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'DeploymentHistoryController.saveDeploymentHistory failed: ' +
                e.getMessage()
            );
            // TEMP DEBUG: return exact exception text (revert after diagnosis)
            response.put('success', false);
            response.put('recordId', null);
            response.put('message', buildDebugMessage(e));
            return response;
        }
    }

    /**
     * TEMP DEBUG ONLY — revert after diagnosis.
     */
    private static String buildDebugMessage(Exception e) {
        if (e == null) {
            return 'Unable to save deployment history.';
        }

        List<String> parts = new List<String>();
        parts.add(e.getMessage());

        if (e instanceof DmlException) {
            DmlException dmlEx = (DmlException) e;
            Integer dmlCount = dmlEx.getNumDml();
            for (Integer i = 0; i < dmlCount; i++) {
                parts.add(dmlEx.getDmlMessage(i));
            }
        }

        return String.join(parts, ' | ');
    }
}