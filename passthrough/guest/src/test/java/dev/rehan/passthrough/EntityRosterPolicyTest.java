package dev.rehan.passthrough;
import com.google.gson.JsonParser;
public final class EntityRosterPolicyTest {
    private static void reject(String owners){try{EntityRosterPolicy.decode(JsonParser.parseString("{\"scene\":7,\"owners\":"+owners+"}").getAsJsonObject(),7,10);throw new AssertionError(owners);}catch(IllegalArgumentException expected){}}
    public static void main(String[] args) {
        var roster=EntityRosterPolicy.decode(JsonParser.parseString("{\"scene\":7,\"owners\":[{\"id\":2,\"rows\":[[9,\"minecraft:iron_golem\",1,2,-3,90,0]]}]}").getAsJsonObject(),7,10);
        if(roster.owners().size()!=1 || !roster.live(7,999_999_999L) || roster.live(8,10) || roster.live(7,1_000_000_011L))throw new AssertionError("Scene or lifetime");
        String exported=EntityRosterPolicy.encodeState(7,roster.owners().getFirst().rows());
        if(!exported.contains("\"t\":\"peerentitystate\"") || !exported.contains("minecraft:iron_golem"))throw new AssertionError(exported);
        reject("[{\"id\":2,\"rows\":[[9,\"minecraft:iron_golem\",1024,2,3,0,0]]}]");
        reject("[{\"id\":2,\"rows\":[[9,\"evil\\\"type\",1,2,3,0,0]]}]");
        reject("[{\"id\":2,\"rows\":[[9.5,\"minecraft:tnt\",1,2,3,0,0]]}]");
        reject("[{\"id\":2,\"rows\":[[9,\"minecraft:tnt\",\"1\",2,3,0,0]]}]");
        try {EntityRosterPolicy.decode(JsonParser.parseString("{\"scene\":7.5,\"owners\":[]}").getAsJsonObject(),7,10);throw new AssertionError("Fractional scene");}catch(IllegalArgumentException expected){}
        reject("[{\"id\":2,\"rows\":[]},{\"id\":2,\"rows\":[]}]");
        reject("[{\"id\":2,\"rows\":[[9,\"minecraft:tnt\",1,2,3,0,0],[9,\"minecraft:tnt\",1,2,3,0,0]]}]");
        var many=new com.google.gson.JsonArray();for(int i=0;i<65;i++)many.add(JsonParser.parseString("["+(i+1)+",\"minecraft:tnt\",1,2,3,0,0]"));
        reject("[{\"id\":2,\"rows\":"+many+"}]");
        System.out.println("Peer entity roster scene, bounds and expiry regressions passed");
    }
}
