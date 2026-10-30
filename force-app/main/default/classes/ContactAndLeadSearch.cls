public class ContactAndLeadSearch {
    public static List<List<sObject>> searchContactsAndLeads(String searchTerm) {
        List<List<sObject>> results = [
            FIND :searchTerm IN NAME FIELDS
            RETURNING
                Contact(Id, FirstName, LastName, Name),
                Lead(Id, FirstName, LastName, Name)
        ];

        return results;
    }
}