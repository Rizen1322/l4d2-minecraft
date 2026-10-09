package dev.rehan.passthrough;

/** A relayed world press can wait behind opening a GUI; releases must still clear held keys. */
public final class ClientInputPolicy {
    private ClientInputPolicy() {}
    public static boolean acceptKey(String action,boolean down,boolean screenOpen) {
        return !down || !screenOpen || "inventory".equals(action) || "escape".equals(action)
            || "chat".equals(action) || "command".equals(action);
    }
}
