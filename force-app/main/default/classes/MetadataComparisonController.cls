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

        Map<Object, Object> fileData =
            (Map<Object, Object>)fileObj;

        String filePath =
            String.valueOf(
                fileData.get('filePath')
            );

        String changeType =
            String.valueOf(
                fileData.get('changeType')
            );

        String metadataType = 'Other';
        String fileName = filePath;

        if (filePath.contains('/')) {
            List<String> parts =
                filePath.split('/');

            fileName =
                parts[parts.size() - 1];
        }

        if (filePath.contains('/classes/')) {
            metadataType = 'ApexClass';
        }
        else if (filePath.contains('/lwc/')) {
            metadataType = 'LWC';
        }
        else if (filePath.contains('/aura/')) {
            metadataType = 'Aura';
        }
        else if (filePath.contains('/objects/')) {
            metadataType = 'CustomObject';
        }
        else if (filePath.contains('/flows/')) {
            metadataType = 'Flow';
        }
        else if (filePath.contains('/permissionsets/')) {
            metadataType = 'PermissionSet';
        }
        else if (filePath.contains('/profiles/')) {
            metadataType = 'Profile';
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
            filePath
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
            Change_Type__c

        FROM Comparison_Result__c

        WHERE Metadata_Comparison__c =
            :comparisonId

        ORDER BY
            Metadata_Type__c,
            File_Name__c

    ];

}
}