public inherited sharing class DeclarationMergeTest {

    public class Helper {
        public String getValue() {
            return 'Stable';
        }
    }

    public String getBaseMessage() {
        return 'Base Message';
    }

    public String getDestinationMessage() {
        return 'Message from Destination Org';
    }
}