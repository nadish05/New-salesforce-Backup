import { LightningElement, api } from 'lwc';
import requestRefund from '@salesforce/apex/PaymentRefundController.requestRefund';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';

export default class RefundPayment extends LightningElement {
    @api recordId;

    handleRefund() {
        requestRefund({ paymentId: this.recordId })
            .then(() => {
                this.showToast(
                    'Success',
                    'Refund request submitted for approval.',
                    'success'
                );

                getRecordNotifyChange([{ recordId: this.recordId }]);
            })
            .catch(error => {
                this.showToast(
                    'Error',
                    error.body.message,
                    'error'
                );
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}