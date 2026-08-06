public with sharing class PaymentRefundController {

    @AuraEnabled
    public static void requestRefund(Id paymentId) {

        if (paymentId == null) {
            throw new AuraHandledException('Invalid payment.');
        }

        Payment__c payment = [
            SELECT Id, Refunded__c, Refund_Status__c
            FROM Payment__c
            WHERE Id = :paymentId
            LIMIT 1
        ];

        if (payment.Refunded__c) {
            throw new AuraHandledException('Payment already refunded.');
        }

        if (payment.Refund_Status__c == 'Requested') {
            throw new AuraHandledException('Refund already requested.');
        }

        // ✅ THIS IS REQUIRED
        payment.Refund_Status__c = 'Requested';
        update payment;

        // ✅ Submit for approval
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(payment.Id);
        req.setComments('Refund requested via Refund button');
        req.setSubmitterId(UserInfo.getUserId());

        Approval.ProcessResult result = Approval.process(req);

        if (!result.isSuccess()) {
            throw new AuraHandledException('Approval submission failed.');
        }
    }
}