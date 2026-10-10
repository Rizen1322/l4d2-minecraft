package dev.rehan.passthrough.client;
import java.util.HashMap;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.Map;
import com.google.gson.JsonObject;
import dev.rehan.passthrough.EntityRosterPolicy;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.Identifier;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntitySpawnReason;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.item.PrimedTnt;
import net.minecraft.world.entity.projectile.Projectile;
/** Client-only replicas: melee targets route to their owner's server; AI and physics remain remote. */
public final class PeerEntities {
    private static volatile EntityRosterPolicy.Snapshot snapshot;
    private static ClientLevel level;
    private static long scene;
    private record Copy(String type,Entity entity) {}
    private static final Map<Long,Copy> copies=new HashMap<>();
    private static final IdentityHashMap<Entity,Boolean> visuals=new IdentityHashMap<>();
    private static final IdentityHashMap<Entity,long[]> targets=new IdentityHashMap<>();
    private static final IdentityHashMap<Entity,double[]> tickPositions=new IdentityHashMap<>();
    private static int nextId=-2_000_000;
    private PeerEntities() {}
    public static void update(JsonObject message){var pose=HostState.live();if(pose!=null)snapshot=EntityRosterPolicy.decode(message,pose.scene(),System.nanoTime());}
    public static boolean owns(Entity entity){return entity!=null && entity.level().isClientSide() && visuals.containsKey(entity);}
    public static boolean attackable(Entity entity){return owns(entity) && entity instanceof Mob;}
    public static boolean attack(Entity entity,double damage) {
        if(!attackable(entity))return false;
        var pose=HostState.live();var packet=snapshot;var target=targets.get(entity);
        if(pose!=null && packet!=null && target!=null && packet.live(pose.scene(),System.nanoTime()))
            dev.rehan.passthrough.Passthrough.events.accept(String.format(java.util.Locale.ROOT,
                "{\"t\":\"peerattack\",\"owner\":%d,\"id\":%d,\"d\":%.3f,\"scene\":%d}",target[0],target[1],damage,pose.scene()));
        return true; // Never send a client-only negative entity ID to the local Minecraft server.
    }
    public static void tick(Entity entity) {
        entity.tickCount++;
        var previous=tickPositions.get(entity);
        if(entity instanceof LivingEntity living)living.walkAnimation.update(previous==null?0:(float)Math.min(Math.hypot(entity.getX()-previous[0],entity.getZ()-previous[1])*4,1),0.4F,1);
        tickPositions.put(entity,new double[]{entity.getX(),entity.getZ()});
    }
    private static void clear() {
        if(level!=null)for(var copy:copies.values())if(level.getEntity(copy.entity().getId())==copy.entity())level.removeEntity(copy.entity().getId(),Entity.RemovalReason.DISCARDED);
        copies.clear();visuals.clear();targets.clear();tickPositions.clear();nextId=-2_000_000;
    }
    public static void frame() {
        var mc=Minecraft.getInstance();var pose=HostState.frame();var packet=snapshot;
        boolean live=pose!=null && packet!=null && packet.live(pose.scene(),System.nanoTime());
        if(level!=mc.level || !live || scene!=pose.scene()){clear();level=mc.level;scene=pose==null?0:pose.scene();}
        if(!live || level==null)return;
        var wanted=new HashSet<Long>();
        for(var owner:packet.owners())for(var row:owner.rows()) {
            long key=((long)owner.id()<<32)|(row.id()&0xffffffffL);wanted.add(key);Copy copy=copies.get(key);
            if(copy!=null && !copy.type().equals(row.type())){remove(key);copy=null;}
            if(copy==null) {
                var type=BuiltInRegistries.ENTITY_TYPE.getOptional(Identifier.parse(row.type()));if(type.isEmpty())continue;
                Entity entity=type.get().create(level,EntitySpawnReason.LOAD);
                if(!(entity instanceof Mob || entity instanceof PrimedTnt || entity instanceof Projectile)
                    || entity instanceof net.minecraft.world.entity.boss.enderdragon.EnderDragon)continue;
                while(level.getEntity(nextId)!=null)nextId--;entity.setId(nextId--);
                entity.noPhysics=true;entity.setNoGravity(true);entity.setPermanentlyInvulnerable(true);
                if(entity instanceof Mob mob)mob.setNoAi(true);
                copy=new Copy(row.type(),entity);copies.put(key,copy);visuals.put(entity,true);
                targets.put(entity,new long[]{owner.id(),row.id()});level.addEntity(entity);
            }
            Entity entity=copy.entity();entity.setPos(row.x(),row.y(),row.z());
            entity.xo=entity.xOld=row.x();entity.yo=entity.yOld=row.y();entity.zo=entity.zOld=row.z();
            entity.setYRot(row.yaw());entity.yRotO=row.yaw();entity.setXRot(row.pitch());entity.xRotO=row.pitch();
            entity.setDeltaMovement(net.minecraft.world.phys.Vec3.ZERO);
            if(entity instanceof LivingEntity living)living.yHeadRot=living.yHeadRotO=living.yBodyRot=living.yBodyRotO=row.yaw();
        }
        var gone=new java.util.ArrayList<Long>();for(long key:copies.keySet())if(!wanted.contains(key))gone.add(key);
        for(long key:gone)remove(key);
    }
    private static void remove(long key){var old=copies.remove(key);if(old==null)return;visuals.remove(old.entity());targets.remove(old.entity());tickPositions.remove(old.entity());if(level!=null && level.getEntity(old.entity().getId())==old.entity())level.removeEntity(old.entity().getId(),Entity.RemovalReason.DISCARDED);}
}
