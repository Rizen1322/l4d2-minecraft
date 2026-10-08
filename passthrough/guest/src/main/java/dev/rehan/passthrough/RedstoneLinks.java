package dev.rehan.passthrough;

import java.util.*;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;

/** Explicitly linked switches; cannot operate unrelated map entities. */
public final class RedstoneLinks {
    private static final Set<BlockPos> links=new LinkedHashSet<>();
    private static int ticks;
    public static void clear(){links.clear();}
    public static boolean link(ServerPlayer p){
        if(!Passthrough.active || !MapBuilds.ready || links.size()>=32)return false;
        BlockPos best=null;double distance=Double.MAX_VALUE;
        for(BlockPos at:BlockPos.betweenClosed(p.blockPosition().offset(-6,-3,-6),p.blockPosition().offset(6,3,6))) {
            var state=p.level().getBlockState(at);
            if(!state.is(Blocks.LEVER) && !state.hasProperty(BlockStateProperties.POWERED))continue;
            double d=at.distToCenterSqr(p.position());if(d<distance){distance=d;best=at.immutable();}
        }
        if(best==null)return false;
        links.add(best);
        Passthrough.events.accept("{\"t\":\"link\",\"pos\":["+best.getX()+","+best.getY()+","+best.getZ()+"]}");return true;
    }
    public static void tick(MinecraftServer s){
        if(++ticks%4!=0 || !Passthrough.active || !MapBuilds.ready || links.isEmpty())return;
        StringBuilder out=new StringBuilder("{\"t\":\"signals\",\"s\":[");int count=0;
        for(BlockPos p:links) {
            if(!s.overworld().isLoaded(p))continue;
            var state=s.overworld().getBlockState(p);
            boolean on=s.overworld().hasNeighborSignal(p);
            for(Direction d:Direction.values())if(state.getSignal(s.overworld(),p,d)>0)on=true;
            if(state.hasProperty(BlockStateProperties.POWERED) && state.getValue(BlockStateProperties.POWERED))on=true;
            out.append(count++==0?"":",").append("[").append(p.getX()).append(",").append(p.getY()).append(",").append(p.getZ()).append(",").append(on).append("]");
        }
        Passthrough.events.accept(out.append("]}").toString());
    }
}
