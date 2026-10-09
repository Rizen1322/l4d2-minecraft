package dev.rehan.passthrough;
public final class ReplyTrackerTest {
    public static void main(String[] args){
        var r=new ReplyTracker();
        if(r.begin(1,1,7)!=ReplyTracker.Status.NEW || r.begin(1,1,7)!=ReplyTracker.Status.PENDING)throw new AssertionError("Concurrent duplicate");
        r.finish(1,1,7,false);
        if(r.begin(1,1,7)!=ReplyTracker.Status.NEW)throw new AssertionError("Failed action lost retry");
        r.newOwner();r.begin(1,2,7);r.finish(1,1,7,false);
        if(r.begin(1,2,7)!=ReplyTracker.Status.PENDING)throw new AssertionError("Old owner cleared new job");
        r.finish(1,2,7,true);
        if(r.begin(1,3,7)!=ReplyTracker.Status.DONE)throw new AssertionError("Reconnect duplicated action");
        if(r.begin(2,3,7)!=ReplyTracker.Status.NEW)throw new AssertionError("New scene blocked by old receipt");
        System.out.println("Reply application/retry/owner regression passed");
    }
}
