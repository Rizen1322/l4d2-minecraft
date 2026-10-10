package dev.rehan.passthrough;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import com.google.gson.JsonObject;
/** Immutable bounded visual snapshot. Remote entity IDs are scoped by Source owner. */
public final class EntityRosterPolicy {
    public record Row(int id,String type,double x,double y,double z,float yaw,float pitch) {}
    public record Owner(int id,List<Row> rows) {}
    public record Snapshot(long scene,long at,List<Owner> owners) {
        public boolean live(long expected,long now){return scene==expected && now>=at && now-at<=1_000_000_000L;}
    }
    private EntityRosterPolicy() {}
    public static String encodeState(long scene,List<Row> rows) {
        if(scene<=0 || rows.size()>64)throw new IllegalArgumentException("Invalid owned entity snapshot");
        var text=new StringBuilder("{\"t\":\"peerentitystate\",\"scene\":").append(scene).append(",\"rows\":[");
        for(var row:rows) {
            if(!row.type().matches("[a-z0-9_.-]+:[a-z0-9_/.-]{1,96}"))throw new IllegalArgumentException("Unsafe entity type");
            if(text.charAt(text.length()-1)!='[')text.append(',');
            text.append('[').append(row.id()).append(",\"").append(row.type()).append("\",").append(row.x()).append(',').append(row.y()).append(',').append(row.z()).append(',').append(row.yaw()).append(',').append(row.pitch()).append(']');
        }
        return text.append("]}").toString();
    }
    public static Snapshot decode(JsonObject message,long expected,long now) {
        if(expected<=0 || !message.has("scene") || !message.get("scene").isJsonPrimitive()
            || !message.get("scene").getAsJsonPrimitive().isNumber() || !message.get("scene").getAsString().matches("[0-9]{1,19}")
            || message.get("scene").getAsLong()!=expected)throw new IllegalArgumentException("Stale entity scene");
        var owners=message.getAsJsonArray("owners");if(owners==null || owners.size()>3)throw new IllegalArgumentException("Entity owner limit");
        var result=new ArrayList<Owner>();var ownerIds=new HashSet<Integer>();
        for(var value:owners) {
            var owner=value.getAsJsonObject();int id=integer(owner.get("id"));
            if(id<1 || id>65535 || !ownerIds.add(id))throw new IllegalArgumentException("Invalid/duplicate entity owner");
            var rows=owner.getAsJsonArray("rows");if(rows==null || rows.size()>64)throw new IllegalArgumentException("Entity owner batch exceeds64");
            var accepted=new ArrayList<Row>();var ids=new HashSet<Integer>();
            for(var v:rows) {
                if(!v.isJsonArray() || v.getAsJsonArray().size()!=7)throw new IllegalArgumentException("Entity row shape");
                var row=v.getAsJsonArray();int entity=integer(row.get(0));
                if(entity<1 || !ids.add(entity) || !row.get(1).isJsonPrimitive() || !row.get(1).getAsJsonPrimitive().isString())throw new IllegalArgumentException("Invalid entity ID/type");
                String type=row.get(1).getAsString();if(!type.matches("[a-z0-9_.-]+:[a-z0-9_/.-]{1,96}"))throw new IllegalArgumentException("Unsafe entity registry ID");
                double[] p=new double[5];for(int i=0;i<5;i++){
                    if(!row.get(i+2).isJsonPrimitive() || !row.get(i+2).getAsJsonPrimitive().isNumber())throw new IllegalArgumentException("Non-numeric entity pose");
                    p[i]=row.get(i+2).getAsDouble();if(!Double.isFinite(p[i]) || Math.abs(p[i])>(i<3?1023:360))throw new IllegalArgumentException("Entity pose outside bounds");
                }
                accepted.add(new Row(entity,type,p[0],p[1],p[2],(float)p[3],(float)p[4]));
            }
            result.add(new Owner(id,List.copyOf(accepted)));
        }
        return new Snapshot(expected,now,List.copyOf(result));
    }
    private static int integer(com.google.gson.JsonElement value) {
        if(value==null || !value.isJsonPrimitive() || !value.getAsJsonPrimitive().isNumber())throw new IllegalArgumentException("Non-numeric entity ID");
        double n=value.getAsDouble();if(!Double.isFinite(n) || n!=Math.rint(n) || n<0 || n>Integer.MAX_VALUE)throw new IllegalArgumentException("Non-integer entity ID");return (int)n;
    }
}
