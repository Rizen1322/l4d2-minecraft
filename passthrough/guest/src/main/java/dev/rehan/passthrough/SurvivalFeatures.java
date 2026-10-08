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
        // Prevent independent Minecraft death/starvation; Source is authoritative.
        p.getAbilities().invulnerable=true;
        if(p.getFoodData().getFoodLevel()>14)p.getFoodData().setFoodLevel(14);
    }
    public static void equipmentHit(int amount,boolean shield){
        MinecraftServer s=WorldBridge.server();if(s==null || amount<0 || amount>100)return;
        s.execute(()->{var players=s.getPlayerList().getPlayers();if(players.isEmpty() || !Passthrough.active)return;
            ServerPlayer p=players.getFirst();
            if(shield && p.getUseItem().is(Items.SHIELD))p.getUseItem().hurtAndBreak(amount,p,p.getUsedItemHand());
            else for(var slot:new net.minecraft.world.entity.EquipmentSlot[]{net.minecraft.world.entity.EquipmentSlot.HEAD,net.minecraft.world.entity.EquipmentSlot.CHEST,net.minecraft.world.entity.EquipmentSlot.LEGS,net.minecraft.world.entity.EquipmentSlot.FEET})
                p.getItemBySlot(slot).hurtAndBreak(Math.max(1,amount/4),p,slot);
        });
    }
    public static void supply(double x,double y,double z,int kind){
        MinecraftServer s=WorldBridge.server();if(s==null || kind<0 || kind>3 || !Double.isFinite(x+y+z))return;
        s.execute(()->{var players=s.getPlayerList().getPlayers();if(players.isEmpty() || !Passthrough.active || !MapBuilds.ready)return;
            ServerPlayer p=players.getFirst();if(p.distanceToSqr(x,y,z)>64*64)return;
            var item=switch(kind){case 0->Items.BREAD;case 1->Items.COBBLESTONE;case 2->Items.IRON_NUGGET;default->Items.ARROW;};
            ItemEntity drop=new ItemEntity(s.overworld(),x,y,z,new ItemStack(item,kind==1?4:1));drop.setDefaultPickUpDelay();s.overworld().addFreshEntity(drop);
        });
    }
}
