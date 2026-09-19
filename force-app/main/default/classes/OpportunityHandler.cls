public class OpportunityHandler {

    // =========================
    // 1. ACCOUNT ROLLUP LOGIC
    // =========================
    public static void updateAccountTotals(Set<Id> accountIds) {

        Map<Id, Decimal> accountToTotal = new Map<Id, Decimal>();

        for (AggregateResult ar : [
            SELECT AccountId, SUM(Amount) total
            FROM Opportunity
            WHERE AccountId IN :accountIds
            GROUP BY AccountId
        ]) {
            accountToTotal.put((Id) ar.get('AccountId'), (Decimal) ar.get('total'));
        }

        List<Account> accountsToUpdate = new List<Account>();

        for (Id accId : accountIds) {
            Decimal total = accountToTotal.containsKey(accId) ? accountToTotal.get(accId) : 0;

            accountsToUpdate.add(new Account(
                Id = accId,
                Total_Opportunity_Amount__c = total
            ));
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }

    // =========================
    // 2. APPROVAL + EMAIL LOGIC
    // =========================
    public static void handleHighValueOpps(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap, Boolean isInsert) {

        List<Opportunity> eligibleOpps = new List<Opportunity>();

        for (Opportunity opp : newOpps) {

            if (opp.Amount == null) continue;

            // 🔥 INSERT case
            if (isInsert && opp.Amount > 1000000) {
                eligibleOpps.add(opp);
            }

            // 🔥 UPDATE case (prevent duplicate submission)
            else if (!isInsert) {
                Opportunity oldOpp = oldMap.get(opp.Id);

                if (oldOpp != null &&
                    oldOpp.Amount <= 1000000 &&
                    opp.Amount > 1000000) {

                    eligibleOpps.add(opp);
                }
            }
        }

        if (eligibleOpps.isEmpty()) return;

        // ===== Submit for Approval =====
        for (Opportunity opp : eligibleOpps) {

            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(opp.Id);
            req.setComments('Auto-submitted for high value opportunity');

            try {
    		Approval.process(req);
			} catch (Exception e) {
    			System.debug('Approval failed: ' + e.getMessage());
			}
        }

        // ===== Send Email =====
        
    }
}