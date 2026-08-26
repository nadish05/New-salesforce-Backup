/**
 * Maps DeploymentHistoryDTO to Deployment_History__c and performs insert.
 * No REST, JSON parsing, HTTP, or business validation.
 */
public with sharing class DeploymentHistoryService {

    public class SaveResult {
        public Boolean success;
        public Id recordId;
        public String message;

        public SaveResult(Boolean success, Id recordId, String message) {
            this.success = success;
            this.recordId = recordId;
            this.message = message;
        }
    }

    public static SaveResult save(DeploymentHistoryDTO dto) {
        if (dto == null) {
            return new SaveResult(
                false,
                null,
                'Unable to save deployment history.'
            );
        }

        if (!Schema.sObjectType.Deployment_History__c.isCreateable()) {
            System.debug(
                LoggingLevel.ERROR,
                'DeploymentHistoryService: create access denied for Deployment_History__c'
            );
            return new SaveResult(
                false,
                null,
                'Unable to save deployment history.'
            );
        }

        try {
            Deployment_History__c record = mapToRecord(dto);
            insert record;
            return new SaveResult(true, record.Id, null);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'DeploymentHistoryService save failed: ' + e.getMessage()
            );
            // TEMP DEBUG: surface exact Salesforce rejection (revert after diagnosis)
            return new SaveResult(
                false,
                null,
                buildDebugMessage(e)
            );
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

    private static Deployment_History__c mapToRecord(DeploymentHistoryDTO dto) {
        Deployment_History__c record = new Deployment_History__c();

        record.Deployment_ID__c = dto.deploymentId;
        record.Deployment_Mode__c = dto.deploymentMode;
        record.Execution_Mode__c = dto.executionMode;
        record.Deployment_Status__c = dto.status;
        record.Validation_Status__c = resolveValidationStatus(dto);
        record.Started_At__c = parseDateTime(dto.startedAt);
        record.Completed_At__c = parseDateTime(dto.completedAt);
        record.Duration_Display__c = truncate(dto.duration, 30);
        record.Duration_Milliseconds__c = dto.durationMilliseconds;
        record.CLI_Version__c = truncate(dto.cliVersion, 30);
        record.CLI_Command__c = dto.cliCommand;
        record.Deployment_Message__c = dto.deploymentMessage;

        record.Deployment_Plan__c = toLookupId(dto.deploymentPlanId);
        record.Metadata_Comparison__c = toLookupId(dto.metadataComparisonId);
        record.Source_Org__c = resolveConnectedOrgId(dto.sourceOrgId);
        record.Destination_Org__c = resolveConnectedOrgId(dto.destinationOrgId);

        mapDeploymentSummary(record, dto.deploymentSummary);
        resolveComponentsTotal(record, dto);
        mapCounts(record, dto);

        record.Deployment_Summary__c = serializePretty(dto.deploymentSummary);
        record.Validation_Summary__c = serializePretty(dto.validationSummary);
        record.Timeline__c = serializePretty(dto.timeline);
        record.Failure_Details__c = serializePretty(dto.failureDetails);
        record.Test_Results__c = serializePretty(dto.testResults);
        record.CLI_Compatibility__c = serializePretty(dto.cliCompatibility);

        return record;
    }

    private static void mapDeploymentSummary(
        Deployment_History__c record,
        DeploymentHistoryDTO.DeploymentSummaryDTO summary
    ) {
        if (summary == null) {
            return;
        }

        record.Components_Validated__c = toDecimal(summary.componentsValidated);
        record.Components_Deployed__c = toDecimal(summary.componentsDeployed);
        record.Components_Total__c = toDecimal(summary.componentsTotal);
        record.Components_Failed__c = toDecimal(summary.componentsFailed);
        record.Tests_Run__c = toDecimal(summary.testsRun);
        record.Tests_Completed__c = toDecimal(summary.testsCompleted);
        record.Tests_Failed__c = toDecimal(summary.testsFailed);
        record.Overall_Coverage__c = summary.overallCoverage;
    }

    /**
     * Backend deploymentSummary does not include componentsTotal.
     * Prefer metadataSummary.totalComponents from the history payload;
     * otherwise derive from deployed + failed counts already on the summary.
     */
    private static void resolveComponentsTotal(
        Deployment_History__c record,
        DeploymentHistoryDTO dto
    ) {
        if (record.Components_Total__c != null) {
            return;
        }

        if (
            dto.metadataSummary != null &&
            dto.metadataSummary.totalComponents != null
        ) {
            record.Components_Total__c = toDecimal(
                dto.metadataSummary.totalComponents
            );
            return;
        }

        if (dto.deploymentSummary == null) {
            return;
        }

        Integer deployed = dto.deploymentSummary.componentsDeployed;
        Integer failed = dto.deploymentSummary.componentsFailed;

        if (deployed == null && failed == null) {
            return;
        }

        Integer deployedValue = deployed == null ? 0 : deployed;
        Integer failedValue = failed == null ? 0 : failed;
        record.Components_Total__c = Decimal.valueOf(
            deployedValue + failedValue
        );
    }

    private static void mapCounts(
        Deployment_History__c record,
        DeploymentHistoryDTO dto
    ) {
        record.Warning_Count__c =
            dto.warnings == null ? 0 : dto.warnings.size();
        record.Error_Count__c =
            dto.errors == null ? 0 : dto.errors.size();
    }

    private static String resolveValidationStatus(DeploymentHistoryDTO dto) {
        String rawStatus = null;

        if (String.isNotBlank(dto.validationStatus)) {
            rawStatus = dto.validationStatus;
        } else if (dto.validationSummary != null) {
            if (String.isNotBlank(dto.validationSummary.overallStatus)) {
                rawStatus = dto.validationSummary.overallStatus;
            } else if (String.isNotBlank(dto.validationSummary.status)) {
                rawStatus = dto.validationSummary.status;
            }
        }

        if (String.isBlank(rawStatus)) {
            return 'NOT_RUN';
        }

        if (rawStatus == 'READY' || rawStatus == 'READY_WITH_WARNINGS') {
            return 'PASS';
        }

        if (rawStatus == 'BLOCKED') {
            return 'BLOCKED';
        }

        if (
            rawStatus == 'PASS' ||
            rawStatus == 'FAIL' ||
            rawStatus == 'NOT_RUN'
        ) {
            return rawStatus;
        }

        return 'FAIL';
    }

    private static Id toLookupId(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return Id.valueOf(value);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'DeploymentHistoryService: ignoring invalid lookup Id: ' + value
            );
            return null;
        }
    }

    /**
     * Resolves a Salesforce Org Id (00D...) to Connected_Org__c.Id via Org_ID__c.
     * Returns null when blank or when no Connected_Org__c matches.
     */
    private static Id resolveConnectedOrgId(String salesforceOrgId) {
        if (String.isBlank(salesforceOrgId)) {
            return null;
        }

        List<Connected_Org__c> matches = [
            SELECT Id
            FROM Connected_Org__c
            WHERE Org_ID__c = :salesforceOrgId
            LIMIT 1
        ];

        if (matches.isEmpty()) {
            return null;
        }

        return matches[0].Id;
    }

    private static Datetime parseDateTime(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return (Datetime) JSON.deserialize(
                '"' + value + '"',
                Datetime.class
            );
        } catch (Exception e) {
            try {
                String normalized = value.replace('T', ' ').replace('Z', '');
                if (normalized.contains('+')) {
                    normalized = normalized.substring(0, normalized.indexOf('+'));
                }
                if (normalized.contains('.')) {
                    normalized = normalized.substring(0, normalized.indexOf('.'));
                }
                return Datetime.valueOfGmt(normalized.trim());
            } catch (Exception ex) {
                System.debug(
                    LoggingLevel.WARN,
                    'DeploymentHistoryService: unable to parse datetime: ' + value
                );
                return null;
            }
        }
    }

    private static Decimal toDecimal(Integer value) {
        return value == null ? null : Decimal.valueOf(value);
    }

    private static String serializePretty(Object value) {
        if (value == null) {
            return null;
        }
        return JSON.serializePretty(value);
    }

    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value) || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }
}