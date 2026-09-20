import { LightningElement } from 'lwc';

export default class Counter extends LightningElement {
    count = 0;

    handleClick() {
        this.count += 1;
    }
}