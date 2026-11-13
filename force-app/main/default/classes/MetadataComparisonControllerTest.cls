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

    private static Map<String, Object> versionedFlowCompareFile(
        String workspaceArtifactPath,
        String changeType,
        String flowStatus,
        String definitionDeveloperName,
        Integer versionNumber,
        String versionId,
        String memberName,
        String selectionIdentity
    ) {
        return new Map<String, Object>{
            'metadataType' => 'Flow',
            'workspaceArtifactPath' => workspaceArtifactPath,
            'changeType' => changeType,
            'flowStatus' => flowStatus,
            'flowDefinitionDeveloperName' => definitionDeveloperName,
            'sourceFlowVersionNumber' => versionNumber,
            'sourceFlowVersionId' => versionId,
            'selectedMetadataMemberName' => memberName,
            'selectionIdentity' => selectionIdentity
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
                Name,
                Flow_Status__c,
                Flow_Definition_Developer_Name__c,
                Source_Flow_Version_Number__c,
                Source_Flow_Version_Id__c,
                Selected_Metadata_Member_Name__c,
                Selection_Identity__c
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
    static void saveComparisonResults_persistsVersionedFlowPhase1Fields() {
        Metadata_Comparison__c comparison = createComparison();
        String pathV1 =
            'force-app/main/default/flows/v1/Get_Customer_Details.flow-meta.xml';
        String pathV2 =
            'force-app/main/default/flows/v2/Get_Customer_Details.flow-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                versionedFlowCompareFile(
                    pathV1,
                    'MODIFIED',
                    'Obsolete',
                    'Get_Customer_Details',
                    1,
                    '301FLOW000000001AAA',
                    'Get_Customer_Details-1',
                    'Flow:Get_Customer_Details:301FLOW000000001AAA'
                ),
                versionedFlowCompareFile(
                    pathV2,
                    'MODIFIED',
                    'Active',
                    'Get_Customer_Details',
                    2,
                    '301FLOW000000002AAA',
                    'Get_Customer_Details-2',
                    'Flow:Get_Customer_Details:301FLOW000000002AAA'
                )
            }
        );
        Test.stopTest();

        Comparison_Result__c v1 = getResultByPath(comparison.Id, pathV1);
        Comparison_Result__c v2 = getResultByPath(comparison.Id, pathV2);

        System.assertEquals('Flow', v1.Metadata_Type__c);
        System.assertEquals('Flow', v2.Metadata_Type__c);
        System.assertEquals('Get_Customer_Details', v1.Flow_Definition_Developer_Name__c);
        System.assertEquals('Get_Customer_Details', v2.Flow_Definition_Developer_Name__c);
        System.assertEquals(
            'Get_Customer_Details-1',
            v1.Selected_Metadata_Member_Name__c
        );
        System.assertEquals(
            'Get_Customer_Details-2',
            v2.Selected_Metadata_Member_Name__c
        );
        System.assertEquals(
            'Flow:Get_Customer_Details:301FLOW000000001AAA',
            v1.Selection_Identity__c
        );
        System.assertEquals(
            'Flow:Get_Customer_Details:301FLOW000000002AAA',
            v2.Selection_Identity__c
        );
        System.assertEquals('Obsolete', v1.Flow_Status__c);
        System.assertEquals('Active', v2.Flow_Status__c);
        System.assertEquals(1, v1.Source_Flow_Version_Number__c.intValue());
        System.assertEquals(2, v2.Source_Flow_Version_Number__c.intValue());
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

    @IsTest
    static void saveComparisonResults_classifiesCustomObjectDefinition() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'force-app/main/default/objects/Vehicle__c/Vehicle__c.object-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'MODIFIED')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('CustomObject', result.Metadata_Type__c);
        System.assertEquals(
            'Vehicle__c.object-meta.xml',
            result.File_Name__c
        );
    }

    @IsTest
    static void saveComparisonResults_classifiesCustomFieldChild() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'force-app/main/default/objects/Vehicle__c/fields/Model__c.field-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'DELETED')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('CustomField', result.Metadata_Type__c);
        System.assertEquals(
            'Model__c.field-meta.xml',
            result.File_Name__c
        );
        System.assertEquals('Model__c.field-meta.xml', result.Name);
    }

    @IsTest
    static void saveComparisonResults_classifiesValidationRuleChild() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'objects/Vehicle__c/validationRules/MyRule.validationRule-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'NEW')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('ValidationRule', result.Metadata_Type__c);
    }

    @IsTest
    static void saveComparisonResults_classifiesRecordTypeChild() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'objects/Vehicle__c/recordTypes/MyRecordType.recordType-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'MODIFIED')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('RecordType', result.Metadata_Type__c);
    }

    @IsTest
    static void saveComparisonResults_classifiesListViewChild() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'objects/Vehicle__c/listViews/All.listView-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'DELETED')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('ListView', result.Metadata_Type__c);
    }

    @IsTest
    static void saveComparisonResults_classifiesCompactLayoutChild() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'objects/Vehicle__c/compactLayouts/MyLayout.compactLayout-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'NEW')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('CompactLayout', result.Metadata_Type__c);
    }

    @IsTest
    static void saveComparisonResults_classifiesFieldSetChild() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'objects/Vehicle__c/fieldSets/MySet.fieldSet-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'MODIFIED')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('FieldSet', result.Metadata_Type__c);
    }

    @IsTest
    static void saveComparisonResults_classifiesSharingReasonChild() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'objects/Vehicle__c/sharingReasons/MyReason.sharingReason-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'NEW')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('SharingReason', result.Metadata_Type__c);
    }

    @IsTest
    static void saveComparisonResults_classifiesWebLinkChild() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'objects/Vehicle__c/webLinks/MyLink.webLink-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'MODIFIED')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('WebLink', result.Metadata_Type__c);
    }

    @IsTest
    static void saveComparisonResults_classifiesCustomIndexChild() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'objects/Vehicle__c/indexes/MyIdx.index-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'NEW')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('CustomIndex', result.Metadata_Type__c);
    }

    @IsTest
    static void saveComparisonResults_classifiesBusinessProcessChild() {
        Metadata_Comparison__c comparison = createComparison();
        String filePath =
            'objects/Opportunity/businessProcesses/Sales.businessProcess-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(filePath, 'MODIFIED')
            }
        );
        Test.stopTest();

        Comparison_Result__c result = getResultByPath(comparison.Id, filePath);
        System.assertEquals('BusinessProcess', result.Metadata_Type__c);
    }

    @IsTest
    static void saveComparisonResults_distinguishesSameNamedFieldsAcrossObjects() {
        Metadata_Comparison__c comparison = createComparison();
        String accountPath =
            'objects/Account/fields/Name.field-meta.xml';
        String contactPath =
            'objects/Contact/fields/Name.field-meta.xml';

        Test.startTest();
        MetadataComparisonController.saveComparisonResults(
            comparison.Id,
            new List<Object>{
                comparisonFile(accountPath, 'MODIFIED'),
                comparisonFile(contactPath, 'MODIFIED')
            }
        );
        Test.stopTest();

        System.assertEquals(
            'CustomField',
            getResultByPath(comparison.Id, accountPath).Metadata_Type__c
        );
        System.assertEquals(
            'CustomField',
            getResultByPath(comparison.Id, contactPath).Metadata_Type__c
        );
        System.assertNotEquals(
            getResultByPath(comparison.Id, accountPath).Id,
            getResultByPath(comparison.Id, contactPath).Id
        );
    }
}