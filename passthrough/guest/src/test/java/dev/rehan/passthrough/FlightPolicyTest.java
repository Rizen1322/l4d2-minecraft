package dev.rehan.passthrough;
/** Guest snapshots cannot turn unequipped players or unrelated fireworks into native flight. */
public final class FlightPolicyTest {
    public static void main(String[] args) {
        String noWings=FlightPolicy.snapshot(7,true,false,4,true);
        if(!noWings.contains("\"on\":false") || !noWings.contains("\"boosting\":false"))throw new AssertionError(noWings);
        String grounded=FlightPolicy.snapshot(7,false,true,4,true);
        if(!grounded.contains("\"on\":false") || !grounded.contains("\"boosting\":false"))throw new AssertionError(grounded);
        String flying=FlightPolicy.snapshot(7,true,true,4,true);
        if(!flying.contains("\"on\":true") || !flying.contains("\"boost\":4") || !flying.contains("\"boosting\":true"))throw new AssertionError(flying);
        if(FlightPolicy.snapshot(0,true,true,1,true)!=null || FlightPolicy.snapshot(7,true,true,-1,true)!=null)throw new AssertionError("Invalid flight scene/sequence accepted");
        if(!FlightPolicy.consuming(true,"EAT") || !FlightPolicy.consuming(true,"DRINK")
            || FlightPolicy.consuming(false,"EAT") || FlightPolicy.consuming(true,"BLOCK") || FlightPolicy.consuming(true,"BOW"))throw new AssertionError("Use slowdown applied to weapons");
        String avatar=FlightPolicy.avatar(7,"minecraft:diamond_sword","minecraft:shield","minecraft:elytra");
        if(avatar==null || !avatar.contains("\"scene\":7") || !avatar.contains("minecraft:elytra")
            || FlightPolicy.avatar(7,"evil\"name","minecraft:air","minecraft:air")!=null)throw new AssertionError("Unsafe avatar registry ID");
        System.out.println("Guest Elytra snapshot and consumption regressions passed");
    }
}
