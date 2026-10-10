package dev.rehan.passthrough;
import com.google.gson.JsonObject;
import net.minecraft.world.entity.Mob;
/** Hits on render replicas are applied only by the Minecraft server owning the real mob. */
public final class PeerCombat {
    private static final PeerAttackPolicy policy=new PeerAttackPolicy();
    private PeerCombat() {}
    public static void attack(JsonObject message) {
        var server=WorldBridge.server();if(server==null)return;
        long scene=message.get("scene").getAsLong(),sequence=message.get("seq").getAsLong();
        int id=message.get("id").getAsInt(),attacker=message.get("attacker").getAsInt();
        double damage=message.get("d").getAsDouble();
        var from=message.getAsJsonArray("from");
        if(from==null || from.size()!=3)return;
        double x=from.get(0).getAsDouble(),y=from.get(1).getAsDouble(),z=from.get(2).getAsDouble();
        WorldBridge.serverWork(server,()->{
            if(!Passthrough.active || !MapBuilds.ready || server!=WorldBridge.server() || scene!=MapBuilds.scene())return;
            var level=server.overworld();var target=level.getEntity(id);
            if(!(target instanceof Mob mob) || !mob.isAlive() || MobWar.isProxy(mob) || !MapBuilds.ownsEntity(mob))return;
            if(!policy.accept(MapBuilds.scene(),scene,attacker,sequence,damage,mob.distanceToSqr(x,y,z)))return;
            // The attacker lives in another private guest world; never credit this owner's local player.
            mob.hurtServer(level,level.damageSources().generic(),(float)damage);
        });
    }
}
