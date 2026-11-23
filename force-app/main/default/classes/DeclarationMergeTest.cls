global without sharing class DeclarationMergeTest {

    public class Helper {
        public String getValue() {
            return 'Stable';
        }
    }

    public String getBaseMessage() {
        return 'Base Message';
    }

    public String getSourceMessage() {
        return 'Message from Source Org';
    }
}