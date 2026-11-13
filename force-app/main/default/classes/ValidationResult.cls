public with sharing class ValidationResult {

    @AuraEnabled
    public String status;

    @AuraEnabled
    public List<String> messages;

    public ValidationResult() {

        status = 'Pending';

        messages = new List<String>();

    }

}