package dev.rehan.passthrough;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;

/** Real vanilla fire blocks; virtual support never becomes a saved/colliding barrier cube. */
public final class GuestFire {
    private static final Map<BlockPos,Double> virtualFloors=new ConcurrentHashMap<>();
    private static final Set<BlockPos> fires=new HashSet<>(); // Server thread only.
    private GuestFire() {}
    public static void reset(){virtualFloors.clear();fires.clear();}
    public static boolean support(BlockGetter level,BlockPos fire){
        return Passthrough.active && MapBuilds.ready && WorldBridge.server()!=null && virtualFloors.containsKey(fire)
            && level instanceof net.minecraft.world.level.Level l && l.dimension()==net.minecraft.world.level.Level.OVERWORLD
            && (!(level instanceof ServerLevel s) || s==WorldBridge.server().overworld());
    }
    public static BlockState floor(BlockGetter level,BlockPos at){
        return support(level,at.above())?Blocks.STONE.defaultBlockState():level.getBlockState(at);
    }
    public static boolean reserve(ServerLevel level,BlockPos cell,double physicalY){
        if(virtualFloors.size()>=64 || !level.isInWorldBounds(cell) || !level.getBlockState(cell).isAir()
            || !level.getBlockState(cell).getFluidState().isEmpty())return false;
        virtualFloors.put(cell.immutable(),physicalY);return true;
    }
    public static void release(BlockPos cell){virtualFloors.remove(cell);}
    public static void changed(BlockPos cell,BlockState state){
        BlockPos key=cell.immutable();
        if(state.is(net.minecraft.tags.BlockTags.FIRE))fires.add(key);
        else {fires.remove(key);virtualFloors.remove(key);}
    }
    public static void report(net.minecraft.server.level.ServerPlayer player){
        var level=player.level();
        fires.removeIf(p->{if(level.getBlockState(p).is(net.minecraft.tags.BlockTags.FIRE))return false;virtualFloors.remove(p);return true;});
        var near=fires.stream().filter(p->player.distanceToSqr(p.getX()+.5,p.getY(),p.getZ()+.5)<48*48)
            .sorted(Comparator.comparingDouble(p->player.distanceToSqr(p.getX()+.5,p.getY(),p.getZ()+.5))).limit(32).toList();
        var text=new StringBuilder("{\"t\":\"fire\",\"p\":[");int n=0;
        for(var p:near)text.append(n++==0?"":",").append(String.format(Locale.ROOT,"[%d,%.4f,%d]",p.getX(),virtualFloors.getOrDefault(p,(double)p.getY()),p.getZ()));
        Passthrough.events.accept(text.append("]}").toString());
    }
}
