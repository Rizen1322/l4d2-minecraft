package dev.rehan.passthrough;
import java.util.EnumSet;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.MoverType;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.phys.Vec3;
/** Passive ground mobs get bounded Source routes instead of pathfinding in air. */
final class SourceWanderGoal extends Goal {
    private final Mob mob;private Vec3 destination;private int ticks;
    SourceWanderGoal(Mob mob){this.mob=mob;setFlags(EnumSet.of(Flag.MOVE));}
    @Override public boolean canUse(){return Passthrough.active && MapBuilds.ready && mob.getTarget()==null && !mob.isInWater();}
    @Override public boolean canContinueToUse(){return canUse();}
    @Override public boolean requiresUpdateEveryTick(){return true;}
    @Override public void tick(){
        if(destination==null || ++ticks>120 || mob.distanceToSqr(destination)<1){ticks=0;var random=mob.getRandom();destination=mob.position().add(random.nextDouble()*8-4,0,random.nextDouble()*8-4);}
        var point=HostNavigation.next(mob,destination);if(point==null)return;
        double dx=point.x-mob.getX(),dz=point.z-mob.getZ(),distance=Math.hypot(dx,dz);if(distance<.01)return;
        double speed=Math.min(distance,Math.clamp(mob.getAttributeValue(Attributes.MOVEMENT_SPEED),.04,.18));
        mob.setYRot((float)(Math.toDegrees(Math.atan2(dz,dx))-90));mob.yBodyRot=mob.getYRot();
        HostTerrain.jumpLedge(mob,dx,dz);mob.move(MoverType.SELF,new Vec3(dx/distance*speed,0,dz/distance*speed));
    }
}
