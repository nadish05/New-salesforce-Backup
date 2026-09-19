@IsTest
private class WeatherServiceSuccessTest {

    @IsTest
    static void getResortWeather_works() {
        // Set up test data
        Datetime dateToCheck = Datetime.newInstance(2024, 7, 14);

        // Set up mock HTTP response
        Test.setMock(
            HttpCalloutMock.class,
            new MockSuccessResponse()
        );

        // Call the method to be tested
        Test.startTest();
        WeatherService.Weather weather =
            WeatherService.getResortWeather(dateToCheck);
        Test.stopTest();

        // Assert the results
        Assert.areEqual(10.0, weather.minTemperatureC);
        Assert.areEqual(50.0, weather.minTemperatureF);
        Assert.areEqual(30.0, weather.maxTemperatureC);
        Assert.areEqual(86.0, weather.maxTemperatureF);
        Assert.areEqual(
            'On July 14, temperature should be between 10.0°C (50.0°F) and 30.0°C (86.0°F) at Coral Cloud Resorts.',
            weather.description
        );
    }

    private class MockSuccessResponse implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"weather":[{"temperature":10.0},{"temperature":30.0}]}'
            );
            return res;
        }
    }
}