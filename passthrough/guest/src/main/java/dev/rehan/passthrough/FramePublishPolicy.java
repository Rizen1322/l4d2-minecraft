package dev.rehan.passthrough;

/** Reject readbacks belonging to another scene, an older frame, or a stalled GPU. */
public final class FramePublishPolicy {
    private long latest;
    public boolean accept(long frame, long capturedScene, long liveScene, long capturedNanos, long now) {
        if (capturedScene == 0 || capturedScene != liveScene || frame <= latest
            || now < capturedNanos || now - capturedNanos > 500_000_000L) return false;
        latest = frame;
        return true;
    }
}
