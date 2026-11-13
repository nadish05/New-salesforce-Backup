public class OrderEventTriggerHandler {
    public static void ordertaskevent(list<Order_Event__e> olistt){
        if(!olistt.isEmpty()){
            List<Task> talist = new List<Task>();
                for(Order_Event__e event : olistt){
                    if(event.Has_Shipped__c == true){
                        
                        Task tlist = new Task();
                        tlist.Priority = 'Medium';
                        tlist.Subject = 'Follow up on shipped order 105';
                        tlist.OwnerId = event.CreatedById;
                        talist.add(tlist);
                    }
                }
           		INSERT talist;
        }
    }
}