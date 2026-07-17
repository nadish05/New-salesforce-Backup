trigger OpportunityTrigger on Opportunity (after insert, after update, after delete, after undelete) {

    // ===== 1. ACCOUNT ROLLUP LOGIC =====
    Set<Id> accountIds = new Set<Id>();

    if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
        for (Opportunity opp : Trigger.new) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
    }

    if (Trigger.isUpdate || Trigger.isDelete) {
        for (Opportunity opp : Trigger.old) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
    }

    if (!accountIds.isEmpty()) {
        OpportunityHandler.updateAccountTotals(accountIds);
    }

    // ===== 2. HIGH VALUE APPROVAL LOGIC =====
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        OpportunityHandler.handleHighValueOpps(Trigger.new, Trigger.oldMap, Trigger.isInsert);
    }
}