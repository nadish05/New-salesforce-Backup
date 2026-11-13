public with sharing class DeploymentReviewService {

    public static Boolean testClassExists(
        String className
    ) {

        String testClass1 =
            className.replace('.cls', '') +
            'Test';

        String testClass2 =
            'Test' +
            className.replace('.cls', '');

        Integer countClasses = [

            SELECT Count()
            FROM ApexClass
            WHERE Name = :testClass1
            OR Name = :testClass2

        ];

        return countClasses > 0;
    }
}