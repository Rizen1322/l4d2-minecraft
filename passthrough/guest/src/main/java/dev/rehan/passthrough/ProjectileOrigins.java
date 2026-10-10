package dev.rehan.passthrough;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

/** Keep the launch segment even when a bridge mailbox coalesces flight snapshots. Server thread only. */
public final class ProjectileOrigins {
    public record Point(double x, double y, double z) {}
    private final Map<Integer, Point> launches = new HashMap<>();
    public Point remember(int id, double x, double y, double z) {
        return launches.computeIfAbsent(id, ignored -> new Point(x, y, z));
    }
    public void retain(Set<Integer> alive) { launches.keySet().retainAll(alive); }
    public void clear() { launches.clear(); }
}
