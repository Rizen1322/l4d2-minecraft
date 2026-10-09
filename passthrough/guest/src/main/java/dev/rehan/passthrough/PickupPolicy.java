package dev.rehan.passthrough;
import java.util.Map;
/** Bounded rewards for actual native inventory pickups, anywhere on the map. */
public final class PickupPolicy {
    public static Map<String,Integer> items(String kind){
        return switch(kind){
            case "bow"->Map.of("bow",1,"arrow",64);
            case "crossbow"->Map.of("crossbow",1,"arrow",32);
            case "cookie"->Map.of("cookie",3);
            case "golden_apple","wooden_sword","stone_sword","iron_sword","diamond_sword","netherite_sword",
                 "flint_and_steel","tnt","speed_potion","slowness_potion","totem_of_undying"->Map.of(kind,1);
            default->Map.of();
        };
    }
}
