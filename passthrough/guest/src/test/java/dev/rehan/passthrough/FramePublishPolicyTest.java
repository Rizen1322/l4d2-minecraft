package dev.rehan.passthrough;
public final class FramePublishPolicyTest {
    private static void check(boolean value, String label) { if (!value) throw new AssertionError(label); }
    public static void main(String[] args) {
        var gate = new FramePublishPolicy();
        check(gate.accept(2, 7, 7, 100, 200), "Normal completed frame");
        check(!gate.accept(1, 7, 7, 100, 200), "Older GPU callback must not rewind camera");
        check(!gate.accept(3, 7, 8, 100, 200), "Old map callback after transition");
        check(!gate.accept(3, 0, 0, 100, 200), "No active map");
        check(!gate.accept(3, 8, 8, 100, 600_000_101), "GPU stall must not revive old geometry");
        check(!gate.accept(3, 8, 8, 200, 100), "Invalid capture clock");
        check(gate.accept(3, 8, 8, 100, 200), "Rejected callback does not consume frame");
        check(!gate.accept(3, 8, 8, 100, 200), "Duplicate completion");
        System.out.println("Frame scene/order/freshness regression passed");
    }
}
