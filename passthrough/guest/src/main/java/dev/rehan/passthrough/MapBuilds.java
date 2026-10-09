package dev.rehan.passthrough;

import java.nio.file.*;
import java.util.*;
import net.minecraft.core.BlockPos;
import net.minecraft.nbt.*;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.storage.LevelResource;

/** Per-Source-map builds, including containers, confined to the private guest world. */
public final class MapBuilds {
    private record Cell(BlockState state, CompoundTag data) {}
    private record Edit(BlockPos pos,Cell cell) {}
    private static final Map<BlockPos,Cell> cells=new LinkedHashMap<>();
    private static final Set<BlockPos> touched=new LinkedHashSet<>();
    private static final ArrayDeque<Edit> edits=new ArrayDeque<>();
    private record Loaded(ServerLevel level,LevelChunk chunk) {}
    private static final List<Loaded> earlyChunks=new ArrayList<>();
    private static MinecraftServer server;
    private static volatile String requested="";
    private static int retryTicks;
    private static boolean recovering,commitPending;
    private static Path directory;
    private static volatile long requestedEpoch;
    private record Selection(String map,long epoch,long scene) {}
    private static volatile Selection selection=new Selection("",0,0);
    private static long requestedScene;
    private static volatile long scene;
    public static long scene(){return scene;}
    private static long epoch=-1;
    private static String map="",pending="";
    private static boolean applying;
    private static int ticks;
    public static volatile boolean ready=true;
    public static void attach(MinecraftServer s){
        Path root=s.getWorldPath(LevelResource.ROOT).normalize();
        server=root.getFileName().toString().equals("l4d2mc-guest")?s:null;
        cells.clear();touched.clear();edits.clear();scene=0;epoch=-1;map="";pending="";recovering=false;commitPending=false;retryTicks=0;ready=server==null;
        if(server==null)return;
        directory=root.resolve("l4d2mc-maps");
        try {
            Files.createDirectories(directory);
            Path marker=directory.resolve("active.txt");
            if(Files.exists(marker)) {
                String old=Files.readString(marker).trim();
                if(valid(old)){map=old;cells.putAll(read(old));}else throw new IllegalStateException("Invalid map marker");
            }
            Path journal=directory.resolve("transition.txt");
            if(Files.exists(journal)) {
                List<String> intent=Files.readAllLines(journal);
                if((intent.size()!=2 && intent.size()!=3) || !valid(intent.get(0)) || !valid(intent.get(1)))throw new IllegalStateException("Invalid transition journal");
                // Restore the original complete archive before accepting another
                // map. Never capture the partially edited vanilla world.
                Path originFile=directory.resolve(intent.get(0)+".dat");
                if(intent.size()==3){
                    String snap=intent.get(2);if(!snap.matches("[A-Za-z0-9_-]+\\.dat"))throw new IllegalStateException("Invalid snapshot reference");
                    originFile=directory.resolve("snapshots").resolve(snap);
                    if(!Files.exists(originFile))throw new IllegalStateException("Recovery snapshot missing");
                }
                Map<BlockPos,Cell> original=readFile(originFile),target=read(intent.get(1));
                Set<BlockPos> union=new LinkedHashSet<>(original.keySet());union.addAll(target.keySet());
                Path dirty=directory.resolve("checkpoint.dat");
                if(Files.exists(dirty)) {
                    var checkpoint=NbtIo.readCompressed(dirty,NbtAccounter.create(8L*1024*1024));
                    var footprint=checkpoint.getList("positions").orElseThrow();
                    if(footprint.size()>60000)throw new IllegalStateException("Recovery footprint too large");
                    for(int i=0;i<footprint.size();i++) {
                        var row=footprint.getCompoundOrEmpty(i);var p=new BlockPos(row.getInt("x").orElseThrow(),row.getInt("y").orElseThrow(),row.getInt("z").orElseThrow());
                        if(Math.abs(p.getX())>1023 || Math.abs(p.getZ())>1023 || !s.overworld().isInWorldBounds(p))throw new IllegalStateException("Recovery footprint outside bounds");
                        union.add(p);
                    }
                }
                if(union.size()>60000)throw new IllegalStateException("Recovery union too large");
                touched.addAll(union); // Keep tombstones through repeated interrupted recoveries.
                for(BlockPos p:union)edits.add(new Edit(p,new Cell(Blocks.AIR.defaultBlockState(),null)));
                for(var entry:original.entrySet())edits.add(new Edit(entry.getKey(),entry.getValue()));
                cells.clear();map="";pending=intent.get(0);recovering=true;
            }
            Path checkpoint=directory.resolve("checkpoint.dat");
            if(!recovering && Files.exists(checkpoint)) {
                CompoundTag recovery=NbtIo.readCompressed(checkpoint,NbtAccounter.create(8L*1024*1024));
                String saved=recovery.getString("map").orElseThrow();
                if(!valid(saved))throw new IllegalStateException("Invalid checkpoint marker");
                if(Files.exists(directory.resolve(saved+".dat"))) {
                    Map<BlockPos,Cell> original=read(saved);
                    // Collect disk-world positions only for clearing; their data
                    // cannot replace the durable archive during recovery.
                    for(Loaded loaded:earlyChunks)if(loaded.level.getServer()==s)chunk(loaded.level,loaded.chunk);
                    Set<BlockPos> union=new LinkedHashSet<>(cells.keySet());union.addAll(original.keySet());
                    var footprint=recovery.getList("positions").orElseThrow();
                    if(footprint.size()>60000)throw new IllegalStateException("Oversized checkpoint footprint");
                    for(int i=0;i<footprint.size();i++) {
                        var row=footprint.getCompoundOrEmpty(i);
                        BlockPos pos=new BlockPos(row.getInt("x").orElseThrow(),row.getInt("y").orElseThrow(),row.getInt("z").orElseThrow());
                        if(Math.abs(pos.getX())>1023 || Math.abs(pos.getZ())>1023 || !s.overworld().isInWorldBounds(pos))throw new IllegalStateException("Invalid checkpoint position");
                        union.add(pos);
                    }
                    touched.addAll(union); // Keep tombstones through repeated interrupted recoveries.
                for(BlockPos p:union)edits.add(new Edit(p,new Cell(Blocks.AIR.defaultBlockState(),null)));
                    for(var entry:original.entrySet())edits.add(new Edit(entry.getKey(),entry.getValue()));
                    cells.clear();map="";pending=saved;recovering=true;
                }
            }
            if(!recovering)for(Loaded loaded:earlyChunks)if(loaded.level.getServer()==s)chunk(loaded.level,loaded.chunk);
            earlyChunks.clear();
        }catch(Exception e){Passthrough.LOG.error("Cannot open map archive; switching disabled",e);server=null;ready=false;}
    }
    private static boolean valid(String name){return name.matches("[A-Za-z0-9_]{1,96}");}
    public static void select(String name,long session,long token){
        if(valid(name) && session>=0 && token>0){selection=new Selection(name,session,token);} // Retain requests received before SERVER_STARTED.
    }
    private static void begin(String name){
        if(!pending.isEmpty() || commitPending)return;
        if(map.equals(name) && epoch==requestedEpoch){ready=true;notice();return;}
        ready=false;WorldBridge.clearTransient();SurvivalFeatures.resetEnvironment();HostNavigation.clear();RedstoneLinks.clear();WorldBridge.resetBarricades();
        try {
            Map<BlockPos,Cell> next=Map.of(); // New host round/map begins with an empty guest scene; preserve the previous archive first.
            if(map.isEmpty() && !cells.isEmpty())map="legacy_unassigned";
            if(!map.isEmpty()) {
                save();
                Path snapshots=directory.resolve("snapshots");Files.createDirectories(snapshots);
                String snapshot=map+"-"+epoch+"-"+UUID.randomUUID()+".dat";
                Files.copy(directory.resolve(map+".dat"),snapshots.resolve(snapshot));
                Path temp=directory.resolve("transition.tmp");Files.write(temp,List.of(map,name,snapshot));
                Files.move(temp,directory.resolve("transition.txt"),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);
            }
            MobWar.hostGone();clearEntities();
            epoch=requestedEpoch;scene=requestedScene;pending=name;
            for(BlockPos p:cells.keySet())edits.add(new Edit(p,new Cell(Blocks.AIR.defaultBlockState(),null)));
            for(var entry:next.entrySet())edits.add(new Edit(entry.getKey(),entry.getValue()));
            // Empty initial scenes need no block-clear transaction.
            if(map.isEmpty() && edits.isEmpty()){pending="";map=name;commitPending=true;commit();}
        }catch(Exception e){pending="";edits.clear();retryTicks=100;Passthrough.LOG.error("Map archive failed; existing builds preserved",e);}
    }
    public static boolean ownsEntity(net.minecraft.world.entity.Entity e){
        if(e instanceof net.minecraft.world.entity.player.Player)return true;
        if(server==null || e.level()!=server.overworld())return true;
        String tag="l4d2mc_scene_"+map+"_"+epoch;
        boolean stale=e.entityTags().stream().anyMatch(t->t.startsWith("l4d2mc_scene_") && !t.equals(tag));
        if(stale){e.discard();return false;}
        e.addTag(tag);return true;
    }
    private static void clearEntities(){
        if(server==null)return;
        var all=new ArrayList<net.minecraft.world.entity.Entity>();server.overworld().getAllEntities().forEach(all::add);
        for(var e:all)if(!(e instanceof net.minecraft.world.entity.player.Player))e.discard();
    }
    private static void notice(){Passthrough.events.accept("{\"t\":\"mapready\",\"map\":\""+map+"\",\"epoch\":"+epoch+",\"ready\":"+ready+"}");}
    private static Cell capture(ServerLevel level,BlockPos p,BlockState state){
        BlockEntity be=level.getBlockEntity(p);
        return new Cell(state,be==null?null:be.saveWithFullMetadata(level.registryAccess()));
    }
    public static void changed(ServerLevel level,BlockPos p,BlockState state){
        if(server==null || level!=server.overworld() || applying || state.is(Blocks.BARRIER) || Nether.isGround(p))return;
        if(Math.abs(p.getX())>1023 || Math.abs(p.getZ())>1023)return;
        touched.add(p.immutable());
        if(state.isAir())cells.remove(p);else cells.put(p.immutable(),capture(level,p,state));
    }
    public static void chunk(ServerLevel level,LevelChunk chunk){
        if(server==null) {
            if(level.getServer().getWorldPath(LevelResource.ROOT).normalize().getFileName().toString().equals("l4d2mc-guest") && earlyChunks.size()<1024)earlyChunks.add(new Loaded(level,chunk));
            return;
        }
        if(level!=server.overworld() || applying || !pending.isEmpty())return;
        var sections=chunk.getSections();var p=new BlockPos.MutableBlockPos();
        for(int section=0;section<sections.length;section++) {
            var data=sections[section];if(data.hasOnlyAir())continue;
            int base=level.getMinY()+section*16;
            for(int x=0;x<16;x++)for(int y=0;y<16;y++)for(int z=0;z<16;z++) {
                var state=data.getBlockState(x,y,z);
                if(state.isAir() || state.is(Blocks.BARRIER))continue;
                p.set(chunk.getPos().getMinBlockX()+x,base+y,chunk.getPos().getMinBlockZ()+z);
                if(Math.abs(p.getX())<=1023 && Math.abs(p.getZ())<=1023 && !Nether.isGround(p)) {
                    // CHUNK_LOAD fires before the chunk future completes. A
                    // level.getBlockEntity lookup waits for that same future and
                    // recursively enters other chunk callbacks: use this chunk.
                    BlockEntity be=chunk.getBlockEntity(p);
                    if(!map.isEmpty() && !requested.isEmpty()) {
                        Cell expected=cells.get(p);
                        if(expected==null){touched.add(p.immutable());edits.add(new Edit(p.immutable(),new Cell(Blocks.AIR.defaultBlockState(),null)));}
                    } else cells.put(p.immutable(),new Cell(state,be==null?null:be.saveWithFullMetadata(level.registryAccess())));
                }
            }
        }
    }
    public static void unload(ServerLevel level,LevelChunk chunk){
        if(server==null || level!=server.overworld() || applying || !pending.isEmpty())return;
        int cx=chunk.getPos().x(),cz=chunk.getPos().z();
        for(var entry:cells.entrySet()) {
            BlockPos p=entry.getKey();if((p.getX()>>4)==cx && (p.getZ()>>4)==cz) {
                BlockEntity be=chunk.getBlockEntity(p);
                entry.setValue(new Cell(chunk.getBlockState(p),be==null?null:be.saveWithFullMetadata(level.registryAccess())));
            }
        }
    }
    private static Map<BlockPos,Cell> read(String name)throws Exception {
        return readFile(directory.resolve(name+".dat"));
    }
    private static Map<BlockPos,Cell> readFile(Path file)throws Exception {
        Map<BlockPos,Cell> result=new LinkedHashMap<>();
        if(!Files.exists(file))return result;
        CompoundTag root=NbtIo.readCompressed(file,NbtAccounter.create(32L*1024*1024));
        if(root.getIntOr("version",0)!=1)throw new IllegalStateException("Unknown archive version");
        var list=root.getList("blocks").orElseThrow(()->new IllegalStateException("Missing archive block list"));if(list.size()>20000)throw new IllegalStateException("Map build exceeds 20000 blocks");
        for(int i=0;i<list.size();i++) {
            var c=list.getCompoundOrEmpty(i);BlockPos p=new BlockPos(c.getInt("x").orElseThrow(),c.getInt("y").orElseThrow(),c.getInt("z").orElseThrow());
            if(Math.abs(p.getX())>1023 || Math.abs(p.getZ())>1023 || !server.overworld().isInWorldBounds(p))throw new IllegalStateException("Invalid archived position");
            BlockState state=BlockState.CODEC.parse(NbtOps.INSTANCE,c.getCompound("state").orElseThrow()).getOrThrow();
            if(!state.isAir() && !state.is(Blocks.BARRIER))result.put(p,new Cell(state,c.getCompound("data").orElse(null)));
        }
        return result;
    }
    public static void save()throws Exception {
        if(server==null || map.isEmpty() || !pending.isEmpty())return;
        if(cells.size()>20000)throw new IllegalStateException("Map build exceeds 20000 blocks; archive unchanged");
        ServerLevel level=server.overworld();ListTag list=new ListTag();
        for(var entry:cells.entrySet()) {
            BlockPos p=entry.getKey();Cell c=entry.getValue();
            if(level.isLoaded(p))c=capture(level,p,level.getBlockState(p));
            if(c.state.isAir() || c.state.is(Blocks.BARRIER))continue;
            entry.setValue(c);
            CompoundTag row=new CompoundTag();row.putInt("x",p.getX());row.putInt("y",p.getY());row.putInt("z",p.getZ());
            row.put("state",NbtUtils.writeBlockState(c.state));if(c.data!=null)row.put("data",c.data.copy());list.add(row);
        }
        CompoundTag root=new CompoundTag();root.putInt("version",1);root.put("blocks",list);
        // A same-map save also needs a recovery marker until vanilla chunks
        // are flushed: the archive must not later be overwritten by stale disk chunks.
        Set<BlockPos> footprint=new LinkedHashSet<>(read(map).keySet());
        footprint.addAll(cells.keySet());footprint.addAll(touched);
        if(footprint.size()>60000)throw new IllegalStateException("Checkpoint footprint exceeds budget");
        ListTag positions=new ListTag();
        for(BlockPos p:footprint) {
            CompoundTag row=new CompoundTag();row.putInt("x",p.getX());row.putInt("y",p.getY());row.putInt("z",p.getZ());positions.add(row);
        }
        CompoundTag checkpoint=new CompoundTag();checkpoint.putString("map",map);checkpoint.put("positions",positions);
        Path dirtyTemp=directory.resolve("checkpoint.tmp");NbtIo.writeCompressed(checkpoint,dirtyTemp);
        Files.move(dirtyTemp,directory.resolve("checkpoint.dat"),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);
        Path temp=directory.resolve(map+".tmp");NbtIo.writeCompressed(root,temp);
        NbtIo.readCompressed(temp,NbtAccounter.create(32L*1024*1024)); // Validate the reader budget before replacing the last archive.
        Files.move(temp,directory.resolve(map+".dat"),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);
        Path marker=directory.resolve("active.tmp");Files.writeString(marker,map);
        Files.move(marker,directory.resolve("active.txt"),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);
        if(!server.saveEverything(true,true,true))throw new IllegalStateException("Vanilla world flush failed");
        Files.deleteIfExists(directory.resolve("checkpoint.dat"));touched.clear();
    }
    public static void tick(MinecraftServer s){
        Selection target=selection;requested=target.map();requestedEpoch=target.epoch();requestedScene=target.scene();
        if(s!=server)return;
        if(retryTicks>0)retryTicks--;
        if(pending.isEmpty() && !edits.isEmpty() && !map.isEmpty()){pending=map;ready=false;}
        if(pending.isEmpty() && !requested.isEmpty() && (!map.equals(requested) || epoch!=requestedEpoch) && retryTicks==0)begin(requested);
        else if(pending.isEmpty() && !commitPending && !requested.isEmpty() && map.equals(requested) && epoch==requestedEpoch){ready=true;if(ticks%20==0)notice();}
        if(!pending.isEmpty()) {
            applying=true;WorldBridge.quietGround(true);
            try {
                for(int i=0;i<64 && !edits.isEmpty();i++) {
                    Edit edit=edits.peek();ServerLevel level=s.overworld();
                    level.setBlock(edit.pos,edit.cell.state,Block.UPDATE_CLIENTS|Block.UPDATE_KNOWN_SHAPE);
                    if(edit.cell.data!=null) {
                        BlockEntity be=BlockEntity.loadStatic(edit.pos,edit.cell.state,edit.cell.data,level.registryAccess());
                        if(be!=null){level.setBlockEntity(be);be.setChanged();}
                    }
                    if(edit.cell.state.isAir())cells.remove(edit.pos);else cells.put(edit.pos,edit.cell);
                    edits.remove();
                }
            }finally{applying=false;WorldBridge.quietGround(false);}
            if(edits.isEmpty()) {
                map=pending;pending="";
                commitPending=true;ready=false;
                commit();
            }
        }else if(commitPending){if(++ticks%20==0)commit();}
        else if(++ticks%1200==0)try{save();}catch(Exception e){Passthrough.LOG.error("Cannot autosave map builds",e);}
    }
    private static void commit(){
        try {
            save();Files.deleteIfExists(directory.resolve("transition.txt"));
            recovering=false;commitPending=false;ready=map.equals(requested) && epoch==requestedEpoch;notice();
        }catch(Exception e){ready=false;Passthrough.LOG.error("Cannot commit map archive",e);}
    }
    public static void detach(){HostNavigation.clear();try{save();}catch(Exception e){Passthrough.LOG.error("Cannot save map builds",e);}server=null;cells.clear();touched.clear();edits.clear();earlyChunks.clear();requested="";selection=new Selection("",0,0);scene=0;recovering=false;commitPending=false;ready=true;}
}
