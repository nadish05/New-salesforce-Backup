public class AccountHandler {
    public static Account insertNewAccount(String accountName) {
        Account acc = new Account(Name = accountName);

        try {
            insert acc;
            return acc;
        } catch (DmlException e) {
            return null;
        }
    }
}