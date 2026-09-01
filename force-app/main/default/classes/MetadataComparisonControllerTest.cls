/**
 * Focused tests for MetadataComparisonController comparison ingest classification.
 */
@IsTest
private class MetadataComparisonControllerTest {

    private static Connected_Org__c createOrg(String suffix) {
        Connected_Org__c orgRec = new Connected_Org__c(
            Name = 'Org ' + suffix,
            Display_Name__c = 'Org ' + suffix,
            Org_ID__c = '00D' + suffix,
            Instance_URL__c = 'https://example' + suffix + '.my.salesforce.com',
            Refresh_Token__c = 'token-' + suffix,
            Active__c = true
        );
        insert orgRec;
        return orgRec;
    }

    private static Metadata_Comparison__c createComparison() {
        Connected_Org__c sourceOrg = createOrg('LayoutSrc');
        Connected_Org__c destOrg = createOrg('LayoutDst');
        Metadata_Comparison__c comparison = new Metadata_Comparison__c(
            Name = 'Layout Classification',
            Source_Org__c = sourceOrg.Id,
            Destination_Org__c = destOrg.Id
        );
        insert comparison;
        return comparison;
    }

    private static Map<String, Object> comparisonFile(
        String filePath,
        String changeType
    ) {
        return new Map<String, Object>{
            'filePath' => filePath,
            'changeType' => changeType
        };
    }

    private static Comparison_Result__c getResultByPath(
        Id comparisonId,
        String filePath
    ) {
        List<Comparison_Result__c> results = [
            SELECT
                Metadata_Type__c,
                File_Path__c,
                File_Name__c,
                Name
            FROM Comparison_Result__c
            WHERE Metadata_Comparison__c = :comparisonId
        ];

        Comparison_Result__c match = null;
        for (Comparison_Result__c result : results) {
            if (result.File_Path__c == filePath) {
                match = result;
                break;
            }
        }

        System.assertNotEquals(
            null,
            match,
            'Expected one comparison result for path: ' + filePath
        );
        return match;
    }

    @IsTest
    static void saveComparisonResults_classifiesStandardAccountLayout() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath = 'layouts/Account-Account Layout.layout-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'MODIFIED')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('Layout', result.Metadata_Type__c);
        System.assertEquals(filePath, result.File_Path__c);
        System.assertEquals(
            'Account-Account Layout.layout-meta.xml',
            result.File_Name__c
        );
        System.assertEquals(
            'Account-Account Layout.layout-meta.xml',
            result.Name
        );
    }

    @IsTest
    static void saveComparisonResults_classifiesEncodedLayoutName() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'layouts/Account-Account %28Marketing%29 Layout.layout-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'NEW')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('Layout', result.Metadata_Type__c);
        System.assertEquals(filePath, result.File_Path__c);
        System.assertEquals(
            'Account-Account %28Marketing%29 Layout.layout-meta.xml',
            result.File_Name__c
        );
    }

    @IsTest
    static void saveComparisonResults_classifiesCustomObjectLayout() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'layouts/Gym_Member__c-Gym Member Layout.layout-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'MODIFIED')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('Layout', result.Metadata_Type__c);
        System.assertEquals(filePath, result.File_Path__c);
    }

    @IsTest
    static void saveComparisonResults_classifiesContactLayout() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath = 'layouts/Contact-Contact Layout.layout-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'DELETED')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('Layout', result.Metadata_Type__c);
    }

    @IsTest
    static void saveComparisonResults_classifiesDxPrefixedLayoutPath() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'force-app/main/default/layouts/Account-Account Layout.layout-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'MODIFIED')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('Layout', result.Metadata_Type__c);
    }

    @IsTest
    static void saveComparisonResults_nonLayoutXmlRemainsUnchanged() {
        Metadata_Comparison__c comparison = createComparison();
        String flowPath =
            'force-app/main/default/flows/Active_Customer.flow-meta.xml';
        String otherPath = 'config/unrelated-settings.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(flowPath, 'MODIFIED'),
                comparisonFile(otherPath, 'NEW')
            }
        );
        Test.stopTest();

        System.assertEquals(
            'Flow',
            getResultByPath(comparison.Id, flowPath).Metadata_Type__c
        );
        System.assertEquals(
            'Other',
            getResultByPath(comparison.Id, otherPath).Metadata_Type__c
        );
    }

    @IsTest
    static void saveComparisonResults_apexClassRemainsApexClass() {
        Metadata_Comparison__c comparison = createComparison();
        String classPath =
            'force-app/main/default/classes/AccountController.cls';
        String metaPath =
            'force-app/main/default/classes/AccountController.cls-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(classPath, 'MODIFIED'),
                comparisonFile(metaPath, 'MODIFIED')
            }
        );
        Test.stopTest();

        System.assertEquals(
            'ApexClass',
            getResultByPath(comparison.Id, classPath).Metadata_Type__c
        );
        System.assertEquals(
            'ApexClass',
            getResultByPath(comparison.Id, metaPath).Metadata_Type__c
        );
    }
}