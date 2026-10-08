package dev.rehan.passthrough;

import java.util.EnumSet;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.MoverType;
import net.minecraft.world.entity.monster.Creeper;
import net.minecraft.world.entity.monster.RangedAttackMob;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.phys.Vec3;

/** Pursue Source targets without asking vanilla navigation to path through its invisible map. */
final class SourcePursuitGoal extends Goal {
    private final Mob mob;
    private int attackCooldown,avoidTicks;
    private double side=1;
    SourcePursuitGoal(Mob mob){this.mob=mob;setFlags(EnumSet.of(Flag.MOVE,Flag.LOOK));}
    @Override public boolean canUse(){return Passthrough.active && mob.getTarget()!=null
        && mob.getTarget().isAlive() && MobWar.targetFor(mob,mob.getTarget());}
    @Override public boolean canContinueToUse(){return canUse();}
    @Override public boolean requiresUpdateEveryTick(){return true;}
    @Override public void start(){mob.getNavigation().stop();}
    @Override public void stop(){mob.getNavigation().stop();}
    @Override public void tick(){
        var target=mob.getTarget();if(target==null)return;
        mob.getLookControl().setLookAt(target,30,30);
        double dx=target.getX()-mob.getX(),dz=target.getZ()-mob.getZ(),distance=Math.hypot(dx,dz);
        float yaw=(float)(Math.toDegrees(Math.atan2(dz,dx))-90);
        mob.setYRot(yaw);mob.yBodyRot=yaw;
        double reach=(mob.getBbWidth()+target.getBbWidth())*.5+.4;
        boolean ranged=mob instanceof RangedAttackMob;
        boolean clear=HostNavigation.canAttack(mob,target.position());
        Vec3 waypoint=HostNavigation.next(mob,target.position());
        double stop=ranged?8:reach;
        if(waypoint!=null && !(clear && distance<=stop && Math.abs(target.getY()-mob.getY())<1)) {
            double wx=waypoint.x-mob.getX(),wz=waypoint.z-mob.getZ(),wd=Math.hypot(wx,wz);
            if(wd>1e-4) {
                double step=Math.min(wd,Math.clamp(mob.getAttributeValue(Attributes.MOVEMENT_SPEED),.08,.35));
                mob.setYRot((float)(Math.toDegrees(Math.atan2(wz,wx))-90));mob.yBodyRot=mob.getYRot();
                if(GolemOrders.golem(mob) && mob.onGround() && HostTerrain.lowLedge(mob,wx,wz))mob.getJumpControl().jump();
                mob.move(MoverType.SELF,new Vec3(wx/wd*step,0,wz/wd*step));
                if(mob.horizontalCollision && ++avoidTicks>=20){HostNavigation.stuck(mob);avoidTicks=0;}
                else if(!mob.horizontalCollision)avoidTicks=0;
            }
        }
        if(mob instanceof Creeper creeper) {
            creeper.setSwellDir(clear && distance<3 && Math.abs(target.getY()-mob.getY())<2.5?1:-1);
            return;
        }
        if(attackCooldown>0)attackCooldown--;
        if(mob instanceof RangedAttackMob shooter && clear && distance<=12 && attackCooldown==0) {
            shooter.performRangedAttack(target,1.0f);attackCooldown=40;return;
        }
        if(!ranged && clear && distance<=reach && Math.abs(target.getY()-mob.getY())<2.5 && attackCooldown==0 && mob.level() instanceof ServerLevel level) {
            mob.swingForAttack(InteractionHand.MAIN_HAND);
            mob.doHurtTarget(level,target);
            attackCooldown=20;
        }
    }
}
