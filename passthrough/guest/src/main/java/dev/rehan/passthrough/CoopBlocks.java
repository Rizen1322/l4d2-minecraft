package dev.rehan.passthrough;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import com.google.gson.JsonObject;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
/** Shared private-scene edits. Unloaded destinations wait without forcing chunks or echoing peers. */
public final class CoopBlocks {
    private static final Map<BlockPos,Integer> changed=new LinkedHashMap<>(),pending=new LinkedHashMap<>();
    private static boolean applying;
    private static long scene,bootstrapScene;
    private CoopBlocks() {}
    public static void reset(){changed.clear();pending.clear();scene=0;bootstrapScene=0;applying=false;}
    private static boolean privateWorld(MinecraftServer s){return s.getWorldPath(net.minecraft.world.level.storage.LevelResource.ROOT).normalize().getFileName().toString().equals("l4d2mc-guest");}
    private static void current(){long token=MapBuilds.scene();if(token!=scene){changed.clear();pending.clear();scene=token;bootstrapScene=0;}}
    public static void changed(ServerLevel level,BlockPos pos,BlockState state) {
        if(applying || !MapBuilds.ready || !privateWorld(level.getServer()) || state.is(Blocks.BARRIER) || Nether.isGround(pos)
            || Math.abs((long)pos.getX())>1023 || Math.abs((long)pos.getZ())>1023 || !level.isInWorldBounds(pos))return;
        current();int id=Block.getId(state);if(id<0 || id>65535)return;
        changed.put(pos.immutable(),id);
    }
    public static void flush() {
        current();if(scene<=0 || !MapBuilds.ready){changed.clear();return;}
        var batch=new ArrayList<CoopBlockPolicy.Row>(256);
        for(var entry:changed.entrySet()) {
            var p=entry.getKey();batch.add(new CoopBlockPolicy.Row(p.getX(),p.getY(),p.getZ(),entry.getValue()));
            if(batch.size()==256){Passthrough.events.accept(CoopBlockPolicy.encode(scene,batch,false));batch.clear();}
        }
        if(!batch.isEmpty())Passthrough.events.accept(CoopBlockPolicy.encode(scene,batch,false));changed.clear();
    }
    public static void snapshot() {
        current();if(scene<=0 || !MapBuilds.ready)return;
        var batch=new ArrayList<CoopBlockPolicy.Row>(256);
        for(var entry:MapBuilds.networkSnapshot().entrySet()) {
            var p=entry.getKey();batch.add(new CoopBlockPolicy.Row(p.getX(),p.getY(),p.getZ(),entry.getValue()));
            if(batch.size()==256){Passthrough.events.accept(CoopBlockPolicy.encode(scene,batch,true));batch.clear();}
        }
        if(!batch.isEmpty())Passthrough.events.accept(CoopBlockPolicy.encode(scene,batch,true));
        bootstrapScene=scene;
    }
    public static void snapshotIfNeeded(){current();if(bootstrapScene!=scene)snapshot();}
    public static void apply(JsonObject message) {
        var s=WorldBridge.server();if(s==null || !message.has("scene") || !privateWorld(s))return;
        long token=message.get("scene").getAsLong();
        var rows=CoopBlockPolicy.decode(message.getAsJsonArray("rows"),s.overworld().getMinY(),s.overworld().getMaxY()+1);
        for(var row:rows){var state=Block.stateById(row.state());if(Block.getId(state)!=row.state() || state.is(Blocks.BARRIER))throw new IllegalArgumentException("Unknown/transient coop registry state");}
        WorldBridge.serverWork(s,()->{
            if(!Passthrough.active || !MapBuilds.ready || token!=MapBuilds.scene())return;current();
            long additions=rows.stream().map(row->new BlockPos(row.x(),row.y(),row.z())).distinct().filter(p->!pending.containsKey(p)).count();
            if(pending.size()+additions>20000)throw new IllegalArgumentException("Coop pending scene exceeds20000cells");
            for(var row:rows)pending.put(new BlockPos(row.x(),row.y(),row.z()),row.state());
            tick(s);
        });
    }
    public static void tick(MinecraftServer s) {
        current();if(!MapBuilds.ready || !Passthrough.active || s!=WorldBridge.server() || !privateWorld(s))return;
        int applied=0;applying=true;
        try {
            var level=s.overworld();var iterator=pending.entrySet().iterator();
            while(iterator.hasNext() && applied<256) {
                var entry=iterator.next();BlockPos p=entry.getKey();
                if(!level.isLoaded(p))continue;
                if(!Nether.isGround(p))level.setBlock(p,Block.stateById(entry.getValue()),Block.UPDATE_CLIENTS|Block.UPDATE_KNOWN_SHAPE);
                iterator.remove();applied++;
            }
        }finally{applying=false;}
    }
}
