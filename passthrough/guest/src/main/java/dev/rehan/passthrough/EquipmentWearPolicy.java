package dev.rehan.passthrough;

import java.util.function.Consumer;
import java.util.function.Predicate;

/** Delayed shield-hit receipts still wear a held shield after use/cooldown ends. */
public final class EquipmentWearPolicy {
    private EquipmentWearPolicy() {}

    public static <T> void apply(boolean shieldHit,T used,T main,T off,
                                Predicate<T> isShield,Consumer<T> wearShield,Runnable wearArmor) {
        if(!shieldHit){wearArmor.run();return;}
        T shield=isShield.test(used)?used:isShield.test(main)?main:isShield.test(off)?off:null;
        // An unequipped/broken shield must never redirect its delayed wear onto armor.
        if(shield!=null)wearShield.accept(shield);
    }
}
