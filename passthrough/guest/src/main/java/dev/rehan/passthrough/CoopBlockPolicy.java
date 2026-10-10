package dev.rehan.passthrough;
import java.util.ArrayList;
import java.util.List;
import com.google.gson.JsonArray;
/** Wire batches contain registry state IDs, including AIR tombstones, never NBT or executable data. */
public final class CoopBlockPolicy {
    public record Row(int x,int y,int z,int state) {}
    private CoopBlockPolicy() {}
    public static List<Row> decode(JsonArray values,int minY,int maxY) {
        if(values==null || values.size()>256)throw new IllegalArgumentException("Coop block batch exceeds256");
        var result=new ArrayList<Row>(values.size());
        for(var value:values) {
            if(!value.isJsonArray() || value.getAsJsonArray().size()!=4)throw new IllegalArgumentException("Invalid coop block row");
            var row=value.getAsJsonArray();int[] v=new int[4];
            for(int i=0;i<4;i++) {
                if(!row.get(i).isJsonPrimitive() || !row.get(i).getAsJsonPrimitive().isNumber())throw new IllegalArgumentException("Non-numeric coop block row");
                double n=row.get(i).getAsDouble();
                if(!Double.isFinite(n) || n!=Math.rint(n) || n<Integer.MIN_VALUE || n>Integer.MAX_VALUE)throw new IllegalArgumentException("Non-integer coop block row");
                v[i]=(int)n;
            }
            if(v[0]<-1023 || v[0]>1023 || v[2]<-1023 || v[2]>1023 || v[1]<minY || v[1]>=maxY || v[3]<0 || v[3]>65535)throw new IllegalArgumentException("Coop block row outside bounds");
            result.add(new Row(v[0],v[1],v[2],v[3]));
        }
        return result;
    }
    public static String encode(long scene,List<Row> rows,boolean bootstrap) {
        if(scene<=0 || rows.size()>256)throw new IllegalArgumentException("Invalid coop block batch");
        var text=new StringBuilder("{\"t\":\"peerblocks\",\"scene\":").append(scene).append(",\"bootstrap\":").append(bootstrap).append(",\"rows\":[");
        for(var row:rows){if(text.charAt(text.length()-1)!='[')text.append(',');text.append('[').append(row.x()).append(',').append(row.y()).append(',').append(row.z()).append(',').append(row.state()).append(']');}
        return text.append("]}").toString();
    }
}
