import { LightningElement } from 'lwc';

export default class GstCalculator extends LightningElement {
    amount = 0;

    handleChange(event) {
        this.amount = Number(event.target.value) || 0;
    }

    get gst() {
        return this.amount * 0.18;
    }

    get total() {
        return this.amount + this.gst;
    }
}