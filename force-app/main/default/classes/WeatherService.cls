public with sharing class WeatherService {

    @AuraEnabled(cacheable=true)
    public static WeatherWrapper getWeather() {

        // Get API Key from Custom Metadata
        Weather_Config__mdt config = Weather_Config__mdt.getInstance('Default');

        if (config == null) {
            throw new AuraHandledException('Custom Metadata not found');
        }

        String apiKey = config.api_key__c;

        Http http = new Http();
        HttpRequest req = new HttpRequest();

        req.setEndpoint(
            'callout:Weather/data/2.5/weather?q=Chennai&appid=' 
            + apiKey + 
            '&units=metric'
        );
        req.setMethod('GET');

        HttpResponse res = http.send(req);

        System.debug('STATUS: ' + res.getStatusCode());
        System.debug('BODY: ' + res.getBody());

        if (res.getStatusCode() == 200) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

            Map<String, Object> main = (Map<String, Object>) data.get('main');
            List<Object> weatherList = (List<Object>) data.get('weather');
            Map<String, Object> weather = (Map<String, Object>) weatherList[0];

            WeatherWrapper result = new WeatherWrapper();
            result.temperature = String.valueOf(main.get('temp'));
            result.condition = (String) weather.get('description');

            return result;

        } else {
            throw new AuraHandledException('API Error: ' + res.getBody());
        }
    }

    public class WeatherWrapper {
        @AuraEnabled public String temperature;
        @AuraEnabled public String condition;
    }
}