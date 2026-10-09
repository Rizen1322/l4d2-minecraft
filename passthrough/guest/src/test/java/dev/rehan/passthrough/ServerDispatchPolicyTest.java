package dev.rehan.passthrough;
import java.util.ArrayDeque;
public final class ServerDispatchPolicyTest {
    public static void main(String[] args){
        var queue=new ArrayDeque<Runnable>();var events=new java.util.ArrayList<String>();
        ServerDispatchPolicy.run(false,queue::add,()->{
            ServerDispatchPolicy.run(true,queue::add,()->events.add("wear applied"));
            events.add("ack");
        });
        if(!events.isEmpty())throw new AssertionError("Socket thread applied server action");
        queue.remove().run();
        if(!queue.isEmpty() || !events.equals(java.util.List.of("wear applied","ack")))throw new AssertionError("Nested action acknowledged early");
        try{ServerDispatchPolicy.run(true,queue::add,()->{throw new IllegalStateException("failed action");});throw new AssertionError("Failure swallowed");}
        catch(IllegalStateException expected){}
        System.out.println("Nested server application-before-ack regression passed");
    }
}
