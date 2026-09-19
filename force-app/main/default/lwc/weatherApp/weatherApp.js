import { LightningElement, wire } from 'lwc';
import getWeather from '@salesforce/apex/WeatherServicedemo.getWeather';

export default class WeatherApp extends LightningElement {

    weather;
    error;

    @wire(getWeather)
    wiredWeather({ data, error }) {
        if (data) {
            this.weather = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.weather = undefined;
            console.error('ERROR:', error);
        }
    }

    // 👉 ADD THIS
    get isLoading() {
        return !this.weather && !this.error;
    }
}