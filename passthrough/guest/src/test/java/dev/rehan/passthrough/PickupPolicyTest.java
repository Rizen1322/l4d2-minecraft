package dev.rehan.passthrough;
public final class PickupPolicyTest {
    public static void main(String[] args){
        if(PickupPolicy.items("bow").get("arrow")!=64)throw new AssertionError("Sniper arrows");
        if(PickupPolicy.items("cookie").get("cookie")!=3)throw new AssertionError("Pill snack");
        if(!PickupPolicy.items("weapon_gascan").isEmpty())throw new AssertionError("Preserve objective carry item");
        if(!PickupPolicy.items("unknown").isEmpty())throw new AssertionError("Reject unknown supply");
        RewardLedger old=RewardLedger.decode("{\"claimed\":[],\"reserve\":{}}");
        old.pickups.add("pickup_123_456");old.reserve.put("speed_potion",1);
        RewardLedger restored=RewardLedger.decode(old.encode());
        if(!restored.pickups.contains("pickup_123_456") || restored.reserve.get("speed_potion")!=1)throw new AssertionError("Persist pickup with reserve");
        restored.totems.put("totem_7_2_900",false);
        RewardLedger consumed=RewardLedger.decode(restored.encode());
        if(!Boolean.FALSE.equals(consumed.totems.get("totem_7_2_900")))throw new AssertionError("Consumed totem must survive reconnect without another cost");
        consumed.totems.put("totem_7_2_900",true);
        if(!Boolean.TRUE.equals(RewardLedger.decode(consumed.encode()).totems.get("totem_7_2_900")))throw new AssertionError("Applied animation receipt lost");
        RewardLedger mixed=new RewardLedger();
        for(int i=0;i<150;i++)mixed.claimed.add("c"+"m".repeat(110)+"_"+i);
        for(int i=0;i<200;i++)mixed.pickups.add("pickup_"+"p".repeat(106)+"_"+i);
        mixed.reserve.put("bread",1);
        boolean stopped=false;
        for(int i=0;i<256;i++){
            String receipt="totem_"+"t".repeat(105)+"_"+i,previous=mixed.encode();
            if(!mixed.stage(candidate->{candidate.totems.put(receipt,false);candidate.reserve.put("bread",64);})){
                if(!mixed.encode().equals(previous))throw new AssertionError("Rejected mixed ledger changed inventory reserve or receipts");
                if(mixed.totems.size()>=256)throw new AssertionError("Did not test aggregate budget before family cap");
                RewardLedger.decode(mixed.encode());stopped=true;break;
            }
        }
        if(!stopped)throw new AssertionError("Mixed-family ledger must stop before player.dat write overflows");
        System.out.println("Pickup rewards and durable receipt regression passed");
    }
}
