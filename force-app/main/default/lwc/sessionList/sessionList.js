import { LightningElement, wire } from 'lwc';
import getSessions from '@salesforce/apex/SessionController.getSessions';

export default class SessionList extends LightningElement {
    sessions;
    error;

    @wire(getSessions)
    wiredSessions({ data, error }) {
    if (data) {
        this.sessions = data;
        console.log('DATA:', data);
    } else if (error) {
        this.error = error;
        console.error('FULL ERROR:', JSON.stringify(error));
    }
}
}