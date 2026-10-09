package dev.rehan.passthrough;
import java.util.Locale;
/** Standalone JVM regression: no Minecraft window/server or test library needed. */
public final class GuestMessagesTest {
    private static void equal(String actual,String expected){if(!actual.equals(expected))throw new AssertionError(actual);}
    public static void main(String[] args){
        var scheduled=new java.util.ArrayDeque<Runnable>();
        var latest=new LatestTaskQueue<String>();var applied=new java.util.ArrayList<Integer>();
        for(int i=0;i<120;i++){int value=i;latest.submit("scene1:health",scheduled::add,()->applied.add(value));}
        if(scheduled.size()!=1)throw new AssertionError("Render-rate snapshots flood server queue");
        scheduled.remove().run();
        if(!applied.equals(java.util.List.of(119)))throw new AssertionError("Old health applied before newest snapshot");
        latest.submit("oldowner:health",scheduled::add,()->applied.add(-1));latest.clear();
        latest.submit("newowner:health",scheduled::add,()->applied.add(120));
        while(!scheduled.isEmpty())scheduled.remove().run();
        if(!applied.equals(java.util.List.of(119,120)))throw new AssertionError("Old owner replayed snapshot or cleared new owner's job");
        latest.submit("reusedkey",scheduled::add,()->applied.add(-2));latest.clear();
        latest.submit("reusedkey",scheduled::add,()->applied.add(121));
        scheduled.remove().run();
        if(applied.size()!=2)throw new AssertionError("Cancelled drain stole replacement job");
        scheduled.remove().run();
        if(applied.getLast()!=121)throw new AssertionError("Replacement job lost after clear");
        try{latest.submit("failure",job->{throw new IllegalStateException("scheduler closed");},()->applied.add(-3));throw new AssertionError("Scheduling failure swallowed");}
        catch(IllegalStateException expected){}
        latest.submit("failure",scheduled::add,()->applied.add(122));
        if(scheduled.size()!=1)throw new AssertionError("Failed schedule poisoned snapshot stream");
        scheduled.remove().run();if(applied.getLast()!=122)throw new AssertionError("Retry applied wrong data");
        if(InputOwnerPolicy.accept(true,1,2,4,4,false))throw new AssertionError("Reattached socket accepts stale input");
        if(InputOwnerPolicy.accept(true,2,2,4,5,false))throw new AssertionError("New scene accepts old click");
        if(!InputOwnerPolicy.accept(true,2,2,4,5,true))throw new AssertionError("Scene change blocks release/menu cleanup");
        if(InputOwnerPolicy.accept(false,2,2,4,4,true))throw new AssertionError("Old controller releases new owner's key");
        equal(GuestMessages.equipment(0,0,false),"{\"t\":\"equipment\",\"armor\":0,\"toughness\":0.00,\"blocking\":false}");
        equal(GuestMessages.equipment(20,8,true),"{\"t\":\"equipment\",\"armor\":20,\"toughness\":8.00,\"blocking\":true}");
        if(GuestMessages.health(50,100,false)!=10 || GuestMessages.health(1,100,false)!=.2f
                || GuestMessages.health(300,100,true)!=.01f || GuestMessages.health(120,100,false)!=20)throw new AssertionError("Source heart scaling");
        Locale.setDefault(Locale.GERMANY);
        equal(GuestMessages.equipment(30,2.5,true),"{\"t\":\"equipment\",\"armor\":20,\"toughness\":2.50,\"blocking\":true}");
        equal(GuestMessages.equipment(-1,Double.NaN,false),"{\"t\":\"equipment\",\"armor\":0,\"toughness\":0.00,\"blocking\":false}");
        System.out.println("Guest equipment serialization regression passed");
    }
}
