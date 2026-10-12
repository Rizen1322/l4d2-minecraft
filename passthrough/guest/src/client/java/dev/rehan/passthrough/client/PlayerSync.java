package dev.rehan.passthrough.client;

import net.minecraft.client.CameraType;
import net.minecraft.client.Minecraft;
import dev.rehan.passthrough.Passthrough;
import java.util.Locale;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.entity.player.Abilities;
import net.minecraft.world.phys.Vec3;

/** Keeps the Minecraft player on the host's player: it stands where they stand and looks where the host camera looks. */
public final class PlayerSync {
	private static final double TELEPORT_SQ = 64.0 * 64.0;
	/** How far the host's player moved over the last client tick (drives the walk animation). */
	private static float tickDistance;
	private static double lastX = Double.NaN, lastZ;
	/** Last host-driven position, kept while the host link is stale. */
	private static double holdX, holdY, holdZ;
	private static boolean holding;

	private PlayerSync() {
	}

	public static float tickDistance() {
		return tickDistance;
	}

    /** Apply the newest Source aim before a queued item/attack input is handled. */
    public static void syncAim() {
        var p=HostState.live();
        var player=Minecraft.getInstance().player;
        if(p==null || player==null)return;
        player.setYRot(p.lookYaw());
        player.setXRot(p.lookPitch());
    }

	/** Every frame, before the camera update: position, rotation, and first/third person to match the host. */
	public static void frame(final float partialTick) {
		HostState.Pose p = HostState.frame();
		Minecraft minecraft = Minecraft.getInstance();
		LocalPlayer player = minecraft.player;
		if (p == null || player == null) {
			return;
		}

		if (p.drive()) {
			// Minecraft flies the player (elytra): it only takes where to look, and tells the host where it is
			player.setYRot(p.lookYaw());
			player.setXRot(p.lookPitch());
			player.yRotO = p.lookYaw();
			player.xRotO = p.lookPitch();
			player.yHeadRot = player.yHeadRotO = p.lookYaw();
			if (minecraft.options.getCameraType() != CameraType.THIRD_PERSON_BACK) {
				minecraft.options.setCameraType(CameraType.THIRD_PERSON_BACK);
			}
			// airborne: with no collision onGround never updates, and the server cancels a grounded player's glide
			player.setOnGround(false);

			// where the player is drawn this frame, how fast that moves (the slope of the tick interpolation, per
			// second) and when (System.nanoTime is the host's QueryPerformanceCounter clock): the host carries it forward
			Vec3 at = player.getPosition(partialTick);
			double vx = (player.getX() - player.xo) * 20.0, vy = (player.getY() - player.yo) * 20.0, vz = (player.getZ() - player.zo) * 20.0;
			Passthrough.events.accept(String.format(Locale.ROOT, "{\"t\":\"mcpos\",\"pos\":[%.4f,%.4f,%.4f],\"vel\":[%.3f,%.3f,%.3f],\"tn\":%d,\"fly\":%b}",
				at.x, at.y, at.z, vx, vy, vz, System.nanoTime(), player.isFallFlying()));
			return;
		}

        player.setSharedFlagOnFire(HostState.burning() || dev.rehan.passthrough.SurvivalFeatures.burning());
        minecraft.options.keyShift.setDown(HostState.isCrouching());
        float headYaw=p.firstPerson()?p.yaw():p.lookYaw();
        // Physical throw/interaction pitch follows Source's aim in every F5
        // view. The camera and avatar renderer own their visual pose.
        float headPitch=p.firstPerson()?p.pitch():p.lookPitch();
		player.setYRot(headYaw);
		player.setXRot(headPitch);
		player.yRotO = headYaw;
		player.xRotO = headPitch;
        // Vanilla arm lag uses tick-smoothed bob angles. Source turns arrive
        // between ticks, so that lag can swing both hands across the screen.
        player.xBob = player.xBobO = headPitch;
        player.yBob = player.yBobO = headYaw;
		player.yHeadRot = player.yHeadRotO = headYaw;
		player.yBodyRot = player.yBodyRotO = dev.rehan.passthrough.AvatarPosePolicy.bodyYaw(p.firstPerson(),p.yaw(),p.lookYaw());
		// the model stands exactly where the host's player is this frame (not a tick behind, interpolating)
		double x = p.firstPerson() ? p.x() : p.px();
		double y = p.firstPerson() ? p.y() - player.getEyeHeight() : p.py();
		double z = p.firstPerson() ? p.z() : p.pz();
		player.setPos(x, y, z);
		player.xo = player.xOld = x;
		player.yo = player.yOld = y;
		player.zo = player.zOld = z;
		CameraType cameraType = p.firstPerson() ? CameraType.FIRST_PERSON : CameraType.THIRD_PERSON_BACK;
		if (minecraft.options.getCameraType() != cameraType) {
			minecraft.options.setCameraType(cameraType);
		}
	}

	/**
	 * Every client tick, at the start of the player's tick (the old position is already saved, so the model
	 * interpolates and walks): in first person the player's eyes are at the host camera, in third person
	 * their feet are at the host player's.
	 */
	public static void tick(final LocalPlayer player) {
		HostState.Pose p = HostState.live();
		if (p == null) {
			hold(player);
			return;
		}
		if (p.drive()) {
			holding = false;
			return;
		}

        // Ticks can precede another render frame: send current aim with the
        // movement packet rather than the last rendered angle.
        player.setYRot(p.lookYaw());
        player.setXRot(p.lookPitch());
		double x = p.firstPerson() ? p.x() : p.px();
		double y = p.firstPerson() ? p.y() - player.getEyeHeight() : p.py();
		double z = p.firstPerson() ? p.z() : p.pz();
		tickDistance = Double.isNaN(lastX) ? 0.0F : (float) Math.min(Math.hypot(x - lastX, z - lastZ), 1.0);
		lastX = x;
		lastZ = z;
		boolean teleport = player.distanceToSqr(x, y, z) > TELEPORT_SQ;
		player.setPos(x, y, z);
		if (teleport) {
			player.xo = player.xOld = x;
			player.yo = player.yOld = y;
			player.zo = player.zOld = z;
		}

		player.setDeltaMovement(Vec3.ZERO);
		holdX = x;
		holdY = y;
		holdZ = z;
		holding = true;
		boolean grounded=HostState.grounded();
        dev.rehan.passthrough.ElytraBridge.hostGrounded(grounded);
        player.setOnGround(grounded);
        boolean wings=net.minecraft.world.entity.LivingEntity.canGlideUsing(
            player.getItemBySlot(net.minecraft.world.entity.EquipmentSlot.CHEST),net.minecraft.world.entity.EquipmentSlot.CHEST);
        if(grounded || !wings)player.stopFallFlying();
		Abilities abilities = player.getAbilities();
		if (abilities.mayfly && abilities.flying==wings) {
			// Creative flight suppresses vanilla double-jump Elytra start. Source
            // still owns movement; disabling this bit cannot transfer authority.
            abilities.flying = !wings;
			player.onUpdateAbilities();
		}
	}

	/**
	 * The host link dropped (bridge restart, tunnel off). The guest world has no ground under
	 * the Source map, so vanilla gravity would drop Steve into the void and kill him repeatedly.
	 * Hover at the last host position until a fresh pose arrives.
	 */
	private static void hold(final LocalPlayer player) {
		// Only a real link loss. A hidden pose (cutscene, scene change, pinned camera) or
		// Elytra flight must never teleport Steve back or close his wings.
		if (!holding || player.isDeadOrDying() || player.isFallFlying() || !HostState.linkLost()) {
			return;
		}
		player.stopFallFlying();
		player.setDeltaMovement(Vec3.ZERO);
		player.setPos(holdX, holdY, holdZ);
		player.fallDistance = 0;
		Abilities abilities = player.getAbilities();
		if (abilities.mayfly && !abilities.flying) {
			abilities.flying = true;
			player.onUpdateAbilities();
		}
	}
}
