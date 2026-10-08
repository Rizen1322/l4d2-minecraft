package dev.rehan.passthrough;
public final class RewardPolicyTest {
    public static void main(String[] args){
        var base=RewardPolicy.items(1,false,0);if(base.get("bread")!=4 || base.containsKey("diamond") || base.containsKey("golden_apple"))throw new AssertionError(base);
        var third=RewardPolicy.items(3,false,2);if(third.get("diamond")!=1 || third.get("arrow")!=32 || third.get("iron_ingot")!=5)throw new AssertionError(third);
        var finale=RewardPolicy.items(4,true,1);if(finale.get("diamond")!=2 || finale.get("golden_apple")!=2)throw new AssertionError(finale);
        if(RewardPolicy.repair(5,100)!=0 || RewardPolicy.repair(60,100)!=50 || RewardPolicy.repair(0,100)!=0)throw new AssertionError("Repair bounds");
        var ledger=new RewardLedger();ledger.claimed.add("c1m1_hotel_123");ledger.reserve.put("bread",4);
        var restored=RewardLedger.decode(ledger.encode());if(!restored.claimed.equals(ledger.claimed) || restored.reserve.get("bread")!=4)throw new AssertionError("Ledger roundtrip");
        for(String broken:new String[]{"null","{\"claimed\":[\"x;quit\"],\"reserve\":{}}","{\"claimed\":[],\"reserve\":{\"bread\":-1}}"}) {
            boolean rejected=false;try{RewardLedger.decode(broken);}catch(IllegalArgumentException expected){rejected=true;}if(!rejected)throw new AssertionError("Corrupt receipt");
        }
        System.out.println("Reward balance regression passed");
    }
}
