/**
 * REST entry point for Deployment History persistence.
 * POST creates. GET/PATCH support CONTROL_ORG history store operations.
 * Persistence only — does not execute rollback.
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
                'DeploymentHistoryApi error: ' + e.getTypeName()
            );
            writeError(response, 500);
        }
    }

    @HttpGet
    global static void getDeploymentHistory() {
        RestResponse response = ensureResponse();
        try {
            RestRequest request = RestContext.request;
            String historyId = historyIdFromRequest(request);
            Map<String, String> params =
                request == null ? new Map<String, String>() : request.params;
            if (params == null) {
                params = new Map<String, String>();
            }

            DeploymentHistoryService.RecordResult result;
            if (String.isNotBlank(historyId)) {
                result = DeploymentHistoryService.getByHistoryId(historyId);
            } else if (String.isNotBlank(params.get('snapshotId'))) {
                result = DeploymentHistoryService.findBySnapshotId(
                    params.get('snapshotId')
                );
            } else if (
                String.isNotBlank(params.get('salesforceDeploymentId')) ||
                String.isNotBlank(params.get('deploymentId'))
            ) {
                String deploymentId =
                    String.isNotBlank(params.get('salesforceDeploymentId'))
                        ? params.get('salesforceDeploymentId')
                        : params.get('deploymentId');
                result = DeploymentHistoryService.findBySalesforceDeploymentId(
                    deploymentId
                );
            } else {
                result = DeploymentHistoryService.listRecent();
            }

            writeRecordResult(response, result);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'DeploymentHistoryApi GET error: ' + e.getTypeName()
            );
            writeNamedError(response, 500, 'INVALID_REQUEST', 'Unable to read deployment history.');
        }
    }

    @HttpPatch
    global static void updateDeploymentHistory() {
        RestResponse response = ensureResponse();
        try {
            RestRequest request = RestContext.request;
            String historyId = historyIdFromRequest(request);
            String body =
                request == null || request.requestBody == null
                    ? null
                    : request.requestBody.toString();

            if (String.isBlank(historyId) || String.isBlank(body)) {
                writeNamedError(
                    response,
                    400,
                    'INVALID_REQUEST',
                    'Unable to update deployment history.'
                );
                return;
            }

            DeploymentHistoryDTO dto =
                (DeploymentHistoryDTO) JSON.deserialize(
                    body,
                    DeploymentHistoryDTO.class
                );
            DeploymentHistoryService.RecordResult result =
                DeploymentHistoryService.updateByHistoryId(historyId, dto);
            writeRecordResult(response, result);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'DeploymentHistoryApi PATCH error: ' + e.getTypeName()
            );
            writeNamedError(
                response,
                500,
                'INVALID_REQUEST',
                'Unable to update deployment history.'
            );
        }
    }

    private static RestResponse ensureResponse() {
        RestResponse response = RestContext.response;
        if (response == null) {
            response = new RestResponse();
            RestContext.response = response;
        }
        response.addHeader('Content-Type', 'application/json');
        return response;
    }

    private static String historyIdFromRequest(RestRequest request) {
        if (request == null || String.isBlank(request.requestURI)) {
            return null;
        }
        String uri = request.requestURI;
        Integer marker = uri.indexOf('/deployment-history/');
        if (marker < 0) {
            return null;
        }
        String remainder =
            uri.substring(marker + '/deployment-history/'.length());
        if (String.isBlank(remainder)) {
            return null;
        }
        List<String> parts = remainder.split('/');
        for (String part : parts) {
            if (String.isNotBlank(part)) {
                return EncodingUtil.urlDecode(part, 'UTF-8');
            }
        }
        return null;
    }

    private static void writeRecordResult(
        RestResponse response,
        DeploymentHistoryService.RecordResult result
    ) {
        if (result == null) {
            writeNamedError(
                response,
                500,
                'INVALID_REQUEST',
                'Unable to read deployment history.'
            );
            return;
        }
        if (result.success != true) {
            Integer statusCode = 400;
            if (result.code == 'NOT_FOUND') {
                statusCode = 404;
            } else if (result.code == 'UNAUTHORIZED') {
                statusCode = 403;
            }
            writeNamedError(response, statusCode, result.code, result.message);
            return;
        }

        Map<String, Object> payload = new Map<String, Object>{
            'success' => true,
            'code' => result.code,
            'message' => result.message,
            'recordId' => result.recordId
        };
        if (result.record != null) {
            payload.put('record', result.record);
        }
        if (result.records != null) {
            payload.put('records', result.records);
        }
        response.statusCode = 200;
        response.responseBody = Blob.valueOf(JSON.serialize(payload));
    }

    private static void writeNamedError(
        RestResponse response,
        Integer statusCode,
        String code,
        String message
    ) {
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(
            JSON.serialize(
                new Map<String, Object>{
                    'success' => false,
                    'code' => code,
                    'message' => message
                }
            )
        );
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