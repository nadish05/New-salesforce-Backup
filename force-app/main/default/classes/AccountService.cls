public class AccountService {

    public static void createAccounts(List<Account> accList) {

        if(accList == null || accList.isEmpty()) return;

        List<Error_Log__c> logs = new List<Error_Log__c>();

        // Partial insert (does not fail entire transaction)
        Database.SaveResult[] results = Database.insert(accList, false);

        for(Integer i = 0; i < results.size(); i++) {

            if(!results[i].isSuccess()) {

                for(Database.Error err : results[i].getErrors()) {

                    logs.add(new Error_Log__c(
                        Message__c = err.getMessage(),
                        StackTrace__c = err.getStatusCode() + ''
                    ));
                }
            }
        }

        // Single DML for logs
        if(!logs.isEmpty()) {
            insert logs;
        }
    }
}