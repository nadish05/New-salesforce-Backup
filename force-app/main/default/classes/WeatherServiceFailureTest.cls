@IsTest
private class WeatherServiceFailureTest {

    @IsTest
    static void getResortWeather_failsWithError() {

        // Set up mock HTTP response
        Test.setMock(
            HttpCalloutMock.class,
            new MockFailureResponse()
        );

        // Call the method to be tested
        Test.startTest();
        try {
            WeatherService.getResortWeather(
                Datetime.newInstance(2024, 7, 14)
            );
            Assert.fail('Expected CalloutException');
        } catch (CalloutException e) {
            System.assert(
                e.getMessage().startsWith('Bad response')
            );
        }
        Test.stopTest();
    }

    private class MockFailureResponse implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('');
            return res;
        }
    }
}