public class AccountService1 {

    public static Map<Id, Integer> getHighRevenueAccounts() {

        Map<Id, Integer> result = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT AccountId accId, COUNT(Id) oppCount
            FROM Opportunity
            WHERE Account.Total_Revenue__c > 50000
            GROUP BY AccountId
        ]) {
            result.put(
                (Id) ar.get('accId'),
                (Integer) ar.get('oppCount')
            );
        }

        return result;
    }
}