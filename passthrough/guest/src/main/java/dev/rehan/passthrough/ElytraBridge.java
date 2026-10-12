package dev.rehan.passthrough;
import java.util.HashSet;
import java.util.Set;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.projectile.FireworkRocketEntity;
/** Real equipped Elytra and real attached rockets, mirrored into native Source movement. */
public final class ElytraBridge {
    private static final Set<Integer> rockets=new HashSet<>();
    private static long scene;
    private static long avatarAt;
    private static long entityAt;
    private static int sequence;
    private static final PeerActions actions=new PeerActions();
    private static String lastSwingHand="main";
    private static volatile boolean grounded=true;
    private static volatile long groundAt;
    private ElytraBridge() {}
    public static void reset(){rockets.clear();actions.reset();scene=0;sequence=0;grounded=true;groundAt=0;avatarAt=0;entityAt=0;}
    /** Client supplies only the native Source grounded flag, never guest collision guesses. */
    public static void hostGrounded(boolean value){grounded=value;groundAt=System.nanoTime();}
    public static void request(boolean start) {
        var s=WorldBridge.server();if(s==null)return;long token=MapBuilds.scene();
        WorldBridge.serverWork(s,()->{
            if(!Passthrough.active || !MapBuilds.ready || MapBuilds.scene()!=token || s.getPlayerList().getPlayers().isEmpty())return;
            var p=s.getPlayerList().getPlayers().getFirst();
            if(!start){p.stopFallFlying();return;}
            if(grounded || System.nanoTime()-groundAt>500_000_000L || !LivingEntity.canGlideUsing(p.getItemBySlot(EquipmentSlot.CHEST),EquipmentSlot.CHEST))return;
            p.getAbilities().flying=false;p.onUpdateAbilities();p.setOnGround(false);
            p.tryToStartFallFlying();
        });
    }
    public static void tick(MinecraftServer s) {
        if(!Passthrough.active || !MapBuilds.ready || s!=WorldBridge.server() || s.getPlayerList().getPlayers().isEmpty())return;
        var p=s.getPlayerList().getPlayers().getFirst();
        long token=MapBuilds.scene();if(scene!=token){rockets.clear();actions.reset();sequence=0;scene=token;avatarAt=0;entityAt=0;p.stopFallFlying();}
        actions.observe(p.isSwinging(),p.getSwingAnimation(0));
        var swing=p.getCurrentSwing();if(swing!=null)lastSwingHand=swing.hand()==net.minecraft.world.InteractionHand.OFF_HAND?"off":"main";
        boolean elytra=LivingEntity.canGlideUsing(p.getItemBySlot(EquipmentSlot.CHEST),EquipmentSlot.CHEST);
        if(!elytra || grounded || System.nanoTime()-groundAt>500_000_000L)p.stopFallFlying();
        boolean flying=p.isFallFlying() && elytra,boosting=false;
        Set<Integer> live=new HashSet<>();
        if(flying)for(var rocket:p.level().getEntitiesOfClass(FireworkRocketEntity.class,p.getBoundingBox().inflate(8))) {
            if(rocket.isRemoved() || ((dev.rehan.passthrough.mixin.FireworkAccessor)rocket).l4d2mc$attachedToEntity()!=p)continue;
            live.add(rocket.getId());boosting=true;
            if(!rockets.contains(rocket.getId()) && sequence<Integer.MAX_VALUE)sequence++;
        }
        rockets.clear();rockets.addAll(live);
        String message=FlightPolicy.snapshot(token,flying,elytra,sequence,boosting);if(message!=null)Passthrough.events.accept(message);
        boolean consuming=FlightPolicy.consuming(p.isUsingItem(),p.getUseItem().getUseAnimation().name());
        Passthrough.events.accept("{\"t\":\"consume\",\"scene\":"+token+",\"using\":"+consuming+"}");
        long now=System.nanoTime();if(now-avatarAt>=100_000_000L) {
            avatarAt=now;
            var registry=net.minecraft.core.registries.BuiltInRegistries.ITEM;
            String avatar=FlightPolicy.avatar(token,registry.getKey(p.getMainHandItem().getItem()).toString(),
                registry.getKey(p.getOffhandItem().getItem()).toString(),registry.getKey(p.getItemBySlot(EquipmentSlot.CHEST).getItem()).toString());
            if(avatar!=null){String swingHand=lastSwingHand;
                avatar=avatar.substring(0,avatar.length()-1)+",\"swing\":"+actions.sequence()+",\"swinghand\":\""+swingHand+"\",\"using\":"+p.isUsingItem()+",\"usehand\":\""+(p.isUsingItem() && p.getUsedItemHand()==net.minecraft.world.InteractionHand.OFF_HAND?"off":"main")+"\"}";Passthrough.events.accept(avatar);}
        }
        if(token>0 && now-entityAt>=100_000_000L) {
            entityAt=now;
            var candidates=new java.util.ArrayList<net.minecraft.world.entity.Entity>();
            for(var e:s.overworld().getAllEntities()) {
                if(e.isRemoved() || !e.isAlive() || MobWar.isProxy(e) || e.entityTags().contains(MobWar.PROXY_TAG))continue;
                if(!(e instanceof net.minecraft.world.entity.Mob || e instanceof net.minecraft.world.entity.item.PrimedTnt || e instanceof net.minecraft.world.entity.projectile.Projectile))continue;
                // Multipart dragon hitboxes are not independent render-only objects.
                if(e instanceof net.minecraft.world.entity.boss.enderdragon.EnderDragon)continue;
                if(e instanceof net.minecraft.world.entity.Avatar || !MapBuilds.ownsEntity(e))continue;
                if(!Double.isFinite(e.getX()+e.getY()+e.getZ()) || Math.abs(e.getX())>1023 || Math.abs(e.getY())>1023 || Math.abs(e.getZ())>1023)continue;
                candidates.add(e);
            }
            candidates.sort(java.util.Comparator.comparingDouble(p::distanceToSqr));
            var rows=new java.util.ArrayList<EntityRosterPolicy.Row>();
            for(var e:candidates) {
                if(rows.size()>=64)break;
                String type=net.minecraft.core.registries.BuiltInRegistries.ENTITY_TYPE.getKey(e.getType()).toString();
                rows.add(new EntityRosterPolicy.Row(e.getId(),type,e.getX(),e.getY(),e.getZ(),net.minecraft.util.Mth.wrapDegrees(e.getYRot()),Math.clamp(e.getXRot(),-90,90)));
            }
            Passthrough.events.accept(EntityRosterPolicy.encodeState(token,rows));
        }
    }
}
