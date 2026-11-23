public with sharing class MethodMergeNoConflictDemo {

    public static String getGreeting() {
        return 'Hello from Source Org';
    }

    public static Decimal calculateDiscount(Decimal amount) {
        return amount * 0.15;
    }

    public static String getStatus() {
        return 'INITIAL';
    }

    public static String getSourceMessage() {
        return 'This method was added in Source Org';
    }

    public static String getDestinationMessage() {
        return 'This method was added in Destination Org';
    }
}