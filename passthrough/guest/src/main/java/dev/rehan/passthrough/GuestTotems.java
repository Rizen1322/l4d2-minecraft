package dev.rehan.passthrough;

import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.item.Items;

/** Cost is saved with inventory before Source may revive; duplicate requests never consume twice. */
public final class GuestTotems {
    private GuestTotems() {}
    public static boolean held(ServerPlayer p){return p.getMainHandItem().is(Items.TOTEM_OF_UNDYING) || p.getOffhandItem().is(Items.TOTEM_OF_UNDYING);}
    private static boolean key(String key){return key!=null && key.matches("totem_[A-Za-z0-9_]{1,112}");}
    public static void consume(String key){
        var s=WorldBridge.server();if(s==null || !key(key))return;long scene=MapBuilds.scene();
        WorldBridge.serverWork(s,()->{
            if(!MapBuilds.ready || MapBuilds.scene()!=scene || s.getPlayerList().getPlayers().isEmpty())return;
            var p=s.getPlayerList().getPlayers().getFirst();var ledger=((RewardAccount)p).l4d2mc$rewards();if(ledger==null)return;
            if(!ledger.totems.containsKey(key)) {
                if(ledger.totems.size()>=256 || !held(p)){result(key,false);return;}
                var hand=p.getMainHandItem().is(Items.TOTEM_OF_UNDYING)?InteractionHand.MAIN_HAND:InteractionHand.OFF_HAND;
                if(!ledger.stage(candidate->candidate.totems.put(key,false))){result(key,false);return;}
                p.getItemInHand(hand).shrink(1);p.inventoryMenu.broadcastChanges();
            }
            if(!CampaignRewards.checkpoint(s,p,key))throw new IllegalStateException("Totem consumption checkpoint not durable; retain Source request");
            result(key,true);
        });
    }
    private static void result(String key,boolean consumed){Passthrough.events.accept("{\"t\":\"totemresult\",\"key\":\""+key+"\",\"consumed\":"+consumed+"}");}
    public static void applied(String key){
        var s=WorldBridge.server();if(s==null || !key(key))return;long scene=MapBuilds.scene();
        WorldBridge.serverWork(s,()->{
            if(!MapBuilds.ready || MapBuilds.scene()!=scene || s.getPlayerList().getPlayers().isEmpty())return;
            var p=s.getPlayerList().getPlayers().getFirst();var ledger=((RewardAccount)p).l4d2mc$rewards();
            if(ledger==null || !Boolean.FALSE.equals(ledger.totems.get(key)))return;
            ledger.totems.put(key,true);
            // Save animation receipt too: reconnects cannot repeatedly animate one consumption.
            if(!CampaignRewards.checkpoint(s,p,key)){ledger.totems.put(key,false);throw new IllegalStateException("Totem animation receipt not durable; retain Source reply");}
            p.setHealth(20);p.clearFire();
            var totem=new net.minecraft.world.item.ItemStack(Items.TOTEM_OF_UNDYING);
            var protection=totem.get(net.minecraft.core.component.DataComponents.DEATH_PROTECTION);
            if(protection!=null)protection.applyEffects(totem,p);
            p.level().broadcastEntityEvent(p,(byte)35);
        });
    }
}
