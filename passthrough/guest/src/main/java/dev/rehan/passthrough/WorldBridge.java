package dev.rehan.passthrough;

import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.entity.projectile.FireworkRocketEntity;
import net.minecraft.world.entity.projectile.Projectile;
import net.minecraft.world.entity.projectile.throwableitemprojectile.ThrownEnderpearl;
import net.minecraft.world.entity.projectile.arrow.AbstractArrow;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;

/** Server-side half: the host's collision as invisible barrier blocks, commands, and events back to the host. */
public final class WorldBridge {
	private static volatile MinecraftServer server;
	/** Barriers we placed (so a reset only removes ours, never the player's builds). */
	private static final Set<BlockPos> barriers = ConcurrentHashMap.newKeySet();
	/** Block changes this tick (server thread only): true = now solid, false = gone. Sent at the end of the tick. */
	private static final Map<BlockPos, Boolean> changes = new LinkedHashMap<>();
	/** While placing or removing the host's own ground: those changes aren't news to the host (server thread only). */
	private static boolean placingGround;
    private static long blockRevision;
    private static final CollisionCachePolicy collisionCache=new CollisionCachePolicy();
    private static String cachedCollision;private static int cachedCollisionCount;
    private static final LoadedEntityIndex<Projectile> loadedProjectiles=new LoadedEntityIndex<>();
    private static ServerLevel projectileLevel;private static boolean projectilesSeeded;
    static void entityLoaded(Entity entity,ServerLevel level){
        if(level.dimension()!=net.minecraft.world.level.Level.OVERWORLD || !(entity instanceof Projectile p))return;
        if(projectileLevel!=level){loadedProjectiles.clear();projectileLevel=level;projectilesSeeded=false;}
        loadedProjectiles.load(p.getId(),p);
    }
    static void entityUnloaded(Entity entity,ServerLevel level){
        if(level==projectileLevel && entity instanceof Projectile p)loadedProjectiles.unload(p.getId(),p);
    }

	public static void serverWork(MinecraftServer s,Runnable action){ServerDispatchPolicy.run(s.isSameThread(),s::execute,action);}

    public static void clearTransient(){changes.clear();barricadeDamage.clear();projectileOrigins.clear();collisionCache.clear();cachedCollision=null;
        loadedProjectiles.clear();projectileLevel=null;projectilesSeeded=false;}

    private WorldBridge() {
	}

	static void attach(final MinecraftServer s) {
		server = s;clearTransient();GuestFire.reset();ElytraBridge.reset();CoopBlocks.reset();
	}

	static void detach() {
		saveMigration();
        GuestFire.reset();
        ElytraBridge.reset();
        CoopBlocks.reset();
        clearTransient();
		server = null;
		barriers.clear();
	}

	public static boolean ready() {
		return server != null;
	}

	public static MinecraftServer server() {
		return server;
	}

	/** Columns of solid ground from the host: {x, z, yBottom, yTop, ...} in block coordinates (inclusive). Only air is replaced. */
	public static void solid(final int[] columns) {
		MinecraftServer s = server;
		if (s == null) {
			return;
		}

		WorldBridge.serverWork(s,() -> {
			ServerLevel level = s.overworld();
			BlockState barrier = Blocks.BARRIER.defaultBlockState();
			BlockPos.MutableBlockPos pos = new BlockPos.MutableBlockPos();
			placingGround = true;
			for (int i = 0; i + 3 < columns.length; i += 4) {
				for (int y = columns[i + 2]; y <= columns[i + 3]; y++) {
					pos.set(columns[i], y, columns[i + 1]);
					if (level.isInWorldBounds(pos) && level.getBlockState(pos).isAir()) {
						level.setBlock(pos, barrier, Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
						barriers.add(pos.immutable());
					}
				}
			}

			placingGround = false;
		});
	}

	/** Remove every barrier we placed (e.g. when the host teleports somewhere else). */
	public static void clearSolid() {
		MinecraftServer s = server;
		if (s == null) {
			return;
		}

		WorldBridge.serverWork(s,() -> {
			ServerLevel level = s.overworld();
			placingGround = true;
			for (BlockPos pos : barriers) {
				if (level.getBlockState(pos).is(Blocks.BARRIER)) {
					level.setBlock(pos, Blocks.AIR.defaultBlockState(), Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
				}
			}

			placingGround = false;
			barriers.clear();
		});
	}

    private static final java.util.Set<String> migrated = new java.util.HashSet<>();
    private static MinecraftServer migrationServer;
    private static java.nio.file.Path migrationFile;
    private static boolean migrationDirty;
    private static int migrationTicks;
    private static void saveMigration() {
        if (!migrationDirty || migrationFile==null) return;
        try {
            var temporary=migrationFile.resolveSibling("l4d2mc-support-migration-v1.tmp");
            java.nio.file.Files.write(temporary,migrated);
            java.nio.file.Files.move(temporary,migrationFile,java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            migrationDirty=false;
        } catch(java.io.IOException error) { Passthrough.LOG.warn("Cannot save support migration",error); }
    }
    /** Migration confined to our dedicated guest world: remove old bridge barriers on chunk load. */
    static void cleanLegacySupports(final ServerLevel level, final net.minecraft.world.level.chunk.LevelChunk chunk) {
        var root=level.getServer().getWorldPath(net.minecraft.world.level.storage.LevelResource.ROOT).normalize();
        if (!root.getFileName().toString().equals("l4d2mc-guest") || level.dimension()!=net.minecraft.world.level.Level.OVERWORLD) return;
        if (migrationServer!=level.getServer()) {
            migrationServer=level.getServer();migrated.clear();migrationDirty=false;
            migrationFile=root.resolve("l4d2mc-support-migration-v1.txt");
            try { if(java.nio.file.Files.exists(migrationFile)) migrated.addAll(java.nio.file.Files.readAllLines(migrationFile)); }
            catch(java.io.IOException error) { Passthrough.LOG.warn("Cannot read support migration",error);return; }
        }
        String key=chunk.getPos().x()+" "+chunk.getPos().z();
        if (migrated.contains(key)) return;
        placingGround=true;
        try {
            var sections=chunk.getSections();
            BlockPos.MutableBlockPos pos=new BlockPos.MutableBlockPos();
            for (int section=0;section<sections.length;section++) {
                var data=sections[section];
                if (!data.maybeHas(state -> state.is(Blocks.BARRIER))) continue;
                int baseY=level.getMinY()+section*16;
                for (int x=0;x<16;x++) for (int y=0;y<16;y++) for (int z=0;z<16;z++) {
                    if (!data.getBlockState(x,y,z).is(Blocks.BARRIER)) continue;
                    pos.set(chunk.getPos().getMinBlockX()+x,baseY+y,chunk.getPos().getMinBlockZ()+z);
                    chunk.setBlockState(pos,Blocks.AIR.defaultBlockState(),Block.UPDATE_KNOWN_SHAPE);
                }
            }
        } finally { placingGround=false; }
        migrated.add(key);migrationDirty=true;
    }

	/** Run a command as the server (op). Results go to the log, not to chat (send_command_feedback is off). */
	public static void command(final String command) {
		MinecraftServer s = server;
		if (s == null) {
			return;
		}

		WorldBridge.serverWork(s,() -> {
			Passthrough.LOG.info("command: {}", command);
			s.getCommands().performPrefixedCommand(s.createCommandSourceStack(), command);
		});
	}

	private static boolean solidForHost(final ServerLevel level, final BlockPos pos, final BlockState state) {
		// the Nether's ground is the host's own ground turned: nothing to collide with that isn't there already
		return !state.isAir() && !state.is(Blocks.BARRIER) && !state.getCollisionShape(level, pos).isEmpty() && !Nether.isGround(pos);
	}

	/** Arrows the host already hit something with (they stay where they hit and aren't reported again). */
	private static final String HIT_TAG = "passthrough_hit";

	/** Every server tick: block changes, and projectiles in flight for the host to trace through its own world. */
	static void tick(final MinecraftServer s) {
		MapBuilds.tick(s);
        SurvivalFeatures.tick(s);
        ElytraBridge.tick(s);
        CoopBlocks.tick(s);
        RedstoneLinks.tick(s);
        flush(s);
        if (++migrationTicks%100==0) saveMigration();
		if (Passthrough.active) {
			reportProjectiles(s.overworld());
		}

		MobWar.tick(s);
        HostTerrain.tick(s);
		Nether.tick(s);
	}

	/**
	 * Player projectiles in flight: {"t":"proj","p":[[id,kind,x,y,z,damage,launchX,launchY,launchZ],...]}. Mobs'
	 * arrows aren't traced by the host: they hit its people's proxies here.
	 */
	private static boolean thrownItem(final Entity e) {
		return e instanceof net.minecraft.world.entity.projectile.throwableitemprojectile.AbstractThrownPotion
			|| e instanceof net.minecraft.world.entity.projectile.throwableitemprojectile.Snowball
			|| e instanceof net.minecraft.world.entity.projectile.throwableitemprojectile.ThrownEgg;
	}

    private static final ProjectileOrigins projectileOrigins = new ProjectileOrigins();
	private static void reportProjectiles(final ServerLevel level) {
		StringBuilder b = null;
        var alive = new java.util.HashSet<Integer>();
        // Seed once for entities loaded before bridge attachment; subsequent
        // load/unload events maintain membership without scanning the world.
        if(projectileLevel!=level){loadedProjectiles.clear();projectileLevel=level;projectilesSeeded=false;}
        if(!projectilesSeeded){for(Entity entity:level.getAllEntities())entityLoaded(entity,level);projectilesSeeded=true;}
		for (Entity e : loadedProjectiles.values()) {
			String kind = null;
			if (e.isRemoved() || !(e instanceof Projectile projectile) || !(projectile.getOwner() instanceof Player)) {
				continue;
			}

			if (e instanceof AbstractArrow arrow && !arrow.entityTags().contains(HIT_TAG) && arrow.getDeltaMovement().lengthSqr() > 1.0E-4) {
				kind = "arrow";
			} else if (e instanceof ThrownEnderpearl) {
                kind="ender_pearl";
            } else if (e instanceof FireworkRocketEntity rocket && rocket.isShotAtAngle()) {
				kind = "firework"; // not the ones boosting an elytra flight
			} else if (thrownItem(e)) {
				kind = "thrown"; // the void guest world has no floor: Source geometry breaks them
			}

			if (kind != null) {
                alive.add(e.getId());
                var origin=projectileOrigins.remember(e.getId(),e.xo,e.yo,e.zo);
				b = b == null ? new StringBuilder("{\"t\":\"proj\",\"p\":[") : b.append(',');
                double damage=kind.equals("firework")?80.0/15.0:0;
				if(e instanceof AbstractArrow arrow) {
                    damage=Math.ceil(arrow.getDeltaMovement().length()*((dev.rehan.passthrough.mixin.ArrowDamageAccessor)arrow).l4d2mc$baseDamage());
                    if(arrow.isCritArrow())damage*=1.25;
                }
                b.append(String.format(Locale.ROOT,"[%d,\"%s\",%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f]",
                    e.getId(),kind,e.getX(),e.getY(),e.getZ(),Math.clamp(damage,0,100),origin.x(),origin.y(),origin.z()));
			}
		}
        projectileOrigins.retain(alive);

		if (b != null) {
			Passthrough.events.accept(b.append("]}").toString());
		}
	}

	/**
	 * The host traced a projectile into something of its own: a firework bursts there; an arrow goes into a person
	 * or car (gone) or sticks where it hit a wall.
	 */
	public static void projectileHit(final int id, final double x, final double y, final double z, final boolean stick) {
		MinecraftServer s = server;
		if (s == null) {
			return;
		}

		WorldBridge.serverWork(s,() -> {
			ServerLevel level = s.overworld();
			Entity e = level.getEntity(id);
			if (e instanceof ThrownEnderpearl) {
                // Source already validated and moved the real survivor.
                e.discard();
            } else if (e instanceof FireworkRocketEntity) {
				e.setPos(x, y, z);
				level.broadcastEntityEvent(e, (byte) 17);
				e.discard();
			} else if (thrownItem(e)) {
				// Break where Source's trace hit: splash/lingering effects, snowball/egg impact.
				e.setPos(x, y, z);
				e.setDeltaMovement(Vec3.ZERO);
				((dev.rehan.passthrough.mixin.ProjectileInvoker) e).l4d2mc$onHit(
					new net.minecraft.world.phys.BlockHitResult(new Vec3(x, y, z), net.minecraft.core.Direction.UP, BlockPos.containing(x, y - 0.01, z), false));
				if (!e.isRemoved()) e.discard();
			} else if (e instanceof AbstractArrow) {
				if (stick) {
					e.setPos(x, y, z);
					e.setDeltaMovement(Vec3.ZERO);
					e.setNoGravity(true);
					e.addTag(HIT_TAG);
				} else {
					e.discard();
				}
			}
		});
	}

	/** Server thread, from Level.setBlock: remember the change; flushed once per tick. */
	public static void onBlockChanged(final ServerLevel level, final BlockPos pos, final BlockState state) {
        blockRevision++;
		if (!Passthrough.active || !MapBuilds.ready || level != level.getServer().overworld()) {
			return;
		}

		Nether.onBlockChanged(pos, state);
        GuestFire.changed(pos,state);
        if(!placingGround)MapBuilds.changed(level,pos,state);
		if (!placingGround) {
			changes.put(pos.immutable(), solidForHost(level, pos, state));
            CoopBlocks.changed(level,pos,state);
            barricadeDamage.remove(pos);
		}
	}

	/** While on, block changes are the host's own ground being edited (not reported as blocks to collide with). */
	static void quietGround(final boolean on) {
		placingGround = on;
	}

	/** End of each server tick: {"t":"blocks","set":[x,y,z,...],"clear":[x,y,z,...]}. */
	static void flush(final MinecraftServer s) {
        CoopBlocks.flush();
		if (!MapBuilds.ready){changes.clear();return;}
        if (changes.isEmpty()) {
			return;
		}

		StringBuilder set = new StringBuilder();
		StringBuilder clear = new StringBuilder();
		for (Map.Entry<BlockPos, Boolean> e : changes.entrySet()) {
			StringBuilder b = e.getValue() ? set : clear;
			BlockPos p = e.getKey();
			b.append(b.isEmpty() ? "" : ",").append(p.getX()).append(',').append(p.getY()).append(',').append(p.getZ());
		}

		changes.clear();
		Passthrough.events.accept("{\"t\":\"blocks\",\"scene\":"+MapBuilds.scene()+",\"set\":[" + set + "],\"clear\":[" + clear + "]}");
	}

	/** Every solid block within `radius` of the player, as one "blocks" message (the host's props start from this). */
	public static void sync(final int radius) {
		sync(radius, 0L);
	}

	public static void sync(final int radius, final long request) {
		MinecraftServer s = server;
		if (s == null) {
			return;
		}

        long scene=MapBuilds.scene();
		WorldBridge.serverWork(s,() -> {
            if(!MapBuilds.ready || scene!=MapBuilds.scene())return;
			ServerLevel level = s.overworld();
			ServerPlayer player = s.getPlayerList().getPlayers().isEmpty() ? null : s.getPlayerList().getPlayers().get(0);
			if (player == null) {
				return;
			}
            CoopBlocks.snapshotIfNeeded();

			BlockPos c = player.blockPosition();
			BlockPos.MutableBlockPos p = new BlockPos.MutableBlockPos();
            // One complete region replaces the host cache atomically, including AIR.
            // Never truncate it silently: an omitted solid would lose its collision.
            StringBuilder cells=new StringBuilder();
            int found=0;
            boolean cacheable=true;
            int x0=Math.max(-1023,c.getX()-radius),x1=Math.min(1023,c.getX()+radius);
            int z0=Math.max(-1023,c.getZ()-radius),z1=Math.min(1023,c.getZ()+radius);
            int y0=Math.max(-1023,c.getY()-24),y1=Math.min(1023,c.getY()+40);
            int scanY0=Math.max(y0,level.getMinY()),scanY1=Math.min(y1,level.getMaxY());
            String bounds=x0+","+y0+","+z0+","+x1+","+y1+","+z1;
            // Availability is a chunk property, not a per-cell property. Also
            // validate it on cache hits: unloaded chunks must never become AIR.
            if(scanY0<=scanY1)for(int cx=x0>>4;cx<=x1>>4;cx++)for(int cz=z0>>4;cz<=z1>>4;cz++) {
                p.set(cx*16,scanY0,cz*16);
                if(!level.isLoaded(p)){collisionCache.clear();return;}
            }
            long scanRevision=blockRevision,now=System.nanoTime();
            if(cachedCollision!=null && collisionCache.reusable(level,scene,scanRevision,bounds,now)) {
                flush(s);Passthrough.events.accept(cachedCollision);
                Passthrough.events.accept("{\"t\":\"syncdone\",\"scene\":"+scene+",\"id\":"+request+",\"count\":"+cachedCollisionCount+"}");
                return;
            }
            for(int x=x0;x<=x1;x++) for(int z=z0;z<=z1;z++) {
                if(scanY0>scanY1)continue;
                p.set(x,scanY0,z);
                // Check availability once per column, without generating chunks.
                // Missing data still aborts the entire replacement snapshot.
                if(!level.isLoaded(p))return;
                var chunk=level.getChunkAt(p);
                for(int y=scanY0;y<=scanY1;) {
                    var section=chunk.getSections()[chunk.getSectionIndex(y)];
                    int end=Math.min(scanY1,y|15);
                    // The section's maintained air count is exact, including edits.
                    if(section.hasOnlyAir()){y=end+1;continue;}
                    for(;y<=end;y++) {
                        p.set(x,y,z);
                        var state=section.getBlockState(x&15,y&15,z&15);
                        // Animated/dynamic collision can change without a block
                        // state write (e.g. moving pistons or block entities).
                        if(state.hasBlockEntity() || state.getBlock().hasDynamicShape())cacheable=false;
                        if(solidForHost(level,p,state)) {
                            if(++found>10000)return;
                            cells.append(cells.isEmpty()?"":",").append(x).append(',').append(y).append(',').append(z);
                        }
                    }
                }
            }
            flush(s);
            String complete="{\"t\":\"blocks\",\"scene\":"+scene+",\"bounds\":["+bounds+"],\"set\":["+cells+"]}";
            if(cacheable){cachedCollision=complete;cachedCollisionCount=found;collisionCache.store(level,scene,scanRevision,bounds,now);}
            else{collisionCache.clear();cachedCollision=null;}
            Passthrough.events.accept(complete);

			Passthrough.events.accept("{\"t\":\"syncdone\",\"scene\":"+scene+",\"id\":" + request + ",\"count\":" + found + "}");
		});
	}

    public static void resetBarricades(){barricadeDamage.clear();}
    private static final Map<BlockPos,Double> barricadeDamage=new java.util.HashMap<>();
    public static void breakBlock(com.google.gson.JsonArray values,double damage){
        if(values.size()!=3 || !Double.isFinite(damage) || damage<=0 || damage>80)return;
        int x=values.get(0).getAsInt(),y=values.get(1).getAsInt(),z=values.get(2).getAsInt();
        MinecraftServer s=server;if(s==null || Math.abs(x)>1023 || Math.abs(z)>1023)return;
        WorldBridge.serverWork(s,()->{BlockPos p=new BlockPos(x,y,z);ServerLevel level=s.overworld();
            if(!Passthrough.active || !MapBuilds.ready || !level.isLoaded(p))return;
            BlockState state=level.getBlockState(p);float hardness=state.getDestroySpeed(level,p);
            if(state.isAir() || state.is(Blocks.BARRIER) || hardness<0){barricadeDamage.remove(p);return;}
            if(barricadeDamage.size()>2048)barricadeDamage.clear();
            double hit=barricadeDamage.getOrDefault(p,0.0)+damage;
            if(hit>=Math.max(8,hardness*20)){barricadeDamage.remove(p);level.destroyBlock(p,true);}
            else barricadeDamage.put(p,hit);
        });
    }

	/** Elytra on and gliding (creative flight off), launched forward along the look; or back to creative flight. */
	public static void glide(final boolean start, final double speed) {
        ElytraBridge.request(start);
	}

	/** `source`: what exploded or was blown up, e.g. "tnt", "creeper", "fireball" (a ghast's). */
	public static void onExplosion(final Vec3 center, final float radius, final String source) {
		if (Passthrough.active) {
			Passthrough.events.accept(String.format(Locale.ROOT, "{\"t\":\"explosion\",\"pos\":[%.3f,%.3f,%.3f],\"r\":%.2f,\"src\":\"%s\"}",
				center.x, center.y, center.z, radius, source));
		}
	}
}
