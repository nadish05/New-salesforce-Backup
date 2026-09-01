trigger OpportunityRevenueTrigger on Opportunity (
    after insert, after update, after delete, after undelete
) {

    Set<Id> accountIds = new Set<Id>();

    // Collect Account Ids from Trigger.new
    if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
        for (Opportunity opp : Trigger.new) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
    }

    // Collect Account Ids from Trigger.old (for delete/update cases)
    if (Trigger.isUpdate || Trigger.isDelete) {
        for (Opportunity opp : Trigger.old) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
    }

    if (accountIds.isEmpty()) return;

    // Aggregate total revenue (ONLY Closed Won)
    Map<Id, Decimal> revenueMap = new Map<Id, Decimal>();

    for (AggregateResult ar : [
        SELECT AccountId accId, SUM(Amount) total
        FROM Opportunity
        WHERE AccountId IN :accountIds
        AND StageName = 'Closed Won'
        GROUP BY AccountId
    ]) {
        revenueMap.put((Id) ar.get('accId'), (Decimal) ar.get('total'));
    }

    // Prepare Account updates
    List<Account> accountsToUpdate = new List<Account>();

    for (Id accId : accountIds) {
        Decimal totalRevenue = revenueMap.containsKey(accId) 
            ? revenueMap.get(accId) 
            : 0;

        accountsToUpdate.add(new Account(
            Id = accId,
            Total_Revenue__c = totalRevenue
        ));
    }

    // Single DML → bulk-safe
    if (!accountsToUpdate.isEmpty()) {
        update accountsToUpdate;
    }
}