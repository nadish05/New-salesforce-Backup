import { LightningElement } from 'lwc';
export default class HelloWorld extends LightningElement {
        greeting = 'Nadish Babu';
        changeHandler(event) {
        this.greeting = event.target.value;
        }
}