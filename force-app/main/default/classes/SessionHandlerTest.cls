@isTest
public class SessionHandlerTest {

    @isTest
    static void testSessionEmailTrigger() {

        Account acc = new Account(Name = 'Test Member');
        insert acc;

        Gym_Trainer__c trainer = new Gym_Trainer__c(Name = 'Test Trainer');
        insert trainer;

        List<Session__c> sessions = new List<Session__c>();

        for (Integer i = 0; i < 5; i++) {
            sessions.add(new Session__c(
                Account__c = acc.Id,
                Gym_Trainer__c = trainer.Id,
                Session_Date__c = Date.today()
            ));
        }

        Test.startTest();
        insert sessions;
        Test.stopTest();

        System.assertEquals(5, [SELECT COUNT() FROM Session__c]);

        // Only ONE email should be sent
        System.assertEquals(1, Limits.getEmailInvocations());
    }
}