/**
 * REST entry point for Deployment History persistence.
 * Backend POSTs JSON; Apex maps and stores Deployment_History__c.
 */
@RestResource(urlMapping='/deployment-history/*')
global with sharing class DeploymentHistoryApi {

    @HttpPost
    global static void createDeploymentHistory() {
        RestResponse response = RestContext.response;
        if (response == null) {
            response = new RestResponse();
            RestContext.response = response;
        }

        response.addHeader('Content-Type', 'application/json');

        try {
            RestRequest request = RestContext.request;
            String body =
                request == null || request.requestBody == null
                    ? null
                    : request.requestBody.toString();

            if (String.isBlank(body)) {
                writeError(response, 400);
                return;
            }

            DeploymentHistoryDTO dto =
                (DeploymentHistoryDTO) JSON.deserialize(
                    body,
                    DeploymentHistoryDTO.class
                );

            if (dto == null) {
                writeError(response, 400);
                return;
            }

            DeploymentHistoryService.SaveResult result =
                DeploymentHistoryService.save(dto);

            if (result != null && result.success == true) {
                response.statusCode = 200;
                response.responseBody = Blob.valueOf(
                    JSON.serialize(
                        new Map<String, Object>{
                            'success' => true,
                            'recordId' => result.recordId
                        }
                    )
                );
                return;
            }

            writeError(response, 400);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'DeploymentHistoryApi error: ' + e.getMessage()
            );
            writeError(response, 500);
        }
    }

    private static void writeError(RestResponse response, Integer statusCode) {
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(
            JSON.serialize(
                new Map<String, Object>{
                    'success' => false,
                    'message' => 'Unable to save deployment history.'
                }
            )
        );
    }
}