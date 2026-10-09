package dev.rehan.passthrough;
import java.util.HashSet;
import java.util.LinkedHashSet;
/** A failed or superseded server job stays retryable; old owners cannot clear a new pending job. */
public final class ReplyTracker {
    private record Receipt(long scene,int id) {}
    private record Pending(long scene,long generation,int id) {}
    public enum Status { NEW, PENDING, DONE }
    private final LinkedHashSet<Receipt> delivered=new LinkedHashSet<>();
    private final HashSet<Pending> pending=new HashSet<>();
    private java.lang.ref.WeakReference<Object> server=new java.lang.ref.WeakReference<>(null);
    private long ownerEpoch;
    /** A stopped server queue cannot finish its pending jobs. Keep receipts, release pending leases. */
    public synchronized long serverOwner(Object current){
        if(server.get()!=current){newOwner();server=new java.lang.ref.WeakReference<>(current);}
        return ownerEpoch;
    }
    public synchronized Status begin(long scene,long generation,int id){
        if(delivered.contains(new Receipt(scene,id)))return Status.DONE;
        return pending.add(new Pending(scene,generation,id))?Status.NEW:Status.PENDING;
    }
    public synchronized void finish(long scene,long generation,int id,boolean success){
        pending.remove(new Pending(scene,generation,id));
        if(success){delivered.add(new Receipt(scene,id));if(delivered.size()>256)delivered.remove(delivered.iterator().next());}
    }
    public synchronized void newOwner(){pending.clear();ownerEpoch++;}
}
