public class StudentResultProcessor {

    // EXISTING METHOD (keep it)
    public static String getGrade(Decimal marks) {
        
        if(marks == null){
            return 'Invalid';
        }
        
        if(marks >= 90){
            return 'A';
        }
        else if(marks >= 75){
            return 'B';
        }
        else if(marks >= 50){
            return 'C';
        }
        else{
            return 'Fail';
        }
    }

    // ✅ NEW BULK METHOD (this is what your trigger should use)
    public static Map<Id, String> calculateGrades(List<Student__c> students) {
        
        Map<Id, String> gradeMap = new Map<Id, String>();

        for(Student__c stu : students){
            gradeMap.put(stu.Id, getGrade(stu.Marks__c));
        }

        return gradeMap;
    }

    // Optional: for BEFORE INSERT (no Id yet)
    public static Map<Integer, String> calculateGradesBeforeInsert(List<Student__c> students) {
        
        Map<Integer, String> gradeMap = new Map<Integer, String>();

        Integer index = 0;
        for(Student__c stu : students){
            gradeMap.put(index, getGrade(stu.Marks__c));
            index++;
        }

        return gradeMap;
    }

    // ---- your other methods unchanged ----

    public static void analyzeResults(List<Integer> marksList) {
        if(marksList == null || marksList.isEmpty()){
            System.debug('No data available');
            return;
        }
        
        Integer passed = 0;
        Integer failed = 0;

        for(Integer marks : marksList){
            if(marks >= 50){
                passed++;
            } else {
                failed++;
            }
        }

        System.debug('Total Students: ' + marksList.size());
        System.debug('Passed: ' + passed);
        System.debug('Failed: ' + failed);
    }

    public static void getTopStudents() {
        List<Student__c> students = [
            SELECT Name, Marks__c 
            FROM Student__c 
            WHERE Marks__c > 75
            ORDER BY Marks__c DESC
        ];

        if(students.isEmpty()){
            System.debug('No top students found');
            return;
        }

        for(Student__c s : students){
            System.debug('Student: ' + s.Name + ' | Marks: ' + s.Marks__c);
        }
    }

    public static Double getAverage(List<Integer> marksList) {
        if(marksList == null || marksList.isEmpty()){
            return 0;
        }
        
        Integer total = 0;
        for(Integer marks : marksList){
            total += marks;
        }
        
        Double average = (Double) total / marksList.size();
        return Math.round(average * 100) / 100.0;
    }
}