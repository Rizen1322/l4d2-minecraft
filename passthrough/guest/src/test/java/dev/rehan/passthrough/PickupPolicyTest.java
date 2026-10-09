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
        System.out.println("Pickup rewards and durable receipt regression passed");
    }
}
