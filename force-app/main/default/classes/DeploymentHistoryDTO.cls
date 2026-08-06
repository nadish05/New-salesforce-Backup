/**
 * Strongly typed DTO for Deployment History persistence payloads.
 * Types aligned to Backend-Metadata deploymentHistory.service.js JSON.
 */
public class DeploymentHistoryDTO {

    public String historyId;
    public String deploymentId;
    public String deploymentMode;
    public String executionMode;
    public String status;
    public String validationStatus;
    public String startedAt;
    public String completedAt;
    public String duration;
    public Decimal durationMilliseconds;
    public String cliVersion;
    public String cliCommand;
    public String deploymentMessage;

    public String deploymentPlanId;
    public String metadataComparisonId;
    public String sourceOrgId;
    public String destinationOrgId;

    public String sourceBranch;
    public String destinationBranch;
    public String repoUrl;
    public String workspacePath;

    public DeploymentSummaryDTO deploymentSummary;
    public ValidationSummaryDTO validationSummary;
    public SummaryDTO summary;
    public List<TimelineDTO> timeline;
    public List<FailureIssueDTO> failureDetails;
    public List<String> warnings;
    public List<String> errors;
    public TestResultsDTO testResults;
    public CliCompatibilityDTO cliCompatibility;
    public MetadataSummaryDTO metadataSummary;
    public ManifestSummaryDTO manifestSummary;
    public WorkspaceSummaryDTO workspaceSummary;

    public class SummaryDTO {
        public Integer metadataCount;
        public Integer dependencyCount;
        public Integer componentsValidated;
        public Boolean workspaceCreated;
        public String deploymentMode;
        public String deploymentStatus;
    }

    public class DeploymentSummaryDTO {
        public Integer componentsValidated;
        public Integer componentsDeployed;
        public Integer componentsTotal;
        public Integer componentsFailed;
        public Integer testsRun;
        public Integer testsCompleted;
        public Integer testsFailed;
        public Decimal overallCoverage;
        public String deploymentStatus;
        public String message;
        public String status;
    }

    public class ValidationSummaryDTO {
        public String destinationConnectivity;
        public String metadataValidation;
        public String dependencyValidation;
        public String overallStatus;
        public Boolean canDeploy;
        public String status;
        public String message;
        public Integer componentsValidated;
        public Integer componentsFailed;
    }

    /** Backend timeline item: { "stage": "...", "timestamp": "..." } */
    public class TimelineDTO {
        public String stage;
        public String timestamp;
        public String name;
        public String status;
        public String message;
        public Decimal durationMilliseconds;
    }

    public class FailureIssueDTO {
        public String componentName;
        public String metadataType;
        public String problem;
        public String file;
        public Decimal line;
        public Decimal column;
    }

    public class FailureDetailsDTO {
        public List<IssueDTO> componentFailures;
        public List<IssueDTO> errors;
        public String message;
        public String problem;
    }

    public class IssueDTO {
        public String message;
        public String code;
        public String severity;
        public String componentName;
        public String fileName;
        public String filePath;
        public String metadataType;
        public String problemType;
        public String lineNumber;
        public String problem;
    }

    public class WarningDTO {
        public String message;
        public String code;
        public String severity;
        public String componentName;
        public String fileName;
        public String filePath;
        public String metadataType;
        public String problemType;
        public String lineNumber;
    }

    public class ErrorDTO {
        public String message;
        public String code;
        public String severity;
        public String componentName;
        public String fileName;
        public String filePath;
        public String metadataType;
        public String problemType;
        public String lineNumber;
        public String problem;
    }

    public class TestResultsDTO {
        public Integer testsRun;
        public Integer testsPassed;
        public Integer testsCompleted;
        public Integer testsFailed;
        public Decimal overallCoverage;
        public List<TestResultItemDTO> results;
        public List<TestResultItemDTO> failingTests;
    }

    public class TestResultItemDTO {
        public String className;
        public String methodName;
        public String status;
        public String message;
        public Decimal coverage;
    }

    public class CliCompatibilityDTO {
        public String cliVersion;
        public String deploymentValidationFlag;
        public Boolean supportsDryRun;
        public Boolean supportsCheckOnly;
        public String detectionSource;
        public Boolean cached;
        public String detectedAt;
    }

    public class MetadataSummaryDTO {
        public Integer totalComponents;
        public Integer metadataCount;
        public Integer dependencyCount;
        public Integer testClassCount;
        public List<String> metadataTypes;
        public String message;
    }

    public class ManifestSummaryDTO {
        public Integer packageCount;
        public Integer metadataTypes;
        public Integer members;
        public String apiVersion;
        public String packageXml;
        public String message;
    }

    public class WorkspaceSummaryDTO {
        public String workspacePath;
        public String branchName;
        public String message;
        public Boolean workspaceCreated;
        public String status;
        public Integer metadataCopied;
        public Integer dependenciesCopied;
        public Integer copiedFiles;
        public String workspaceSize;
        public List<String> missingFiles;
    }
}