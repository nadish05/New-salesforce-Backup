/**
 * @description Production-ready Apex controller for Account management
 * Handles bulk operations with proper error handling and data validation
 */
public with sharing class AccountController {
    
    /**
     * @description Retrieves accounts with selected fields for datatable display
     * @return List<Account> - List of Account records
     */
    @AuraEnabled(cacheable=true)
    public static List<Account> getAccounts() {
        return [
            SELECT Id, Name, Industry, Phone 
            FROM Account 
            LIMIT 10
        ];
    }

    /**
     * @description Bulk updates multiple Account records
     * Validates data, performs DML outside of loops, handles errors gracefully
     * @param accountsToUpdate - List of Account records with updated values
     * @return Map with success status and error messages
     */
    @AuraEnabled
    public static Map<String, Object> updateAccounts(List<Account> accountsToUpdate) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('success', false);
        result.put('message', '');
        result.put('updatedRecordCount', 0);

        try {
            // Validate input
            if (accountsToUpdate == null || accountsToUpdate.isEmpty()) {
                result.put('message', 'No records to update');
                return result;
            }

            // Perform bulk update (DML outside loop)
            List<Database.SaveResult> saveResults = Database.update(accountsToUpdate, false);
            
            // Track successful and failed updates
            List<String> errorMessages = new List<String>();
            Integer successCount = 0;

            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult saveResult = saveResults[i];
                
                if (saveResult.isSuccess()) {
                    successCount++;
                } else {
                    // Collect error details
                    for (Database.Error error : saveResult.getErrors()) {
                        errorMessages.add(
                            'Record ' + (i + 1) + ': ' + error.getStatusCode() + 
                            ' - ' + error.getMessage()
                        );
                    }
                }
            }

            // Set response
            if (successCount > 0) {
                result.put('success', true);
                result.put('updatedRecordCount', successCount);
                
                if (errorMessages.isEmpty()) {
                    result.put('message', 'Successfully updated ' + successCount + ' record(s)');
                } else {
                    result.put('message', 'Updated ' + successCount + ' record(s). Errors: ' + 
                        String.join(errorMessages, '; '));
                }
            } else {
                result.put('message', 'Update failed. Errors: ' + String.join(errorMessages, '; '));
            }

        } catch (Exception e) {
            result.put('success', false);
            result.put('message', 'Error updating records: ' + e.getMessage());
            // Log for debugging
            System.debug(LoggingLevel.ERROR, 'Account update error: ' + e.getStackTraceString());
        }

        return result;
    }
}