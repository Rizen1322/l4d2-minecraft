package dev.rehan.passthrough;

import java.util.EnumSet;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.MoverType;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.phys.Vec3;

/** Persistent golem orders; uses the same host collision shapes as combat pursuit. */
public final class GolemOrders extends Goal {
    private static final String PREFIX="l4d2mc_order_";
    private final Mob mob;
    private int avoid;
    private double side=1;
    public GolemOrders(Mob mob){this.mob=mob;setFlags(EnumSet.of(Flag.MOVE,Flag.LOOK));}
    public static boolean golem(Mob mob){String k=BuiltInRegistries.ENTITY_TYPE.getKey(mob.getType()).getPath();return k.equals("iron_golem") || k.equals("snow_golem");}
    private static String order(Mob mob){return mob.entityTags().stream().filter(s->s.startsWith(PREFIX)).findFirst().orElse(PREFIX+"attack");}
    private static Vec3 guard(Mob mob){
        String[] p=order(mob).split("_");
        if(p.length!=6 || !p[2].equals("guard"))return null;
        try{return new Vec3(Double.parseDouble(p[3]),Double.parseDouble(p[4]),Double.parseDouble(p[5]));}catch(NumberFormatException e){return null;}
    }
    public static boolean permits(Mob mob,net.minecraft.world.entity.LivingEntity target){
        if(!golem(mob))return true;
        Vec3 at=guard(mob);return at==null || target.distanceToSqr(at)<=144;
    }
    public static void set(Mob mob,String mode){
        var old=mob.entityTags().stream().filter(s->s.startsWith(PREFIX)).toList();old.forEach(mob::removeTag);
        String tag=PREFIX+mode;
        if(mode.equals("guard"))tag+="_"+mob.getX()+"_"+mob.getY()+"_"+mob.getZ();
        mob.addTag(tag);mob.setTarget(null);mob.getNavigation().stop();mob.setPersistenceRequired();
    }
    public static Mob nearest(ServerPlayer p){
        return p.level().getEntitiesOfClass(Mob.class,p.getBoundingBox().inflate(12),GolemOrders::golem)
            .stream().min(java.util.Comparator.comparingDouble(m->m.distanceToSqr(p))).orElse(null);
    }
    private Vec3 destination(){
        if(!(mob.level() instanceof net.minecraft.server.level.ServerLevel level))return null;
        Vec3 at=guard(mob);if(at!=null)return at;
        if(!order(mob).equals(PREFIX+"follow"))return null;
        var players=level.getServer().getPlayerList().getPlayers();return players.isEmpty()?null:players.getFirst().position();
    }
    @Override public boolean canUse(){Vec3 p=destination();return Passthrough.active && MapBuilds.ready && mob.getTarget()==null && p!=null && mob.distanceToSqr(p)>9;}
    @Override public boolean canContinueToUse(){return canUse();}
    @Override public boolean requiresUpdateEveryTick(){return true;}
    @Override public void start(){mob.getNavigation().stop();}
    @Override public void tick(){
        Vec3 p=destination();if(p==null)return;
        Vec3 waypoint=HostNavigation.next(mob,p);if(waypoint==null)return;
        double dx=waypoint.x-mob.getX(),dz=waypoint.z-mob.getZ(),d=Math.hypot(dx,dz);if(d<.01)return;
        double step=Math.min(d,Math.clamp(mob.getAttributeValue(Attributes.MOVEMENT_SPEED),.08,.3));
        double mx=dx/d*step,mz=dz/d*step;
        mob.setYRot((float)(Math.toDegrees(Math.atan2(mz,mx))-90));mob.yBodyRot=mob.getYRot();
        HostTerrain.jumpLedge(mob,mx,mz);
        mob.move(MoverType.SELF,new Vec3(mx,0,mz));
        if(mob.horizontalCollision && ++avoid>=20){HostNavigation.stuck(mob);avoid=0;}
        else if(!mob.horizontalCollision)avoid=0;
    }
}
