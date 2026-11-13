public class AccountTriggerHandler {
    
    public static void CreateAccounts (List<Account> acclist)
    {
        for(Account acc : acclist)
        {
            if (acc.ShippingState!=acc.billingState)
            {
                acc.ShippingState = acc.BillingState;
            }
        }
    }

}