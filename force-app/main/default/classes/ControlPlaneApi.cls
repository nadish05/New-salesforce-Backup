/**
 * Apex REST boundary for Product/Control Org persistence.
 *
 * Authentication: Salesforce session of the calling integration user.
 * Node ↔ Product Org Connected App / Named Credential wiring is TBC.
 * Does not accept destination refresh tokens as actor identity.
 * Does not expose adminRelease.
 * Does not execute rollback.
 *
 * Artifact bytes use Salesforce Files (ContentVersion.VersionData).
 * Binary upload/download is not JSON-encoded.
 */
@RestResource(urlMapping='/control-plane/*')
global with sharing class ControlPlaneApi {

    @HttpPost
    global static void handlePost() {
        dispatch('POST');
    }

    @HttpPut
    global static void handlePut() {
        dispatch('PUT');
    }

    @HttpGet
    global static void handleGet() {
        dispatch('GET');
    }

    @HttpPatch
    global static void handlePatch() {
        dispatch('PATCH');
    }

    private static void dispatch(String method) {
        RestResponse response = RestContext.response;
        if (response == null) {
            response = new RestResponse();
            RestContext.response = response;
        }
        response.addHeader('Content-Type', 'application/json');

        try {
            RestRequest request = RestContext.request;
            List<String> parts = pathParts(request);

            if (isArtifactBytesGet(method, parts)) {
                handleArtifactBytesGet(response, parts);
                return;
            }
            if (isArtifactUpload(method, parts)) {
                handleArtifactUpload(response, request, parts);
                return;
            }

            Map<String, Object> rawBody = readBody(request);

            if (ControlPlaneSanitize.containsForbiddenKey(rawBody)) {
                write(
                    response,
                    400,
                    ControlPlaneResult.fail(
                        'INVALID_REQUEST',
                        'Credential fields are not accepted.'
                    )
                );
                return;
            }

            Map<String, Object> body = ControlPlaneSanitize.sanitize(rawBody);
            ControlPlaneResult result = route(method, parts, body);
            write(response, statusCodeFor(result), result);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'ControlPlaneApi error: ' + e.getTypeName()
            );
            write(
                response,
                500,
                ControlPlaneResult.fail(
                    'INVALID_REQUEST',
                    'Unable to process control-plane request.'
                )
            );
        }
    }

    private static ControlPlaneResult route(
        String method,
        List<String> parts,
        Map<String, Object> body
    ) {
        if (parts.isEmpty()) {
            return ControlPlaneResult.fail('INVALID_REQUEST', 'Unknown route.');
        }

        String root = parts[0];
        if (root == 'snapshots') {
            return routeSnapshots(method, parts, body);
        }
        if (root == 'operations') {
            return routeOperations(method, parts, body);
        }
        if (root == 'locks') {
            return routeLocks(method, parts, body);
        }
        return ControlPlaneResult.fail('INVALID_REQUEST', 'Unknown route.');
    }

    private static ControlPlaneResult routeSnapshots(
        String method,
        List<String> parts,
        Map<String, Object> body
    ) {
        if (method == 'POST' && parts.size() == 1) {
            return DeploymentSnapshotService.createSnapshot(body);
        }
        if (parts.size() < 2) {
            return ControlPlaneResult.fail('INVALID_REQUEST', 'Unknown route.');
        }

        String snapshotId = parts[1];
        if (method == 'GET' && parts.size() == 2) {
            return DeploymentSnapshotService.getSnapshot(snapshotId);
        }
        if (method == 'PATCH' && parts.size() == 2) {
            return DeploymentSnapshotService.updateSnapshot(snapshotId, body);
        }
        if (method == 'POST' && parts.size() == 3 && parts[2] == 'members') {
            return DeploymentSnapshotService.addMember(snapshotId, body);
        }
        if (method == 'GET' && parts.size() == 3 && parts[2] == 'members') {
            return DeploymentSnapshotService.getMembers(snapshotId);
        }
        if (method == 'POST' && parts.size() == 3 && parts[2] == 'seal') {
            return DeploymentSnapshotService.sealSnapshot(snapshotId);
        }
        if (method == 'GET' &&
            parts.size() == 5 &&
            parts[2] == 'artifacts' &&
            parts[4] == 'metadata') {
            return DeploymentSnapshotArtifactService.getArtifactMetadataById(
                snapshotId,
                parts[3]
            );
        }
        if (method == 'GET' &&
            parts.size() == 5 &&
            parts[2] == 'artifacts' &&
            parts[4] == 'exists') {
            return DeploymentSnapshotArtifactService.existsArtifactById(
                snapshotId,
                parts[3]
            );
        }
        return ControlPlaneResult.fail('INVALID_REQUEST', 'Unknown route.');
    }

    private static ControlPlaneResult routeOperations(
        String method,
        List<String> parts,
        Map<String, Object> body
    ) {
        if (method == 'POST' && parts.size() == 1) {
            return RollbackOperationService.createOperation(body);
        }
        if (method == 'GET' && parts.size() == 2) {
            return RollbackOperationService.getOperation(parts[1]);
        }
        if (method == 'GET' && parts.size() == 1) {
            Map<String, String> params =
                RestContext.request == null
                    ? new Map<String, String>()
                    : RestContext.request.params;
            String destinationOrgId =
                params == null ? null : params.get('destinationOrgId');
            String snapshotId =
                params == null ? null : params.get('snapshotId');
            if (String.isBlank(destinationOrgId)) {
                destinationOrgId = textValue(body.get('destinationOrgId'));
            }
            if (String.isBlank(snapshotId)) {
                snapshotId = textValue(body.get('snapshotId'));
            }
            return RollbackOperationService.findByDestinationAndSnapshot(
                destinationOrgId,
                snapshotId
            );
        }
        if (method == 'PATCH' && parts.size() == 2) {
            return RollbackOperationService.updateOperation(parts[1], body);
        }
        if (method == 'POST' && parts.size() == 3 && parts[2] == 'claim') {
            return RollbackOperationService.claimOperation(parts[1]);
        }
        if (method == 'POST' &&
            parts.size() == 3 &&
            parts[2] == 'in-progress') {
            return RollbackOperationService.transitionToInProgress(parts[1]);
        }
        if (method == 'POST' &&
            parts.size() == 3 &&
            parts[2] == 'execution-started') {
            return RollbackOperationService.markExecutionStarted(parts[1]);
        }
        if (method == 'POST' && parts.size() == 3 && parts[2] == 'terminal') {
            return RollbackOperationService.markTerminal(
                parts[1],
                textValue(body.get('status')),
                textValue(body.get('resultCode')),
                textValue(body.get('resultMessage'))
            );
        }
        return ControlPlaneResult.fail('INVALID_REQUEST', 'Unknown route.');
    }

    private static ControlPlaneResult routeLocks(
        String method,
        List<String> parts,
        Map<String, Object> body
    ) {
        if (method == 'POST' && parts.size() == 2 && parts[1] == 'acquire') {
            return DestinationOrgLockService.acquire(body);
        }
        if (method == 'POST' && parts.size() == 2 && parts[1] == 'renew') {
            return DestinationOrgLockService.renew(body);
        }
        if (method == 'POST' && parts.size() == 2 && parts[1] == 'release') {
            return DestinationOrgLockService.release(body);
        }
        if (method == 'GET' && parts.size() == 2) {
            return DestinationOrgLockService.getLock(parts[1]);
        }
        return ControlPlaneResult.fail('INVALID_REQUEST', 'Unknown route.');
    }

    private static Boolean isArtifactUpload(String method, List<String> parts) {
        return (method == 'POST' || method == 'PUT') &&
            parts != null &&
            parts.size() == 3 &&
            parts[0] == 'snapshots' &&
            parts[2] == 'artifacts';
    }

    private static Boolean isArtifactBytesGet(String method, List<String> parts) {
        return method == 'GET' &&
            parts != null &&
            parts.size() == 4 &&
            parts[0] == 'snapshots' &&
            parts[2] == 'artifacts';
    }

    private static void handleArtifactUpload(
        RestResponse response,
        RestRequest request,
        List<String> parts
    ) {
        String snapshotId = parts[1];
        String artifactId = readArtifactId(request);
        Blob versionData = request == null ? null : request.requestBody;
        ControlPlaneResult result =
            DeploymentSnapshotArtifactService.storeArtifactById(
                snapshotId,
                artifactId,
                versionData
            );
        write(response, statusCodeFor(result), result);
    }

    private static void handleArtifactBytesGet(
        RestResponse response,
        List<String> parts
    ) {
        ControlPlaneResult result =
            DeploymentSnapshotArtifactService.getArtifactBytesById(
                parts[1],
                parts[3]
            );
        if (result != null &&
            result.success == true &&
            result.artifactBytes != null) {
            writeBinary(response, result);
            return;
        }
        write(response, statusCodeFor(result), result);
    }

    private static String readArtifactId(RestRequest request) {
        if (request == null) {
            return null;
        }
        if (request.params != null &&
            String.isNotBlank(request.params.get('artifactId'))) {
            return request.params.get('artifactId');
        }
        if (request.headers == null) {
            return null;
        }
        String fromHeader = request.headers.get('X-Control-Plane-Artifact-Id');
        if (String.isBlank(fromHeader)) {
            fromHeader = request.headers.get('x-control-plane-artifact-id');
        }
        return fromHeader;
    }

    private static List<String> pathParts(RestRequest request) {
        List<String> parts = new List<String>();
        if (request == null || String.isBlank(request.requestURI)) {
            return parts;
        }
        String uri = request.requestURI;
        Integer marker = uri.indexOf('/control-plane/');
        String remainder = marker >= 0
            ? uri.substring(marker + '/control-plane/'.length())
            : '';
        for (String part : remainder.split('/')) {
            if (String.isNotBlank(part)) {
                parts.add(EncodingUtil.urlDecode(part, 'UTF-8'));
            }
        }
        return parts;
    }

    private static Map<String, Object> readBody(RestRequest request) {
        if (request == null ||
            request.requestBody == null ||
            String.isBlank(request.requestBody.toString())) {
            return new Map<String, Object>();
        }
        Object untyped = JSON.deserializeUntyped(request.requestBody.toString());
        if (untyped instanceof Map<String, Object>) {
            return (Map<String, Object>) untyped;
        }
        return new Map<String, Object>();
    }

    private static void write(
        RestResponse response,
        Integer statusCode,
        ControlPlaneResult result
    ) {
        response.statusCode = statusCode;
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(
            JSON.serialize(result == null
                ? ControlPlaneResult.fail('INVALID_REQUEST', 'Unknown error.')
                    .toMap()
                : result.toMap())
        );
    }

    private static void writeBinary(
        RestResponse response,
        ControlPlaneResult result
    ) {
        response.statusCode = 200;
        response.addHeader('Content-Type', 'application/octet-stream');
        if (String.isNotBlank(result.artifactId)) {
            response.addHeader(
                'X-Control-Plane-Artifact-Id',
                result.artifactId
            );
        }
        if (result.artifactSize != null) {
            response.addHeader(
                'X-Control-Plane-Artifact-Size',
                String.valueOf(result.artifactSize.intValue())
            );
        }
        response.responseBody = result.artifactBytes;
    }

    private static Integer statusCodeFor(ControlPlaneResult result) {
        if (result == null) {
            return 500;
        }
        if (result.success == true) {
            return 200;
        }
        if (result.code == 'NOT_FOUND') {
            return 404;
        }
        if (result.code == 'UNAUTHORIZED') {
            return 403;
        }
        if (result.code == 'CONFLICT' || result.code == 'DUPLICATE_VALUE') {
            return 409;
        }
        if (result.code == 'SEALED' || result.code == 'INVALID_STATE') {
            return 409;
        }
        return 400;
    }

    private static String textValue(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }
}