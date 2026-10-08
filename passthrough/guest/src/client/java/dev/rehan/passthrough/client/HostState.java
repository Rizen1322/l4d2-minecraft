package dev.rehan.passthrough.client;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.rehan.passthrough.Passthrough;

/** The host's latest camera and player pose, already in Minecraft coordinates (the host converts). */
public final class HostState {
	/**
	 * @param hostFrame the host's frame number for this pose (echoed in the exported frame)
	 * @param x camera position
	 * @param yaw Minecraft yaw (0 = facing +Z), pitch (positive = down) and roll, in degrees
	 * @param fov vertical field of view, degrees
	 * @param firstPerson whether the host camera is first person (third person shows the player model)
	 * @param px the player's feet (third person)
	 * @param bodyYaw the player's body yaw (third person)
	 * @param drive Minecraft moves the player (elytra flight) and the host follows; lookYaw/lookPitch steer
	 * @param gun the player holds one of the host's guns (Steve aims it; his own item isn't drawn)
	 */
	public record Pose(
		long hostFrame, double x, double y, double z, float yaw, float pitch, float roll, float fov,
		boolean firstPerson, double px, double py, double pz, float bodyYaw, long receivedNanos,
		boolean drive, float lookYaw, float lookPitch, boolean gun
	) {
	}

    public record Surface(net.minecraft.world.phys.Vec3 pos, net.minecraft.core.BlockPos cell,
                          net.minecraft.core.Direction face, long received) {}
    private static volatile Surface surface;
    static void surface(final JsonObject m) {
        if (!m.has("hit") || m.get("hit").isJsonNull()) { surface=null; return; }
        JsonObject h=m.getAsJsonObject("hit");
        JsonArray p=h.getAsJsonArray("pos"), c=h.getAsJsonArray("cell");
        net.minecraft.core.Direction[] faces={net.minecraft.core.Direction.WEST,net.minecraft.core.Direction.EAST,
            net.minecraft.core.Direction.DOWN,net.minecraft.core.Direction.UP,net.minecraft.core.Direction.NORTH,net.minecraft.core.Direction.SOUTH};
        surface=new Surface(new net.minecraft.world.phys.Vec3(p.get(0).getAsDouble(),p.get(1).getAsDouble(),p.get(2).getAsDouble()),
            new net.minecraft.core.BlockPos(c.get(0).getAsInt(),c.get(1).getAsInt(),c.get(2).getAsInt()),faces[h.get("face").getAsInt()],System.nanoTime());
    }
    public static Surface surface() {
        Surface s=surface;
        return s!=null && System.nanoTime()-s.received()<250_000_000L ? s : null;
    }

	private static final long TIMEOUT_NANOS = 2_000_000_000L;
	private static volatile Pose latest;
    private static volatile boolean usable,crouching;
    public static boolean isCrouching(){return live()!=null && crouching;}
    public static boolean canUse(){return live()!=null && usable;}
	/** The pose this frame renders with, taken once per frame so every hook agrees. Render thread only. */
	private static Pose frame;

    private static volatile boolean visible=true,nativeUse;
    static boolean nativeUse(){return nativeUse;}
	private HostState() {
	}

	/** {"t":"cam","f":frame,"p":[x,y,z],"r":[yaw,pitch,roll],"fov":deg,"fp":bool,"pl":[x,y,z],"h":bodyYaw} */
	static void update(final JsonObject m) {
        nativeUse=m.has("nativeuse") && m.get("nativeuse").getAsBoolean();
        visible=!m.has("visible") || m.get("visible").getAsBoolean();
		usable=m.has("usable") && m.get("usable").getAsBoolean();
        crouching=m.has("sneak") && m.get("sneak").getAsBoolean();
		JsonArray p = m.getAsJsonArray("p");
		JsonArray r = m.getAsJsonArray("r");
		JsonArray pl = m.has("pl") ? m.getAsJsonArray("pl") : p;
		float yaw = r.get(0).getAsFloat();
		latest = new Pose(
			m.has("f") ? m.get("f").getAsLong() : 0L,
			p.get(0).getAsDouble(), p.get(1).getAsDouble(), p.get(2).getAsDouble(),
			yaw, r.get(1).getAsFloat(), r.size() > 2 ? r.get(2).getAsFloat() : 0.0F,
			m.has("fov") ? m.get("fov").getAsFloat() : 70.0F,
			!m.has("fp") || m.get("fp").getAsBoolean(),
			pl.get(0).getAsDouble(), pl.get(1).getAsDouble(), pl.get(2).getAsDouble(),
			m.has("h") ? m.get("h").getAsFloat() : yaw,
			System.nanoTime(),
			m.has("drive") && m.get("drive").getAsBoolean(),
			m.has("look") ? m.getAsJsonArray("look").get(0).getAsFloat() : yaw,
			m.has("look") ? m.getAsJsonArray("look").get(1).getAsFloat() : r.get(1).getAsFloat(),
			m.has("gun") && m.get("gun").getAsBoolean()
		);
	}

	/** The latest pose if the host is still sending, else null. */
	static Pose live() {
		Pose p = latest;
		return visible && p != null && System.nanoTime() - p.receivedNanos() < TIMEOUT_NANOS ? p : null;
	}

	/** The pose for the frame being rendered, or null when no host is attached. */
	public static Pose frame() {
		return frame;
	}

	public static void beginFrame() {
		frame = live();
		Passthrough.active = frame != null;
	}
}
