package dev.rehan.passthrough;
/** Render a guard band without resizing either game or changing the user's FOV. */
public final class WorldProjection {
    private WorldProjection() {}
    public static float renderFov(float host){return (float)Math.toDegrees(2*Math.atan(Math.tan(Math.toRadians(host)*.5)*1.2));}
}
