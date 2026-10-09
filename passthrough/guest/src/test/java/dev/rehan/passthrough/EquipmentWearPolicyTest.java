package dev.rehan.passthrough;

public final class EquipmentWearPolicyTest {
    private static final class Stack {
        final boolean shield;int damage;
        Stack(boolean shield){this.shield=shield;}
    }
    public static void main(String[] args) {
        Stack empty=new Stack(false),shield=new Stack(true),armor=new Stack(false);
        // Source emits cooldown first: stopUsingItem empties used item, but offhand remains.
        EquipmentWearPolicy.apply(true,empty,empty,shield,s->s.shield,s->s.damage++,()->armor.damage++);
        if(shield.damage!=1 || armor.damage!=0)throw new AssertionError("Cooldown redirected shield wear to armor");
        // Releasing RMB before its delayed receipt arrives also retains the main-hand shield.
        EquipmentWearPolicy.apply(true,empty,shield,empty,s->s.shield,s->s.damage++,()->armor.damage++);
        if(shield.damage!=2 || armor.damage!=0)throw new AssertionError("Released shield lost its wear");
        // The shield was moved out of both hands or already broken: never wear unrelated armor.
        EquipmentWearPolicy.apply(true,empty,empty,empty,s->s.shield,s->s.damage++,()->armor.damage++);
        if(armor.damage!=0)throw new AssertionError("Absent shield damaged armor");
        EquipmentWearPolicy.apply(false,shield,shield,empty,s->s.shield,s->s.damage++,()->armor.damage++);
        if(armor.damage!=1 || shield.damage!=2)throw new AssertionError("Armor receipt wore shield");
        System.out.println("Delayed shield wear and armor isolation regressions passed");
    }
}
