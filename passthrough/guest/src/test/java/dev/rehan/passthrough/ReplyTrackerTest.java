package dev.rehan.passthrough;
public final class ReplyTrackerTest {
    public static void main(String[] args){
        var worldReplies=new ReplyTracker();var oldServer=new Object();var newServer=new Object();
        long oldLease=worldReplies.serverOwner(oldServer);
        if(worldReplies.begin(7,oldLease,19)!=ReplyTracker.Status.NEW)throw new AssertionError("First server reply not scheduled");
        if(worldReplies.serverOwner(oldServer)!=oldLease || worldReplies.begin(7,oldLease,19)!=ReplyTracker.Status.PENDING)throw new AssertionError("Same server heartbeat loses pending dedup");
        long newLease=worldReplies.serverOwner(newServer);
        if(oldLease==newLease || worldReplies.begin(7,newLease,19)!=ReplyTracker.Status.NEW)throw new AssertionError("Stopped server suppresses reply retry");
        worldReplies.finish(7,oldLease,19,false);
        if(worldReplies.begin(7,newLease,19)!=ReplyTracker.Status.PENDING)throw new AssertionError("Late stopped-server cleanup cancels new reply");
        worldReplies.finish(7,newLease,19,true);
        if(worldReplies.begin(7,worldReplies.serverOwner(oldServer),19)!=ReplyTracker.Status.DONE)throw new AssertionError("Applied receipt lost during world reload");
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
