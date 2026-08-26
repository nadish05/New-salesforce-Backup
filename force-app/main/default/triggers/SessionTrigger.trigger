trigger SessionTrigger on Session__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        SessionHandler.sendEmailOnCreate(Trigger.new);
    }
}