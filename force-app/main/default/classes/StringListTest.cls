public class StringListTest {
    public static List<String> generateStringList(Integer n) {
        List<String> result = new List<String>();

        for (Integer i = 0; i < n; i++) {
            result.add('Test ' + i);
        }

        return result;
    }
}