trigger OrderEventTrigger on Order_Event__e (after insert) {
    if(trigger.isafter && trigger.isinsert){
        OrderEventTriggerHandler.ordertaskevent(trigger.new);
    }

}