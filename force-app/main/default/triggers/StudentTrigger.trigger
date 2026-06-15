trigger StudentTrigger on Student__c (before insert, before update) {

    for (Student__c stu : Trigger.new) {

        // Insert → always calculate
        if (Trigger.isInsert) {
            stu.Grade__c = StudentResultProcessor.getGrade(stu.Marks__c);
        }

        // Update → only when Marks__c changes
        else if (Trigger.isUpdate) {

            Student__c oldStu = Trigger.oldMap.get(stu.Id);

            if (stu.Marks__c != oldStu.Marks__c) {
                stu.Grade__c = StudentResultProcessor.getGrade(stu.Marks__c);
            }
        }
    }
}