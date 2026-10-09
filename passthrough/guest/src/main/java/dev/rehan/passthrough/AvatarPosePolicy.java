package dev.rehan.passthrough;

/** Body direction belongs to the survivor, never to an orbiting third-person camera. */
public final class AvatarPosePolicy {
    private AvatarPosePolicy() {}
    public static float bodyYaw(boolean firstPerson, float cameraYaw, float survivorYaw) {
        return firstPerson ? cameraYaw : survivorYaw;
    }
    public static boolean prone(String pin) { return "hunter".equals(pin); }
    /** Lay the torso around Source's survivor root rather than tipping around the feet. */
    public static final float PRONE_HEIGHT = 0.23F;
    public static final float PRONE_CENTER = 0.75F;
}
