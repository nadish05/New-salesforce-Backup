import { LightningElement } from 'lwc';

export default class ConditionalMessage extends LightningElement {
    amount = 0;

    handleChange(event) {
        this.amount = Number(event.target.value) || 0;
    }

    get isHighValue() {
        return this.amount > 5000;
    }
}