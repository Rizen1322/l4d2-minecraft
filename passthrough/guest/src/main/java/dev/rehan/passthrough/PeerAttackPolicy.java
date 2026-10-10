package dev.rehan.passthrough;
import java.util.HashMap;
import java.util.Map;
/** Server-thread validation and exactly-once application of room-authorized melee. */
public final class PeerAttackPolicy {
    private long scene;
    private final Map<Integer,Long> sequences=new HashMap<>();
    public boolean accept(long expected,long incoming,int attacker,long sequence,double damage,double distanceSquared) {
        if(expected<=0 || incoming!=expected || attacker<1 || attacker>65535 || sequence<=0
            || !Double.isFinite(damage) || damage<=0 || damage>100
            || !Double.isFinite(distanceSquared) || distanceSquared<0 || distanceSquared>25)return false;
        if(scene!=expected){scene=expected;sequences.clear();}
        if(sequence<=sequences.getOrDefault(attacker,0L))return false;
        sequences.put(attacker,sequence);return true;
    }
}
