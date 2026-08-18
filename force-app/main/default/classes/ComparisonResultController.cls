public with sharing class ComparisonResultController {

    @AuraEnabled(cacheable=true)
    public static Integer getResultCount(
        Id metadataComparisonId,
        String searchKey
    ) {

        String searchPattern =
            '%' + (String.isBlank(searchKey) ? '' : searchKey) + '%';

        return [
            SELECT COUNT()
            FROM Comparison_Result__c
            WHERE Metadata_Comparison__c = :metadataComparisonId
            AND Name LIKE :searchPattern
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Comparison_Result__c> getComparisonResults(
        Id metadataComparisonId,
        String searchKey,
        Integer pageSize,
        Integer pageNumber,
        String sortField,
        String sortDirection
    ) {

        if(pageSize == null) pageSize = 50;
        if(pageNumber == null) pageNumber = 1;

        Integer offsetRows = (pageNumber - 1) * pageSize;

        String query =
            'SELECT Id, Name ' +
            'FROM Comparison_Result__c ' +
            'WHERE Metadata_Comparison__c = :metadataComparisonId';

        if(String.isNotBlank(searchKey)) {
            query +=
                ' AND Name LIKE \'%' +
                String.escapeSingleQuotes(searchKey) +
                '%\'';
        }

        if(String.isBlank(sortField)) {
            sortField = 'Name';
        }

        if(String.isBlank(sortDirection)) {
            sortDirection = 'ASC';
        }

        query +=
            ' ORDER BY ' + sortField + ' ' + sortDirection +
            ' LIMIT ' + pageSize +
            ' OFFSET ' + offsetRows;

        return Database.query(query);
    }
}