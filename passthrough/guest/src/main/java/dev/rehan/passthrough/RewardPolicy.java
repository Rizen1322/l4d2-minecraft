package dev.rehan.passthrough;
import java.util.LinkedHashMap;
import java.util.Map;
/** Pure bounded campaign balance; resources never depend on callback retries. */
public final class RewardPolicy {
    public static Map<String,Integer> items(int chapter,boolean finale,int difficulty){
        int bonus=Math.clamp(difficulty,0,2);var out=new LinkedHashMap<String,Integer>();
        out.put("bread",4);out.put("cobblestone",32);out.put("arrow",16+8*bonus);out.put("iron_ingot",3+bonus);
        if(chapter%2==0 || finale)out.put("golden_apple",finale?2:1);
        if(chapter%3==0 || finale)out.put("diamond",finale?2:1);
        return out;
    }
    public static int experience(boolean finale){return finale?30:10;}
    public static int repair(int damage,int maximum){return Math.max(0,damage-Math.min(damage,Math.max(1,maximum/10)));}
}
