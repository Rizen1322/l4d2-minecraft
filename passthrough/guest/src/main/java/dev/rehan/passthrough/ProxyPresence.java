package dev.rehan.passthrough;
import java.util.Set;
/** Combat eligibility comes from the newest complete Source snapshot, not visual hysteresis. */
public final class ProxyPresence {
    private Set<Integer> present=Set.of();
    private long received;
    public void update(Set<Integer> handles,long now){present=Set.copyOf(handles);received=now;}
    public boolean targetable(int handle,long now){return present.contains(handle) && now>=received && now-received<750_000_000L;}
    public void clear(){present=Set.of();received=0;}
}
