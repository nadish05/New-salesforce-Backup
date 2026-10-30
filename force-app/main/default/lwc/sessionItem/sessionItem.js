import { LightningElement, api } from 'lwc';

export default class SessionItem extends LightningElement {
    @api session;

    get accountName() {
        return this.session?.Account__r?.Name;
    }

    get trainerName() {
        return this.session?.Gym_Trainer__r?.Name;
    }
}