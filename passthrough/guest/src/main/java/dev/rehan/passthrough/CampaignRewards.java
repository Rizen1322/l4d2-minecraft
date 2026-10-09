package dev.rehan.passthrough;
import java.util.*;
import net.minecraft.resources.Identifier;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.item.ItemStack;
/** Per-player receipt and reserve persist atomically with inventory in player.dat. */
public final class CampaignRewards {
    public static void claim(String key,String map,boolean finale,int difficulty){
        if(!key.matches("[A-Za-z0-9_]{1,128}") || !map.matches("[A-Za-z0-9_]{1,96}") || difficulty<0 || difficulty>2)return;
        var s=WorldBridge.server();if(s==null)return;
        s.execute(()->{
            if(!s.getWorldPath(net.minecraft.world.level.storage.LevelResource.ROOT).normalize().getFileName().toString().equals("l4d2mc-guest") || s.getPlayerList().getPlayers().isEmpty())return;
            ServerPlayer p=s.getPlayerList().getPlayers().getFirst();RewardLedger data=((RewardAccount)p).l4d2mc$rewards();
            if(data==null)return;
            if(data.claimed.contains(key)){if(checkpoint(s,p,key))ack(key);return;}
            if(data.claimed.size()>=256){p.sendSystemMessage(net.minecraft.network.chat.Component.literal("Reward ledger is full; reward retained by Source."));return;}
            int chapter=1+data.claimed.size();
            var reserve=data.reserve;
            var grant=RewardPolicy.items(chapter,finale,difficulty);
            for(var e:grant.entrySet())if(reserve.getOrDefault(e.getKey(),0)+e.getValue()>10000)return;
            if(!data.stage(candidate->{grant.forEach((item,count)->candidate.reserve.merge(item,count,Integer::sum));candidate.claimed.add(key);}))return;
            p.giveExperiencePoints(RewardPolicy.experience(finale));
            for(var slot:net.minecraft.world.entity.EquipmentSlot.values()) {
                ItemStack stack=p.getItemBySlot(slot);
                if(stack.isDamageableItem() && stack.getDamageValue()>0)stack.setDamageValue(RewardPolicy.repair(stack.getDamageValue(),stack.getMaxDamage()));
            }
            p.sendSystemMessage(net.minecraft.network.chat.Component.literal("Chapter completed: supplies reserved, equipment repaired 10%."));
            deliver(s,p);
            if(checkpoint(s,p,key))ack(key);
            else Passthrough.LOG.error("Reward remains in Source outbox until player checkpoint succeeds");
        });
    }
    public static boolean checkpoint(MinecraftServer s,ServerPlayer p,String key){
        // saveEverything returns chunk status; player IO failures can be swallowed by Minecraft.
        // Read back the actual atomic player file before clearing the Source outbox.
        try {
            if(key.startsWith("pickup_") || key.startsWith("totem_"))s.getPlayerList().saveAll();else s.saveEverything(true,true,true);
            var file=s.getWorldPath(net.minecraft.world.level.storage.LevelResource.ROOT).resolve("playerdata").resolve(p.getUUID()+".dat");
            var saved=net.minecraft.nbt.NbtIo.readCompressed(file,net.minecraft.nbt.NbtAccounter.create(32L*1024*1024));
            var ledger=RewardLedger.decode(saved.getString("l4d2mcRewards").orElseThrow());
            if(key.startsWith("totem_")) {
                var live=((RewardAccount)p).l4d2mc$rewards();
                return live!=null && live.totems.containsKey(key) && java.util.Objects.equals(ledger.totems.get(key),live.totems.get(key));
            }
            return (key.startsWith("pickup_")?ledger.pickups:ledger.claimed).contains(key);
        }catch(Exception ex){Passthrough.LOG.error("Reward receipt not durable; Source outbox retained",ex);return false;}
    }
    private static void ack(String key){Passthrough.events.accept("{\"t\":\"rewardack\",\"key\":\""+key+"\"}");}
    public static void deliver(MinecraftServer s,ServerPlayer p){
        RewardLedger data=((RewardAccount)p).l4d2mc$rewards();if(data==null)return;
        var reserve=data.reserve;if(reserve.isEmpty())return;
        boolean changed=false;
        for(var e:new ArrayList<>(reserve.entrySet())) {
            var item=BuiltInRegistries.ITEM.getOptional(Identifier.withDefaultNamespace(e.getKey()));
            boolean custom=e.getKey().equals("speed_potion") || e.getKey().equals("slowness_potion");if(item.isEmpty() && !custom)continue;
            int amount=Math.min(64,e.getValue());if(amount<=0){reserve.remove(e.getKey());changed=true;continue;}
            ItemStack stack=custom?SurvivalFeatures.pickupStack(e.getKey()):new ItemStack(item.get(),amount);
            if(custom)amount=1;p.getInventory().add(stack);
            int inserted=amount-stack.getCount();if(inserted<=0)continue;
            int remaining=e.getValue()-inserted;if(remaining==0)reserve.remove(e.getKey());else reserve.put(e.getKey(),remaining);changed=true;
        }
        if(changed)p.inventoryMenu.broadcastChanges();
    }
}
