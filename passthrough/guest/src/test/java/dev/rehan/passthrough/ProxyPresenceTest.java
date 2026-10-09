package dev.rehan.passthrough;
import java.util.Set;
/** A retained visual proxy must not remain a combat target after Source removes it. */
public final class ProxyPresenceTest {
    public static void main(String[] args){
        var roster=new ProxyPresence();
        roster.update(Set.of(4,8),1_000_000_000L);
        if(!roster.targetable(4,1_100_000_000L))throw new AssertionError("Fresh target not acquired");
        roster.update(Set.of(8),1_200_000_000L);
        if(roster.targetable(4,1_200_000_000L))throw new AssertionError("Dead/omitted target remains attackable");
        if(!roster.targetable(8,1_200_000_000L))throw new AssertionError("Next live target lost");
        if(roster.targetable(8,2_000_000_000L))throw new AssertionError("Stopped Source retains target");
        roster.clear();if(roster.targetable(8,1_200_000_000L))throw new AssertionError("Old map retains target");
        System.out.println("Source proxy freshness and death regressions passed");
    }
}
