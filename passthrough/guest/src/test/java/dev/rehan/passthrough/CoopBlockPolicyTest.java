package dev.rehan.passthrough;
import com.google.gson.JsonParser;
public final class CoopBlockPolicyTest {
    public static void main(String[] args) {
        var rows=CoopBlockPolicy.decode(JsonParser.parseString("[[1,64,-2,5],[1,64,-2,0]]").getAsJsonArray(),-64,320);
        if(rows.size()!=2 || rows.get(1).state()!=0)throw new AssertionError("AIR tombstone lost");
        for(String bad:new String[]{"[[1.5,64,0,1]]","[[1024,64,0,1]]","[[0,320,0,1]]","[[0,64,0,65536]]","[[0,64,0,-1]]","[[0,64,0,1,2]]"}) {
            try {CoopBlockPolicy.decode(JsonParser.parseString(bad).getAsJsonArray(),-64,320);throw new AssertionError(bad);}catch(IllegalArgumentException expected) {}
        }
        var oversized=new com.google.gson.JsonArray();for(int i=0;i<257;i++)oversized.add(JsonParser.parseString("[0,64,0,1]"));
        try {CoopBlockPolicy.decode(oversized,-64,320);throw new AssertionError("Unbounded network batch");}catch(IllegalArgumentException expected) {}
        String json=CoopBlockPolicy.encode(7,rows,true);
        if(!json.contains("\"bootstrap\":true") || !json.contains("[1,64,-2,0]"))throw new AssertionError(json);
        System.out.println("Coop block state batching and validation regressions passed");
    }
}
