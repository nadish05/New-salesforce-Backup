public class DependencyReviewResult {

    @AuraEnabled
    public String status;

    @AuraEnabled
    public List<String> dependencies;

    @AuraEnabled
    public List<String> validations;

    @AuraEnabled
    public Decimal coveragePercentage;

    public DependencyReviewResult() {

        status = 'Pending';

        dependencies = new List<String>();

        validations = new List<String>();

        coveragePercentage = 0;

    }

}