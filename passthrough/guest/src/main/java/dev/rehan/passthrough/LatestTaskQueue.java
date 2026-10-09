package dev.rehan.passthrough;
import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;
/** At most one scheduled job per snapshot stream; latest data replaces queued old data. */
public final class LatestTaskQueue<K> {
    private static final class Slot {Runnable action;Slot(Runnable value){action=value;}}
    private final Map<K,Slot> pending=new HashMap<>();
    public void submit(K key,Consumer<Runnable> schedule,Runnable action){
        final Slot slot;
        synchronized(this){var existing=pending.get(key);if(existing!=null){existing.action=action;return;}slot=new Slot(action);pending.put(key,slot);}
        try{schedule.accept(()->{
            Runnable latest;synchronized(this){if(pending.get(key)!=slot)return;pending.remove(key);latest=slot.action;}
            latest.run();
        });}catch(RuntimeException failure){synchronized(this){pending.remove(key,slot);}throw failure;}
    }
    public synchronized void clear(){pending.clear();}
}
