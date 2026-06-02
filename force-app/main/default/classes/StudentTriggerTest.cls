@isTest
public class StudentTriggerTest {

    // 🔹 Reusable method to create valid student
    private static Student__c createStudent(Decimal marks) {
        return new Student__c(
            Name = 'Test Student',
            Marks__c = marks,
            Course_Enrolled__c = 'Salesforce',
            Date_of_Birth__c = Date.today(),
            Email__c = 'test@test.com'
        );
    }

    // ✅ Test Insert
    @isTest
    static void testInsertStudent() {

        Student__c stu = createStudent(85);
        insert stu;

        Student__c result = [
            SELECT Grade__c FROM Student__c WHERE Id = :stu.Id
        ];

        System.assertEquals('B', result.Grade__c);
    }

    // ✅ Test Update (Marks Changed)
    @isTest
    static void testUpdateStudent() {

        Student__c stu = createStudent(40);
        insert stu;

        stu.Marks__c = 92;
        update stu;

        Student__c result = [
            SELECT Grade__c FROM Student__c WHERE Id = :stu.Id
        ];

        System.assertEquals('A', result.Grade__c);
    }

    // ✅ Test Update WITHOUT changing marks
    @isTest
    static void testUpdateWithoutChange() {

        Student__c stu = createStudent(80);
        insert stu;

        stu.Name = 'Updated Name';
        update stu;

        Student__c result = [
            SELECT Grade__c FROM Student__c WHERE Id = :stu.Id
        ];

        System.assertEquals('B', result.Grade__c);
    }

    // ✅ Test Null Marks
    @isTest
    static void testNullMarks() {

        Student__c stu = createStudent(null);
        insert stu;

        Student__c result = [
            SELECT Grade__c FROM Student__c WHERE Id = :stu.Id
        ];

        System.assertEquals('Invalid', result.Grade__c);
    }

    // ✅ Test Bulk Insert (200 records)
    @isTest
    static void testBulkInsert() {

        List<Student__c> students = new List<Student__c>();

        for (Integer i = 0; i < 200; i++) {
            students.add(createStudent(60));
        }

        insert students;

        List<Student__c> resultList = [
            SELECT Grade__c FROM Student__c
        ];

        for (Student__c s : resultList) {
            System.assertEquals('C', s.Grade__c);
        }
    }

    // ✅ Test Boundary Values
    @isTest
    static void testGradeBoundaries() {

        System.assertEquals('A', StudentResultProcessor.getGrade(90));
        System.assertEquals('B', StudentResultProcessor.getGrade(75));
        System.assertEquals('C', StudentResultProcessor.getGrade(50));
    }

    // ✅ Test Processor Methods
    @isTest
    static void testProcessorMethods() {

        // ---- analyzeResults ----
        List<Integer> marksList = new List<Integer>{30, 60, 80, 45};
        StudentResultProcessor.analyzeResults(marksList);
        StudentResultProcessor.analyzeResults(new List<Integer>());
        StudentResultProcessor.analyzeResults(null);

        // ---- getAverage ----
        System.assertEquals(53.75, StudentResultProcessor.getAverage(marksList));
        System.assertEquals(0, StudentResultProcessor.getAverage(new List<Integer>()));
        System.assertEquals(0, StudentResultProcessor.getAverage(null));

        // ---- getGrade ----
        System.assertEquals('A', StudentResultProcessor.getGrade(95));
        System.assertEquals('B', StudentResultProcessor.getGrade(80));
        System.assertEquals('C', StudentResultProcessor.getGrade(60));
        System.assertEquals('Fail', StudentResultProcessor.getGrade(30));
        System.assertEquals('Invalid', StudentResultProcessor.getGrade(null));

        // ---- getTopStudents (with results) ----
        List<Student__c> students = new List<Student__c>{
            createStudent(90),
            createStudent(80),
            createStudent(40)
        };

        insert students;

        Test.startTest();
        StudentResultProcessor.getTopStudents();
        Test.stopTest();
    }

    // ✅ Test getTopStudents with NO results
    @isTest
    static void testNoTopStudents() {

        List<Student__c> students = new List<Student__c>{
            createStudent(40),
            createStudent(30)
        };

        insert students;

        Test.startTest();
        StudentResultProcessor.getTopStudents();
        Test.stopTest();
    }
    @isTest
static void testBulkMethods() {

    List<Student__c> students = new List<Student__c>{
        createStudent(90),
        createStudent(70),
        createStudent(40)
    };

    insert students;

    // ---- Test calculateGrades ----
    Map<Id, String> gradeMap = 
        StudentResultProcessor.calculateGrades(students);

    System.assertEquals(3, gradeMap.size());

    for (Student__c stu : students) {
        System.assert(gradeMap.containsKey(stu.Id));
    }

    // ---- Test calculateGradesBeforeInsert ----
    List<Student__c> newStudents = new List<Student__c>{
        createStudent(85),
        createStudent(55)
    };

    Map<Integer, String> beforeMap = 
        StudentResultProcessor.calculateGradesBeforeInsert(newStudents);

    System.assertEquals(2, beforeMap.size());
}
}