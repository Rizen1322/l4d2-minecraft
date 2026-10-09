package dev.rehan.passthrough;

import net.fabricmc.fabric.api.command.v2.CommandRegistrationCallback;
import net.fabricmc.fabric.api.event.player.UseEntityCallback;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.level.GameType;

/** Opt-in limited-resource play, equipment heartbeat, and useful friendly mobs. */
public final class SurvivalFeatures {
    private static int ticks;
    private static long lastIgnition;
    private static long burnUntil;
    private static volatile boolean guestBurning;
    private static volatile long healthAt,healthScene;
    private static volatile java.util.UUID healthPlayer;
    public static boolean hostOwnsHealth(ServerPlayer p){
        return Passthrough.active && MapBuilds.ready && healthPlayer!=null && healthPlayer.equals(p.getUUID())
            && healthScene==MapBuilds.scene() && System.nanoTime()-healthAt<2_000_000_000L
            && p.level().getServer()==WorldBridge.server();
    }
    public static boolean burning(){return guestBurning;}
    public static void resetEnvironment(){burnUntil=0;guestBurning=false;lastIgnition=0;healthAt=0;healthPlayer=null;GuestFire.reset();}
    private static java.util.UUID burnPlayer;
    public static void register(){
        CommandRegistrationCallback.EVENT.register((dispatcher,access,environment)-> {
            var root=Commands.literal("l4d2mc");
            for(String mode:new String[]{"survival","creative"})root.then(Commands.literal(mode).executes(ctx->{
                ServerPlayer p=ctx.getSource().getPlayerOrException();
                if(!privateWorld(p.level().getServer()))return 0;
                p.setGameMode(mode.equals("survival")?GameType.SURVIVAL:GameType.CREATIVE);
                // Source owns health/movement; survival still consumes items and tools.
                p.getAbilities().invulnerable=true;p.getAbilities().mayfly=true;p.onUpdateAbilities();
                p.sendSystemMessage(Component.literal("L4D2MC: "+mode+". Health and movement remain controlled by L4D2."));return 1;
            }));
            var golem=Commands.literal("golem");
            for(String mode:new String[]{"follow","guard","attack"})golem.then(Commands.literal(mode).executes(ctx->{
                ServerPlayer p=ctx.getSource().getPlayerOrException();if(!privateWorld(p.level().getServer()))return 0;
                Mob m=GolemOrders.nearest(p);if(m==null){p.sendSystemMessage(Component.literal("No golem within 12 blocks."));return 0;}
                GolemOrders.set(m,mode);p.sendSystemMessage(Component.literal("Golem: "+mode));return 1;
            }));
            root.then(Commands.literal("link").executes(ctx->{
                ServerPlayer p=ctx.getSource().getPlayerOrException();if(!privateWorld(p.level().getServer()))return 0;
                boolean ok=RedstoneLinks.link(p);
                p.sendSystemMessage(Component.literal(ok?"Link requested: nearest switch -> Source door/button in your crosshair.":"Place a lever/pressure plate within 6 blocks first."));return ok?1:0;
            }));
            root.then(Commands.literal("supplies").executes(ctx->{
                ServerPlayer p=ctx.getSource().getPlayerOrException();if(!privateWorld(p.level().getServer()))return 0;
                var account=((RewardAccount)p).l4d2mc$rewards();
                if(account==null){p.sendSystemMessage(Component.literal("Reward ledger needs recovery; rewards are retained."));return 0;}
                CampaignRewards.deliver(p.level().getServer(),p);
                p.sendSystemMessage(Component.literal("Reserved supplies: "+account.reserve));return 1;
            }));
            root.then(golem).then(Commands.literal("save").executes(ctx->{
                if(!privateWorld(ctx.getSource().getServer()))return 0;
                try{MapBuilds.save();ctx.getSource().sendSuccess(()->Component.literal("Map builds saved."),false);return 1;}
                catch(Exception e){ctx.getSource().sendFailure(Component.literal("Save failed; previous archive retained."));return 0;}
            }));dispatcher.register(root);
        });
        UseEntityCallback.EVENT.register((player,level,hand,entity,hit)-> {
            if(!Passthrough.active || hand!=InteractionHand.MAIN_HAND || !player.isShiftKeyDown() || !player.getMainHandItem().isEmpty()
                || !(entity instanceof Mob mob) || !GolemOrders.golem(mob))return InteractionResult.PASS;
            if(!level.isClientSide()){GolemOrders.set(mob,"follow");player.sendSystemMessage(Component.literal("Golem: follow. /l4d2mc golem guard | attack"));}
            return InteractionResult.SUCCESS;
        });
    }
    private static boolean privateWorld(MinecraftServer s){return s.getWorldPath(net.minecraft.world.level.storage.LevelResource.ROOT).normalize().getFileName().toString().equals("l4d2mc-guest");}
    public static void tick(MinecraftServer s){
        if(++ticks%4!=0 || !Passthrough.active || !MapBuilds.ready || !privateWorld(s))return;
        var players=s.getPlayerList().getPlayers();if(players.isEmpty())return;ServerPlayer p=players.getFirst();
        Passthrough.events.accept(GuestMessages.equipment(p.getArmorValue(),p.getAttributeValue(Attributes.ARMOR_TOUGHNESS),p.isBlocking()));
        Passthrough.events.accept("{\"t\":\"totemheld\",\"held\":"+GuestTotems.held(p)+"}");
        var sources=p.damageSources();
        var general=net.minecraft.world.item.enchantment.EnchantmentHelper.getDamageProtection(p.level(),p,sources.generic());
        var fire=net.minecraft.world.item.enchantment.EnchantmentHelper.getDamageProtection(p.level(),p,sources.inFire());
        var blast=net.minecraft.world.item.enchantment.EnchantmentHelper.getDamageProtection(p.level(),p,sources.explosion(null,null));
        var fall=net.minecraft.world.item.enchantment.EnchantmentHelper.getDamageProtection(p.level(),p,sources.fall());
        var projectile=net.minecraft.world.item.enchantment.EnchantmentHelper.getDamageProtection(p.level(),p,sources.arrow(null,null));
        var resistance=p.getEffect(net.minecraft.world.effect.MobEffects.RESISTANCE);
        Passthrough.events.accept(String.format(java.util.Locale.ROOT,
            "{\"t\":\"protection\",\"e\":[%.2f,%.2f,%.2f,%.2f,%.2f],\"resistance\":%d,\"fireproof\":%b}",
            general,fire,blast,fall,projectile,resistance==null?0:Math.min(4,resistance.getAmplifier()+1),p.hasEffect(net.minecraft.world.effect.MobEffects.FIRE_RESISTANCE)));
        var speed=p.getEffect(net.minecraft.world.effect.MobEffects.SPEED);
        var slow=p.getEffect(net.minecraft.world.effect.MobEffects.SLOWNESS);
        double factor=Math.clamp((1+(speed==null?0:.2*(speed.getAmplifier()+1)))*(1-(slow==null?0:.15*(slow.getAmplifier()+1))),.25,2);
        boolean hazard=false;
        for(var at:net.minecraft.core.BlockPos.betweenClosed(p.getBoundingBox().deflate(.05))) {
            var state=p.level().getBlockState(at);
            if(state.is(net.minecraft.tags.BlockTags.FIRE) || state.getFluidState().is(net.minecraft.tags.FluidTags.LAVA)){hazard=true;break;}
        }
        long now=System.nanoTime();
        if(!p.getUUID().equals(burnPlayer)){burnPlayer=p.getUUID();burnUntil=0;}
        if(hazard)burnUntil=now+4_000_000_000L;
        if(p.isInWaterOrRain() || p.hasEffect(net.minecraft.world.effect.MobEffects.FIRE_RESISTANCE))burnUntil=0;
        guestBurning=now<burnUntil;
        Passthrough.events.accept(String.format(java.util.Locale.ROOT,"{\"t\":\"effects\",\"speed\":%.3f,\"burn\":%b}",factor,now<burnUntil));
        GuestFire.report(p);
        CampaignRewards.deliver(s,p);
        // Prevent independent Minecraft death/starvation; Source is authoritative.
        p.getAbilities().invulnerable=true;
        if(p.getFoodData().getFoodLevel()>14)p.getFoodData().setFoodLevel(14);
    }
    public static void hostHealth(com.google.gson.JsonArray values){
        if(values==null || values.size()!=4)return;
        double hp=values.get(0).getAsDouble(),temporary=values.get(1).getAsDouble(),maximum=values.get(2).getAsDouble();
        boolean incap=values.get(3).getAsBoolean();
        if(!Double.isFinite(hp+temporary+maximum) || maximum<=0 || maximum>1000 || hp<0 || hp>1000 || temporary<0 || temporary>1000)return;
        MinecraftServer s=WorldBridge.server();if(s==null)return;
        WorldBridge.serverWork(s,()->{if(!Passthrough.active || !MapBuilds.ready || !privateWorld(s) || s.getPlayerList().getPlayers().isEmpty())return;
            ServerPlayer p=s.getPlayerList().getPlayers().getFirst();
            healthPlayer=p.getUUID();healthScene=MapBuilds.scene();healthAt=System.nanoTime();
            p.setHealth(GuestMessages.health(hp,maximum,incap));
            p.setAbsorptionAmount(incap?0:(float)Math.clamp(temporary/maximum*20,0,20));
        });
    }
    public static void igniteSurface(double x,double y,double z,net.minecraft.core.BlockPos cell){
        MinecraftServer s=WorldBridge.server();if(s==null || !Double.isFinite(x+y+z))return;
        long scene=MapBuilds.scene();
        WorldBridge.serverWork(s,()->{
            if(!Passthrough.active || !MapBuilds.ready || MapBuilds.scene()!=scene || !privateWorld(s) || s.getPlayerList().getPlayers().isEmpty())return;
            ServerPlayer p=s.getPlayerList().getPlayers().getFirst();
            if(p.distanceToSqr(x,y,z)>36 || Math.abs(cell.getX()-x)>1 || Math.abs(cell.getY()-y)>.501 || Math.abs(cell.getZ()-z)>1
                || System.nanoTime()-lastIgnition<350_000_000L)return;
            var hand=p.getMainHandItem().is(Items.FLINT_AND_STEEL)?InteractionHand.MAIN_HAND:InteractionHand.OFF_HAND;
            ItemStack tool=p.getItemInHand(hand);if(!tool.is(Items.FLINT_AND_STEEL))return;
            if(!GuestFire.reserve(p.level(),cell,y))return;
            try {
                var hit=new net.minecraft.world.phys.BlockHitResult(new net.minecraft.world.phys.Vec3(x,y,z),net.minecraft.core.Direction.UP,cell.below(),false);
                var result=tool.useOn(new net.minecraft.world.item.context.UseOnContext(p,hand,hit));
                if(result.consumesAction())lastIgnition=System.nanoTime();
            }finally{if(!p.level().getBlockState(cell).is(net.minecraft.tags.BlockTags.FIRE))GuestFire.release(cell);}
        });
    }
    public static void equipmentHit(int amount,boolean shield){
        MinecraftServer s=WorldBridge.server();if(s==null || amount<0 || amount>100)return;
        WorldBridge.serverWork(s,()->{var players=s.getPlayerList().getPlayers();if(players.isEmpty() || !Passthrough.active)return;
            ServerPlayer p=players.getFirst();
            if(p.isCreative())return;
            int wear=Math.max(1,(int)Math.ceil(amount/5.0));
            EquipmentWearPolicy.apply(shield,p.getUseItem(),p.getMainHandItem(),p.getOffhandItem(),
                stack->stack.is(Items.SHIELD),stack->{
                    var hand=stack==p.getOffhandItem()?InteractionHand.OFF_HAND:InteractionHand.MAIN_HAND;
                    stack.hurtAndBreak(wear,p,hand);
                },()->{
                    for(var slot:new net.minecraft.world.entity.EquipmentSlot[]{net.minecraft.world.entity.EquipmentSlot.HEAD,net.minecraft.world.entity.EquipmentSlot.CHEST,net.minecraft.world.entity.EquipmentSlot.LEGS,net.minecraft.world.entity.EquipmentSlot.FEET})
                        p.getItemBySlot(slot).hurtAndBreak(Math.max(1,wear/4),p,slot);
                });
        });
    }
    public static void shieldCooldown(int ticks){
        var s=WorldBridge.server();if(s==null || ticks<1 || ticks>200)return;
        WorldBridge.serverWork(s,()->{if(!Passthrough.active || s.getPlayerList().getPlayers().isEmpty())return;
            var p=s.getPlayerList().getPlayers().getFirst();
            p.getCooldowns().addCooldown(new ItemStack(Items.SHIELD),ticks);p.stopUsingItem();
        });
    }
    public static ItemStack pickupStack(String kind){
        return switch(kind){
                case "golden_apple"->new ItemStack(Items.GOLDEN_APPLE);
                case "cookie"->new ItemStack(Items.COOKIE);
                case "wooden_sword"->new ItemStack(Items.WOODEN_SWORD);
                case "stone_sword"->new ItemStack(Items.STONE_SWORD);
                case "iron_sword"->new ItemStack(Items.IRON_SWORD);
                case "diamond_sword"->new ItemStack(Items.DIAMOND_SWORD);
                case "netherite_sword"->new ItemStack(Items.NETHERITE_SWORD);
                case "bow"->new ItemStack(Items.BOW);
                case "crossbow"->new ItemStack(Items.CROSSBOW);
                case "flint_and_steel"->new ItemStack(Items.FLINT_AND_STEEL);
                case "tnt"->new ItemStack(Items.TNT);
                case "totem_of_undying"->new ItemStack(Items.TOTEM_OF_UNDYING);
                case "speed_potion","slowness_potion"->{
                    var potion=new ItemStack(kind.equals("speed_potion")?Items.POTION:Items.SPLASH_POTION);
                    potion.set(net.minecraft.core.component.DataComponents.POTION_CONTENTS,
                        new net.minecraft.world.item.alchemy.PotionContents(kind.equals("speed_potion")?net.minecraft.world.item.alchemy.Potions.SWIFTNESS:net.minecraft.world.item.alchemy.Potions.SLOWNESS));
                    yield potion;
                }
                default->ItemStack.EMPTY;
        };
    }
    private static final java.util.Set<String> pendingPickups=new java.util.HashSet<>();
    public static void pickup(String kind,String key){
        MinecraftServer s=WorldBridge.server();if(s==null || !key.matches("pickup_[A-Za-z0-9_]{1,112}"))return;
        synchronized(pendingPickups){if(!pendingPickups.add(key))return;}
        WorldBridge.serverWork(s,()->{try{
            if(!Passthrough.active || !MapBuilds.ready || !privateWorld(s) || s.getPlayerList().getPlayers().isEmpty())return;
            ServerPlayer p=s.getPlayerList().getPlayers().getFirst();var account=((RewardAccount)p).l4d2mc$rewards();if(account==null)return;
            if(!account.pickups.contains(key)){
                var grant=PickupPolicy.items(kind);if(grant.isEmpty())return;
                if(account.reserve.size()+grant.keySet().stream().filter(item->!account.reserve.containsKey(item)).count()>32)return;
                for(var e:grant.entrySet())if(account.reserve.getOrDefault(e.getKey(),0)+e.getValue()>10000)return;
                if(!account.stage(candidate->{
                    grant.forEach((item,count)->candidate.reserve.merge(item,count,Integer::sum));
                    if(candidate.pickups.size()>=512)candidate.pickups.remove(candidate.pickups.iterator().next());
                    candidate.pickups.add(key);
                }))return;
            }
            CampaignRewards.deliver(s,p);
            if(CampaignRewards.checkpoint(s,p,key))Passthrough.events.accept("{\"t\":\"pickupack\",\"key\":\""+key+"\"}");
        }finally{synchronized(pendingPickups){pendingPickups.remove(key);}}});
    }
    public static void supply(double x,double y,double z,int kind){
        MinecraftServer s=WorldBridge.server();if(s==null || kind<0 || kind>3 || !Double.isFinite(x+y+z))return;
        WorldBridge.serverWork(s,()->{var players=s.getPlayerList().getPlayers();if(players.isEmpty() || !Passthrough.active || !MapBuilds.ready)return;
            ServerPlayer p=players.getFirst();if(p.distanceToSqr(x,y,z)>64*64)return;
            var item=switch(kind){case 0->Items.BREAD;case 1->Items.COBBLESTONE;case 2->Items.IRON_NUGGET;default->Items.ARROW;};
            ItemEntity drop=new ItemEntity(s.overworld(),x,y,z,new ItemStack(item,kind==1?4:1));drop.setDefaultPickUpDelay();s.overworld().addFreshEntity(drop);
        });
    }
}
