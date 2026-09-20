public class JsonParserExample {

    public static void parseJson() {

        String jsonString = '{"name": "John", "age": 30}';

        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(jsonString);

        System.debug('Name: ' + (String)data.get('name'));
        System.debug('Age: ' + (Integer)data.get('age'));
    }
}