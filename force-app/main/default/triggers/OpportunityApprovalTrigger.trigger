trigger OpportunityApprovalTrigger on Opportunity (before insert, before update) {

    for (Opportunity opp : Trigger.new) {

        if (opp.Discount__c != null) {

            // ✅ ONLY set Pending if NOT already approved
            if (opp.Discount__c > 20 && opp.Discount__c <= 30) {

                if (opp.Approval_Status__c != 'Approved') {
                    opp.Approval_Status__c = 'Pending';
                }
            }

            // Auto approve if ≤ 20
            else if (opp.Discount__c <= 20) {
                opp.Approval_Status__c = 'Approved';
            }
        }
    }
}