package dev.rehan.passthrough;
public final class PeerRosterTest {
    public static void main(String[] args){
        var actions=new PeerActions();actions.observe(true,0);actions.observe(true,.3F);actions.observe(true,.3F);if(actions.sequence()!=1)throw new AssertionError("Duplicate swing restarted");actions.observe(true,.1F);if(actions.sequence()!=2)throw new AssertionError("New swing reset was missed");actions.observe(false,0);actions.observe(true,0);if(actions.sequence()!=3)throw new AssertionError("Next swing lost");actions.reset();if(actions.sequence()!=0)throw new AssertionError("Scene action state leaked");
        var peer=new PeerRoster.Member(14,2,3,4,90,120,80,false,false,"none","minecraft:diamond_sword","bad:item",false);
        var input=new java.util.ArrayList<PeerRoster.Member>();input.add(peer);
        var roster=new PeerRoster(123,100,input);input.clear();
        if(roster.players().size()!=1 || peer.pitch()!=90 || !peer.off().equals("minecraft:air"))throw new AssertionError("Immutable bounded metadata");
        if(!roster.live(123,200) || roster.live(456,200) || roster.live(123,1_000_000_100L) || roster.live(123,99))throw new AssertionError("Scene and freshness lease");
        if(!peer.uuid(123).equals(peer.uuid(123)) || peer.uuid(123).equals(peer.uuid(456)) || peer.entityId()>=0)throw new AssertionError("Scene UUID and client-only id");
        boolean invalid=false;try{new PeerRoster.Member(14,Double.NaN,0,0,0,0,80,false,false,"none","minecraft:air","minecraft:air",false);}catch(IllegalArgumentException expected){invalid=true;}
        if(!invalid)throw new AssertionError("Nonfinite peer coordinate");
        if(new PeerRoster(123,0,java.util.Collections.nCopies(8,peer)).players().size()!=4)throw new AssertionError("Room avatar cap");
        System.out.println("Peer avatar immutable scene/freshness/UUID/equipment regressions passed");
    }
}
