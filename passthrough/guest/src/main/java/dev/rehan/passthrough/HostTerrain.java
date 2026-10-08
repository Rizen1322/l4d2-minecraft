package dev.rehan.passthrough;

import com.google.gson.JsonArray;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.storage.LevelResource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.entity.projectile.Projectile;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.shapes.Shapes;
import net.minecraft.world.phys.shapes.VoxelShape;

/** Transient per-entity Source floor/wall planes. No saved or selectable blocks. */
public final class HostTerrain {
    private record Support(Entity entity,double x,double z,boolean floor,double y,
                           double xmin,double xmax,double zmin,double zmax,long at) {}
    private static final HashMap<Integer,Support> supports=new HashMap<>(); // Server thread only.
    // Immutable snapshots also supply the client's predicted TNT/item collisions.
    private static volatile Map<Integer,Support> clientSupports=Map.of();
    private static volatile MinecraftServer server;
    private static int ticks;

    public static void attach(MinecraftServer value){
        server=value.getWorldPath(LevelResource.ROOT).normalize().getFileName().toString().equals("l4d2mc-guest")?value:null;
        supports.clear();clientSupports=Map.of();ticks=0;
    }
    public static void detach(){supports.clear();clientSupports=Map.of();server=null;}

    private static boolean physical(Entity e){return !(e instanceof Player) && !(e instanceof Projectile)
        && !MobWar.isProxy(e) && (!e.isNoGravity() || e instanceof Mob);}
    public static boolean shouldFreeze(Entity e){
        MinecraftServer current=server;
        if(current==null || e.level()!=current.overworld() || e instanceof Player || MobWar.isProxy(e))return false;
        if(!Passthrough.active)return true;
        if(!physical(e))return false;
        Support s=supports.get(e.getId());
        return !Passthrough.active || s==null || s.entity!=e || System.nanoTime()-s.at>1_000_000_000L || Math.hypot(e.getX()-s.x,e.getZ()-s.z)>1.5;
    }

    public static void update(JsonArray rows){
        MinecraftServer current=server;
        if(current==null || rows.size()>64)return;
        List<double[]> copy=new ArrayList<>();
        for(var row:rows){
            var a=row.getAsJsonArray();if(a.size()!=9)continue;
            double[] v=new double[9];boolean valid=true;
            for(int i=0;i<9;i++){v[i]=a.get(i).getAsDouble();if(!Double.isFinite(v[i]))valid=false;}
            if(valid && v[0]>0 && v[0]<Integer.MAX_VALUE && v[0]==Math.rint(v[0])
                    && Math.abs(v[1])<=1023 && Math.abs(v[2])<=1023 && Math.abs(v[4])<=1023
                    && Math.abs(v[5])<=4096 && Math.abs(v[6])<=4096 && Math.abs(v[7])<=4096 && Math.abs(v[8])<=4096)copy.add(v);
        }
        long received=System.nanoTime();
        var clientCopy=new HashMap<>(clientSupports);
        clientCopy.entrySet().removeIf(entry->received-entry.getValue().at>1_000_000_000L);
        for(double[] v:copy)clientCopy.put((int)v[0],new Support(null,v[1],v[2],v[3]==1,v[4],v[5],v[6],v[7],v[8],received));
        clientSupports=Map.copyOf(clientCopy);
        current.execute(()->{
            if(server!=current || !Passthrough.active)return;
            ServerLevel level=current.overworld();
            for(double[] v:copy){
                Entity e=level.getEntity((int)v[0]);
                if(e==null || e instanceof Player || MobWar.isProxy(e))continue;
                if(Math.hypot(e.getX()-v[1],e.getZ()-v[2])>3)continue;
                Support s=new Support(e,v[1],v[2],v[3]==1,v[4],v[5],v[6],v[7],v[8],System.nanoTime());
                if(s.floor && e.getY()<s.y && s.y-e.getY()<2){
                    e.setPos(e.getX(),s.y,e.getZ());
                    e.setDeltaMovement(e.getDeltaMovement().multiply(1,0,1));e.setOnGround(true);
                }
                supports.put(e.getId(),s);
            }
        });
    }

    public static List<VoxelShape> shapes(Entity e,AABB query){
        if(!Passthrough.active || e==null || e instanceof Player || MobWar.isProxy(e))return List.of();
        boolean client=e.level().isClientSide();
        Support s=(client?clientSupports:supports).get(e.getId());
        if(s==null || (!client && s.entity!=e) || System.nanoTime()-s.at>1_000_000_000L)return List.of();
        if(Math.hypot(e.getX()-s.x,e.getZ()-s.z)>2)return List.of();
        List<VoxelShape> result=new ArrayList<>(5);
        double lo=s.y-8,hi=s.y+8;
        if(s.floor)add(result,query,new AABB(s.x-2,s.y-0.25,s.z-2,s.x+2,s.y,s.z+2));
        if(s.xmin>-2048)add(result,query,new AABB(s.xmin-0.25,lo,s.z-2,s.xmin,hi,s.z+2));
        if(s.xmax<2048)add(result,query,new AABB(s.xmax,lo,s.z-2,s.xmax+0.25,hi,s.z+2));
        if(s.zmin>-2048)add(result,query,new AABB(s.x-2,lo,s.zmin-0.25,s.x+2,hi,s.zmin));
        if(s.zmax<2048)add(result,query,new AABB(s.x-2,lo,s.zmax,s.x+2,hi,s.zmax+0.25));
        return result;
    }
    private static void add(List<VoxelShape> result,AABB query,AABB shape){if(query.intersects(shape))result.add(Shapes.create(shape));}

    public static void tick(MinecraftServer current){
        if(++ticks%2!=0 || !Passthrough.active || current!=server)return;
        ServerLevel level=current.overworld();
        Player player=current.getPlayerList().getPlayers().isEmpty()?null:current.getPlayerList().getPlayers().getFirst();
        if(player==null)return;
        supports.entrySet().removeIf(entry->entry.getValue().entity.isRemoved() || System.nanoTime()-entry.getValue().at>2_000_000_000L);
        var near=level.getEntities((Entity)null,player.getBoundingBox().inflate(48),e->physical(e) && e.isAlive());
        near.sort(Comparator.comparingDouble(e->e.distanceToSqr(player)));
        StringBuilder out=new StringBuilder("{\"t\":\"phys\",\"p\":[");int n=0;
        for(Entity e:near){
            if(n>=64)break;
            out.append(n++==0?"":",").append(String.format(Locale.ROOT,"[%d,%.4f,%.4f,%.4f,%.3f,%.3f,%d]",
                e.getId(),e.getX(),e.getY(),e.getZ(),e.getBbWidth(),e.getBbHeight(),e instanceof Mob?1:0));
        }
        Passthrough.events.accept(out.append("]}").toString());
    }
}
