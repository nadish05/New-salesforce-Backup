public without sharing class SessionController {

    @AuraEnabled(cacheable=true)
    public static List<Session__c> getSessions() {
        return [
            SELECT Id,
                   Status__c,
                   Session_Type__c,
                   Account__r.Name,
                   Gym_Trainer__r.Name
            FROM Session__c
            WHERE Account__c != NULL
            AND Gym_Trainer__c != NULL
            ORDER BY CreatedDate DESC
        ];
    }
}