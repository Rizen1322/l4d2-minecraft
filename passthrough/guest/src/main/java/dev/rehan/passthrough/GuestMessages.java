package dev.rehan.passthrough;
import java.util.Locale;
/** Pure JSON serializer, exercised without a running Minecraft server. */
public final class GuestMessages {
    private GuestMessages() {}
    public static String equipment(int armor,double toughness,boolean blocking){
        double safe=Double.isFinite(toughness)?Math.clamp(toughness,0,20):0;
        return String.format(Locale.ROOT,"{\"t\":\"equipment\",\"armor\":%d,\"toughness\":%.2f,\"blocking\":%b}",Math.clamp(armor,0,20),safe,blocking);
    }
}
