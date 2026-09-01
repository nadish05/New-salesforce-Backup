public with sharing class MetadataComparisonController {

    @AuraEnabled
    public static void saveComparison(
        String comparisonName,
        Id sourceOrgId,
        Id destinationOrgId
    ) {

        Metadata_Comparison__c rec =
            new Metadata_Comparison__c();

        rec.Name =
            comparisonName;

        rec.Source_Org__c =
            sourceOrgId;

        rec.Destination_Org__c =
            destinationOrgId;

        insert rec;
    }

    @AuraEnabled(cacheable=true)
public static List<Metadata_Comparison__c>
getComparisons() {

    return [

        SELECT
            Id,
            Name,
            Comparison_Name__c,
            Source_Org__c,
            Source_Org__r.Name,
            Destination_Org__c,
            Destination_Org__r.Name

        FROM Metadata_Comparison__c

        ORDER BY CreatedDate DESC

    ];

}

@AuraEnabled
public static Metadata_Comparison__c getComparisonDetails(
    Id comparisonId
) {

    return [

        SELECT
            Id,
            Comparison_Name__c,

            Source_Branch__c,
            Source_Status__c,

            Destination_Branch__c,
            Destination_Status__c,

            Comparison_Status__c,

            Source_Org__c,
            Source_Org__r.Name,
            Source_Org__r.Org_ID__c,
            Source_Org__r.Instance_URL__c,
            Source_Org__r.Refresh_Token__c,

            Destination_Org__c,
            Destination_Org__r.Name,
            Destination_Org__r.Org_ID__c,
            Destination_Org__r.Instance_URL__c,
            Destination_Org__r.Refresh_Token__c

        FROM Metadata_Comparison__c

        WHERE Id = :comparisonId

        LIMIT 1

    ];

}

@AuraEnabled
public static void updateMigrationStatus(
    Id comparisonId,
    String branchName,
    String migrationType
) {

    Metadata_Comparison__c comparisonRec = [
        SELECT
            Id,
            Source_Status__c,
            Destination_Status__c
        FROM Metadata_Comparison__c
        WHERE Id = :comparisonId
        LIMIT 1
    ];

    if (migrationType == 'Source') {

        comparisonRec.Source_Branch__c =
            branchName;

        comparisonRec.Source_Status__c =
            'Metadata Pushed';

    }

    if (migrationType == 'Destination') {

        comparisonRec.Destination_Branch__c =
            branchName;

        comparisonRec.Destination_Status__c =
            'Metadata Pushed';

    }

    if (
        comparisonRec.Source_Status__c ==
        'Metadata Pushed'
        &&
        comparisonRec.Destination_Status__c ==
        'Metadata Pushed'
    ) {

        comparisonRec.Comparison_Status__c =
            'Metadata Pushed';

    }

    update comparisonRec;

}

@AuraEnabled
public static void saveComparisonResults(
    Id comparisonId,
    List<Object> files
) {

    System.debug(
    'FILES RECEIVED: ' +
    files.size()
);

System.debug(
    'COMPARISON ID: ' +
    comparisonId
);

    // Delete old results
    List<Comparison_Result__c> oldResults = [
        SELECT Id
        FROM Comparison_Result__c
        WHERE Metadata_Comparison__c = :comparisonId
    ];

    if (!oldResults.isEmpty()) {
        delete oldResults;
    }

    List<Comparison_Result__c> resultsToInsert =
        new List<Comparison_Result__c>();

    for (Object fileObj : files) {

        System.debug(
            'FILE OBJECT => ' +
            fileObj
        );

        Map<String, Object> fileData =
            (Map<String, Object>)fileObj;

        String filePath =
            String.valueOf(
                fileData.get('filePath')
            );

        String changeType =
            String.valueOf(
                fileData.get('changeType')
            );

        String flowStatus = null;

if (
    fileData.containsKey('flowStatus')
) {

    flowStatus =
        String.valueOf(
            fileData.get('flowStatus')
        );

}

        String metadataType =
            resolveMetadataType(filePath);

        String fileName = filePath;

        if (filePath.contains('/')) {
            List<String> parts =
                filePath.split('/');

            fileName =
                parts[parts.size() - 1];
        }

        String recordName = fileName;

if(recordName.length() > 80) {
    recordName = recordName.substring(0,80);
}
        
        resultsToInsert.add(
    new Comparison_Result__c(

        Name =
            recordName,

        Metadata_Comparison__c =
            comparisonId,

        Metadata_Type__c =
            metadataType,

        Change_Type__c =
            changeType,

        File_Name__c =
            fileName,

        File_Path__c =
            filePath,

        Flow_Status__c =
            flowStatus
    )
);
    }

    if (!resultsToInsert.isEmpty()) {
        insert resultsToInsert;
    }
}

@AuraEnabled(cacheable=true)
public static List<Comparison_Result__c>
getComparisonResults(
    Id comparisonId
) {

    return [

        SELECT
            Id,
            Name,
            Metadata_Type__c,
            File_Name__c,
            File_Path__c,
            Change_Type__c,
            Flow_Status__c,
            Selected_For_Deployment__c,
            Deployment_Intent__c

        FROM Comparison_Result__c

        WHERE Metadata_Comparison__c =
            :comparisonId

        ORDER BY
            Metadata_Type__c,
            File_Name__c

    ];

}

    private static String resolveMetadataType(
        String filePath
    ) {

        if (filePath.contains('/classes/')) {
            return 'ApexClass';
        }

        if (filePath.contains('/lwc/')) {
            return 'LWC';
        }

        if (filePath.contains('/aura/')) {
            return 'Aura';
        }

        if (filePath.contains('/objects/')) {
            return 'CustomObject';
        }

        if (filePath.contains('/flows/')) {
            return 'Flow';
        }

        if (filePath.contains('/permissionsets/')) {
            return 'PermissionSet';
        }

        if (filePath.contains('/profiles/')) {
            return 'Profile';
        }

        if (filePath.contains('/namedCredentials/')) {
            return 'NamedCredential';
        }

        if (filePath.contains('/labels/')) {
            return 'CustomLabel';
        }

        if (filePath.contains('/customMetadata/')) {
            return 'CustomMetadata';
        }

        if (
            filePath.contains('/externalCredentials/') ||
            filePath.endsWith('.externalCredential-meta.xml')
        ) {
            return 'ExternalCredential';
        }

        if (
            filePath.endsWith('.layout-meta.xml') &&
            (filePath.contains('/layouts/') || filePath.startsWith('layouts/'))
        ) {
            return 'Layout';
        }

        return 'Other';

    }

}