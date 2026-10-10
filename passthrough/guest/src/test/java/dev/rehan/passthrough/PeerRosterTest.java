package dev.rehan.passthrough;
public final class PeerRosterTest {
    public static void main(String[] args){
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
