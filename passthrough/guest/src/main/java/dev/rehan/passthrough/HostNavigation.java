package dev.rehan.passthrough;

import com.google.gson.JsonObject;
import java.util.*;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.phys.Vec3;

/** Source navmesh requests/replies, server-thread state; no direct pursuit fallback through walls. */
public final class HostNavigation {
    private static final Map<Integer,State> states=new HashMap<>();
    private static int serial;
    private static final class State {
        Mob entity;Vec3 goal,origin,visibleGoal;int query;
        long sent,started,received;
        NavCursor cursor;boolean los;
    }
    public static void clear(){states.clear();}
    private static State state(Mob mob,Vec3 goal){
        long now=System.nanoTime();State s=states.get(mob.getId());
        if(s==null || s.entity!=mob){s=new State();s.entity=mob;states.put(mob.getId(),s);}
        boolean changed=s.goal==null || s.goal.distanceToSqr(goal)>1;
        boolean expired=s.received>0?now-s.received>1_200_000_000L:now-s.started>30_000_000_000L;
        if(s.goal==null || expired || (changed && s.received>0)) {
            s.goal=goal;s.query=++serial;s.cursor=null;s.los=false;s.received=0;s.started=now;s.sent=0;
        }
        if(now-s.sent>500_000_000L) {
            s.sent=now;
            Passthrough.events.accept(String.format(Locale.ROOT,"{\"t\":\"nav\",\"id\":%d,\"q\":%d,\"from\":[%.4f,%.4f,%.4f],\"goal\":[%.4f,%.4f,%.4f],\"w\":%.3f,\"h\":%.3f}",
                mob.getId(),s.query,mob.getX(),mob.getY(),mob.getZ(),s.goal.x,s.goal.y,s.goal.z,(double)mob.getBbWidth(),(double)mob.getBbHeight()));
        }
        if(states.size()>128)states.entrySet().removeIf(e->e.getValue().entity.isRemoved() || now-e.getValue().sent>10_000_000_000L);
        return s;
    }
    public static Vec3 next(Mob mob,Vec3 goal){
        State s=state(mob,goal);
        if(s.cursor==null || System.nanoTime()-s.received>1_500_000_000L)return null;
        double[] p=s.cursor.next(mob.getX(),mob.getY(),mob.getZ());
        return p==null?null:new Vec3(p[0],p[1],p[2]);
    }
    public static boolean canAttack(Mob mob,Vec3 goal){
        State s=states.get(mob.getId());return s!=null && s.entity==mob && s.los && s.origin!=null && s.visibleGoal!=null
            && s.entity.position().distanceToSqr(s.origin)<=.0625 && s.visibleGoal.distanceToSqr(goal)<=.0625
            && System.nanoTime()-s.received<1_500_000_000L;
    }
    public static void stuck(Mob mob){State s=states.get(mob.getId());if(s!=null){s.cursor=null;s.received=0;s.started=0;}}
    public static void reply(JsonObject m){
        int id=m.get("id").getAsInt(),q=m.get("q").getAsInt();boolean los=m.has("los") && m.get("los").getAsBoolean();
        var origin=m.getAsJsonArray("origin");var visibleGoal=m.getAsJsonArray("goal");
        if(origin==null || visibleGoal==null || origin.size()!=3 || visibleGoal.size()!=3)return;
        double[] op=new double[3],gp=new double[3];
        for(int k=0;k<3;k++) {
            op[k]=origin.get(k).getAsDouble();gp[k]=visibleGoal.get(k).getAsDouble();
            if(!Double.isFinite(op[k]) || !Double.isFinite(gp[k]) || Math.abs(op[k])>1023 || Math.abs(gp[k])>1023)return;
        }
        var rows=m.getAsJsonArray("p");if(rows==null || rows.size()>32)return;
        double[][] points=new double[rows.size()][3];
        for(int i=0;i<rows.size();i++) {
            var row=rows.get(i).getAsJsonArray();if(row.size()!=3)return;
            for(int k=0;k<3;k++){double v=row.get(k).getAsDouble();if(!Double.isFinite(v) || Math.abs(v)>1023)return;points[i][k]=v;}
        }
        var server=WorldBridge.server();if(server==null)return;
        server.execute(()->{State s=states.get(id);if(s==null || s.query!=q || s.entity.isRemoved() || !Passthrough.active)return;
            s.cursor=new NavCursor(points);s.received=System.nanoTime();s.los=los;
            s.origin=new Vec3(op[0],op[1],op[2]);s.visibleGoal=new Vec3(gp[0],gp[1],gp[2]);
        });
    }
}
