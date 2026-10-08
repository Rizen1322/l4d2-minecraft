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
		Passthrough.events = message -> instance.broadcast(message);
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
		if (conn == this.controller) {
			this.controller = null;
			Minecraft minecraft = Minecraft.getInstance();
			minecraft.execute(() -> ClientInput.releaseRelay(minecraft));
		}
	}

	@Override
	public void onMessage(final WebSocket conn, final String message) {
		try {
			JsonObject m = JsonParser.parseString(message).getAsJsonObject();
            if(m.has("rid"))synchronized(delivered) {
                int rid=m.get("rid").getAsInt();if(!delivered.add(rid))return;
                if(delivered.size()>256)delivered.remove(delivered.iterator().next());
            }
			switch (m.get("t").getAsString()) {
				case "attach" -> {
					WebSocket previous = this.controller;
					this.controller = conn;
					if (previous != null && previous != conn) previous.close(1000,"host replaced");
					Minecraft minecraft = Minecraft.getInstance();
					minecraft.execute(() -> ClientInput.releaseRelay(minecraft));
				}
				case "world" -> dev.rehan.passthrough.MapBuilds.select(m.get("map").getAsString(),m.has("epoch")?m.get("epoch").getAsLong():0);
                case "cam" -> HostState.update(m);
				case "surface" -> HostState.surface(m);
                case "physground" -> HostTerrain.update(m.getAsJsonArray("p"));
                case "ground" -> {} // Retired: Source supports are virtual, never world blocks.
				case "clear" -> WorldBridge.clearSolid();
				case "cmd" -> WorldBridge.command(m.get("c").getAsString());
				case "gta", "gtastate", "gtainfo", "director" -> this.relay(conn, message);
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
                case "hosthealth" -> dev.rehan.passthrough.SurvivalFeatures.hostHealth(m.getAsJsonArray("h"));
                case "equipmenthit" -> dev.rehan.passthrough.SurvivalFeatures.equipmentHit(m.get("d").getAsInt(),m.get("shield").getAsBoolean());
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
					minecraft.execute(() -> ClientInput.handle(minecraft, m));
				}
			}
		} catch (RuntimeException e) {
			Passthrough.LOG.warn("bad host message {}: {}", message.length() > 200 ? message.substring(0, 200) : message, e.toString());
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
