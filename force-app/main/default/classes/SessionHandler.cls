public class SessionHandler {

    public static void sendEmailOnCreate(List<Session__c> sessions) {

        if (sessions == null || sessions.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        Set<Id> trainerIds = new Set<Id>();

        for (Session__c s : sessions) {
            if (s.Account__c != null) {
                accountIds.add(s.Account__c);
            }
            if (s.Gym_Trainer__c != null) {
                trainerIds.add(s.Gym_Trainer__c);
            }
        }

        Map<Id, Account> accMap = new Map<Id, Account>(
            [SELECT Id, Name FROM Account WHERE Id IN :accountIds]
        );

        Map<Id, Gym_Trainer__c> trainerMap = new Map<Id, Gym_Trainer__c>(
            [SELECT Id, Name FROM Gym_Trainer__c WHERE Id IN :trainerIds]
        );

        String body = '<h2>New Sessions Created</h2>';

        for (Session__c s : sessions) {

            String accName = accMap.containsKey(s.Account__c)
                ? accMap.get(s.Account__c).Name
                : 'N/A';

            String trainerName = trainerMap.containsKey(s.Gym_Trainer__c)
                ? trainerMap.get(s.Gym_Trainer__c).Name
                : 'N/A';

            // Format Date
            String sessionDate = s.Session_Date__c != null
                ? String.valueOf(s.Session_Date__c)
                : 'N/A';

            // Format Time (manual)
            String startTime = 'N/A';
            if (s.Start_Time__c != null) {
                Integer h = s.Start_Time__c.hour();
                Integer m = s.Start_Time__c.minute();
                startTime = String.valueOf(h) + ':' + (m < 10 ? '0' + String.valueOf(m) : String.valueOf(m));
            }

            String endTime = 'N/A';
            if (s.End_Time__c != null) {
                Integer h = s.End_Time__c.hour();
                Integer m = s.End_Time__c.minute();
                endTime = String.valueOf(h) + ':' + (m < 10 ? '0' + String.valueOf(m) : String.valueOf(m));
            }

            body += '<table border="1" cellpadding="5" cellspacing="0" style="border-collapse:collapse; margin-bottom:15px;">';
            body += '<tr><th>Field</th><th>Value</th></tr>';
            body += '<tr><td>Session Name</td><td>' + s.Name + '</td></tr>';
            body += '<tr><td>Member</td><td>' + accName + '</td></tr>';
            body += '<tr><td>Trainer</td><td>' + trainerName + '</td></tr>';
            body += '<tr><td>Session Date</td><td>' + sessionDate + '</td></tr>';
            body += '<tr><td>Start Time</td><td>' + startTime + '</td></tr>';
            body += '<tr><td>End Time</td><td>' + endTime + '</td></tr>';
            body += '<tr><td>Status</td><td>' + s.Status__c + '</td></tr>';
            body += '</table>';
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{'bnadish1@gmail.com'});
        mail.setSubject('New Sessions Created (' + sessions.size() + ')');
        mail.setHtmlBody(body);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{mail});
    }
}