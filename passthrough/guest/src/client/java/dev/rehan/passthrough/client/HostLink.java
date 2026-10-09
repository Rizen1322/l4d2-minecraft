package dev.rehan.passthrough.client;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import dev.rehan.passthrough.MobWar;
import dev.rehan.passthrough.Nether;
import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.WorldBridge;
import dev.rehan.passthrough.HostTerrain;
import java.net.InetSocketAddress;
import java.util.Locale;
import net.minecraft.client.Minecraft;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;

/**
 * The host's connection: a WebSocket server on 127.0.0.1 (port 25601, or -Dpassthrough.port).
 *
 * <p>Host to Minecraft (JSON, Minecraft coordinates):
 * <ul>
 * <li>{"t":"cam","f":frame,"p":[x,y,z],"r":[yaw,pitch,roll],"fov":vertical degrees,"fp":first person,"pl":[feet x,y,z],"h":body yaw}</li>
 * <li>{"t":"ground","c":[x,z,yBottom,yTop, ...]}: solid columns (barriers)</li>
 * <li>{"t":"clear"}: remove the barriers placed so far</li>
 * <li>{"t":"cmd","c":"time set noon"}: a server command</li>
 * <li>{"t":"key","k":"use|attack|pick|inventory|drop|swap|escape","down":bool}</li>
 * <li>{"t":"slot","n":0-8}, {"t":"scroll","d":+-1}, {"t":"hud","hidden":bool}, {"t":"view","w":px,"h":px}</li>
 * </ul>
 * Minecraft to host: {"t":"hello",...} on connect, {"t":"explosion","pos":[x,y,z],"r":radius}.
 * Relayed unchanged to the other clients: {"t":"gta",...} (director commands for the host plugin), {"t":"gtastate",...}.
 */
public final class HostLink extends WebSocketServer {
	private static HostLink instance;
	private volatile WebSocket controller;
    private final Object controllerLock=new Object();
    private volatile long controllerGeneration;
    private final java.util.LinkedHashSet<Integer> delivered=new java.util.LinkedHashSet<>();

	private HostLink(final int port) {
		super(new InetSocketAddress("127.0.0.1", port));
		this.setReuseAddr(true);
		this.setDaemon(true);
	}

	static void launch() {
		int port = Integer.getInteger("passthrough.port", 25601);
		instance = new HostLink(port);
		instance.start();
		Passthrough.events = message -> {
            JsonObject event=JsonParser.parseString(message).getAsJsonObject();
            String type=event.get("t").getAsString();
            if(!java.util.Set.of("ui","mapready","pickupack","rewardack").contains(type) && !event.has("scene"))
                event.addProperty("scene",dev.rehan.passthrough.MapBuilds.scene());
            instance.broadcast(event.toString());
        };
	}

	@Override
	public void onStart() {
		Passthrough.LOG.info("host link listening on 127.0.0.1:{}", this.getPort());
	}

	@Override
	public void onOpen(final WebSocket conn, final ClientHandshake handshake) {
		Passthrough.LOG.info("host connected from {}", conn.getRemoteSocketAddress());
		conn.send(String.format(Locale.ROOT, "{\"t\":\"hello\",\"v\":1,\"shm\":\"%s\",\"pid\":%d}", FrameExporter.NAME.replace("\\", "\\\\"), ProcessHandle.current().pid()));
        Minecraft minecraft=Minecraft.getInstance();
        minecraft.execute(()->{if(conn.isOpen())try {
            conn.send("{\"t\":\"ui\",\"open\":"+(minecraft.player!=null && minecraft.gui.screen()!=null)+"}");
        } catch(org.java_websocket.exceptions.WebsocketNotConnectedException ignored) {}});
	}

	@Override
	public void onClose(final WebSocket conn, final int code, final String reason, final boolean remote) {
		Passthrough.LOG.info("host disconnected ({} {})", code, reason);
        final long generation;
        synchronized(controllerLock) {
            if(conn!=controller)return;
            controller=null;generation=++controllerGeneration;
        }
        Minecraft minecraft=Minecraft.getInstance();
        minecraft.execute(()->{if(controller==null && controllerGeneration==generation)ClientInput.releaseRelay(minecraft);});
	}

	@Override
	public void onMessage(final WebSocket conn, final String message) {
		try {
			JsonObject m = JsonParser.parseString(message).getAsJsonObject();
            if(!m.get("t").getAsString().equals("attach") && conn!=this.controller)return;
            String type=m.get("t").getAsString();
            if(SOURCE_TASKS.contains(type)) {
                queueSource(conn,m);return;
            }
            dispatch(conn,m);

		} catch (RuntimeException e) {
			Passthrough.LOG.warn("bad host message {}: {}", message.length() > 200 ? message.substring(0, 200) : message, e.toString());
		}
	}

    private static final java.util.Set<String> SOURCE_TASKS=java.util.Set.of(
        "hosthealth","peds","physground","projhit","equipmenthit","shieldcooldown","breakblock",
        "mobdmg","mobpos","navpath","supply","blocksync","totemrequest","totemapplied");
    private final dev.rehan.passthrough.ReplyTracker replies=new dev.rehan.passthrough.ReplyTracker();
    private void ackReply(int rid){Passthrough.events.accept("{\"t\":\"replyack\",\"id\":"+rid+"}");}
    private void queueSource(WebSocket conn,JsonObject m){
        if(!m.has("scene"))return;
        long scene=m.get("scene").getAsLong(),generation=controllerGeneration;
        int rid=m.has("rid")?m.get("rid").getAsInt():0;
        if(rid<0)return;
        var server=WorldBridge.server();if(server==null || !dev.rehan.passthrough.MapBuilds.ready || scene!=dev.rehan.passthrough.MapBuilds.scene())return;
        if(rid>0){
            var status=replies.begin(scene,generation,rid);
            if(status==dev.rehan.passthrough.ReplyTracker.Status.DONE){ackReply(rid);return;}
            if(status==dev.rehan.passthrough.ReplyTracker.Status.PENDING)return;
        }
        server.execute(()->{boolean success=false;try{
            if(conn!=controller || generation!=controllerGeneration || !dev.rehan.passthrough.MapBuilds.ready || scene!=dev.rehan.passthrough.MapBuilds.scene())return;
            dispatch(conn,m);
            success=true;
            if(rid>0)ackReply(rid);
        }catch(RuntimeException error){Passthrough.LOG.warn("Source reply not applied; retained for retry",error);}
        finally{if(rid>0)replies.finish(scene,generation,rid,success);}});
    }
    private void dispatch(WebSocket conn,JsonObject m){
			switch (m.get("t").getAsString()) {
                case "attach" -> {
                    final long generation;
                    synchronized(controllerLock) {
                        WebSocket previous=controller;
                        if(previous!=null && previous!=conn && previous.isOpen()) {
                            conn.close(1008,"another host already owns the guest");return;
                        }
                        controller=conn;generation=++controllerGeneration;replies.newOwner();
                    }
                    Minecraft minecraft=Minecraft.getInstance();
                    minecraft.execute(()->{if(controller==conn && controllerGeneration==generation)ClientInput.releaseRelay(minecraft);});
                }
				case "world" -> dev.rehan.passthrough.MapBuilds.select(m.get("map").getAsString(),m.has("epoch")?m.get("epoch").getAsLong():0,m.has("scene")?m.get("scene").getAsLong():0);
                case "cam" -> HostState.update(m);
				case "surface" -> HostState.surface(m);
                case "physground" -> HostTerrain.update(m.getAsJsonArray("p"));
                case "ground" -> {} // Retired: Source supports are virtual, never world blocks.
				case "clear" -> WorldBridge.clearSolid();
				case "cmd" -> WorldBridge.command(m.get("c").getAsString());
				case "gta", "gtastate", "gtainfo", "director" -> this.relay(conn, m.toString());
				case "blocksync" -> WorldBridge.sync(Math.clamp(m.has("r") ? m.get("r").getAsInt() : 16,1,32), m.has("id") ? m.get("id").getAsLong() : 0L);
				case "projhit" -> {
					JsonArray at = m.getAsJsonArray("pos");
					WorldBridge.projectileHit(m.get("id").getAsInt(), at.get(0).getAsDouble(), at.get(1).getAsDouble(), at.get(2).getAsDouble(),
						m.has("stick") && m.get("stick").getAsBoolean());
				}
				case "peds" -> {
					JsonArray list = m.getAsJsonArray("p");
					double[] flat = new double[list.size() * 5];
					for (int i = 0; i < list.size(); i++) {
						JsonArray e = list.get(i).getAsJsonArray();
						for (int k = 0; k < 5; k++) {
							flat[i * 5 + k] = k<e.size()?e.get(k).getAsDouble():0;
						}
					}

					MobWar.peds(flat);
				}
				case "navpath" -> dev.rehan.passthrough.HostNavigation.reply(m);
                case "mobpos" -> {
                    var p=m.getAsJsonArray("p");HostTerrain.recover(m.get("id").getAsInt(),p.get(0).getAsDouble(),p.get(1).getAsDouble(),p.get(2).getAsDouble());
                }
                case "chapterreward" -> dev.rehan.passthrough.CampaignRewards.claim(m.get("key").getAsString(),m.get("map").getAsString(),m.get("finale").getAsBoolean(),m.get("difficulty").getAsInt());
                case "hosthealth" -> dev.rehan.passthrough.SurvivalFeatures.hostHealth(m.getAsJsonArray("h"));
                case "equipmenthit" -> dev.rehan.passthrough.SurvivalFeatures.equipmentHit(m.get("d").getAsInt(),m.get("shield").getAsBoolean());
                case "shieldcooldown" -> dev.rehan.passthrough.SurvivalFeatures.shieldCooldown(m.get("ticks").getAsInt());
                case "pickup" -> dev.rehan.passthrough.SurvivalFeatures.pickup(m.get("item").getAsString(),m.get("key").getAsString());
                case "totemrequest" -> dev.rehan.passthrough.GuestTotems.consume(m.get("key").getAsString());
                case "totemapplied" -> dev.rehan.passthrough.GuestTotems.applied(m.get("key").getAsString());
                case "supply" -> {
                    JsonArray p=m.getAsJsonArray("pos");dev.rehan.passthrough.SurvivalFeatures.supply(p.get(0).getAsDouble(),p.get(1).getAsDouble(),p.get(2).getAsDouble(),m.get("kind").getAsInt());
                }
                case "breakblock" -> WorldBridge.breakBlock(m.getAsJsonArray("pos"),m.get("d").getAsDouble());
                case "mobdmg" -> MobWar.damage(m.get("id").getAsInt(), m.get("d").getAsDouble());
				case "spawnmobs" -> MobWar.spawn(m.get("k").getAsString(), m.has("n") ? m.get("n").getAsInt() : 5,
					m.has("rmin") ? m.get("rmin").getAsDouble() : 8.0, m.has("rmax") ? m.get("rmax").getAsDouble() : 16.0,
					m.has("arc") ? m.get("arc").getAsDouble() : 40.0, m.has("yaw") ? m.get("yaw").getAsDouble() : 0.0,
					m.has("at") ? new double[] {m.getAsJsonArray("at").get(0).getAsDouble(), m.getAsJsonArray("at").get(1).getAsDouble(),
						m.getAsJsonArray("at").get(2).getAsDouble()} : null);
				case "mobsclear" -> MobWar.clearMobs();
				case "portal" -> {
					JsonArray at = m.getAsJsonArray("at");
					Nether.buildPortal(at.get(0).getAsDouble(), at.get(1).getAsDouble(), at.get(2).getAsDouble(), m.get("yaw").getAsFloat());
				}
				case "netheroff" -> Nether.stop();
				case "nethersync" -> Nether.resync();
				case "glide" -> WorldBridge.glide(!m.has("on") || m.get("on").getAsBoolean(), m.has("speed") ? m.get("speed").getAsDouble() : 1.2);
				default -> {
					Minecraft minecraft = Minecraft.getInstance();
					minecraft.execute(() -> {if(controller==conn)ClientInput.handle(minecraft, m);});
				}
			}
    }

	/** Messages between the host plugin and a director script pass through Minecraft's link to every other client. */
	private void relay(final WebSocket from, final String message) {
		for (WebSocket c : this.getConnections()) {
			if (c != from && c.isOpen()) {
				c.send(message);
			}
		}
	}

	@Override
	public void onError(final WebSocket conn, final Exception e) {
		Passthrough.LOG.warn("host link error", e);
	}

	private static int[] ints(final JsonArray a) {
		int[] out = new int[a.size()];
		for (int i = 0; i < out.length; i++) {
			out[i] = a.get(i).getAsInt();
		}

		return out;
	}
}
