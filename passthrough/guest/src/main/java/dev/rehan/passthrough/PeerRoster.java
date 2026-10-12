package dev.rehan.passthrough;
import java.util.List;
import java.util.UUID;
import java.nio.charset.StandardCharsets;
/** Immutable, scene-scoped render data. It never creates a server entity. */
public record PeerRoster(long scene,long received,List<Member> players) {
    public PeerRoster {players=List.copyOf(players.subList(0,Math.min(4,players.size())));}
    public record Member(int id,double x,double y,double z,float yaw,float pitch,float hp,boolean incap,boolean dead,String pin,String main,String off,boolean flying,boolean crouching,int swing,String swingHand,boolean using,String useHand,boolean burning) {
        public Member(int id,double x,double y,double z,float yaw,float pitch,float hp,boolean incap,boolean dead,String pin,String main,String off,boolean flying){this(id,x,y,z,yaw,pitch,hp,incap,dead,pin,main,off,flying,false,-1,"main",false,"main",false);}
        public Member(int id,double x,double y,double z,float yaw,float pitch,float hp,boolean incap,boolean dead,String pin,String main,String off,boolean flying,boolean crouching){this(id,x,y,z,yaw,pitch,hp,incap,dead,pin,main,off,flying,crouching,-1,"main",false,"main",false);}
        public Member {
            if(id<=0 || id>1_000_000 || !Double.isFinite(x+y+z) || Math.abs(x)>1024 || Math.abs(y)>1024 || Math.abs(z)>1024 || !Float.isFinite(yaw+pitch+hp))throw new IllegalArgumentException("Invalid peer pose");
            if(swing< -1)throw new IllegalArgumentException("Invalid swing sequence");swingHand="off".equals(swingHand)?"off":"main";useHand="off".equals(useHand)?"off":"main";
            pin=pin==null?"none":pin;
            main=item(main);off=item(off);pitch=Math.clamp(pitch,-90,90);
        }
        private static String item(String id){return id!=null && id.matches("minecraft:[a-z0-9_]{1,64}")?id:"minecraft:air";}
        public UUID uuid(long scene){return UUID.nameUUIDFromBytes(("l4d2mc-peer:"+scene+":"+id).getBytes(StandardCharsets.UTF_8));}
        public int entityId(){return -1_000_000-id;}
    }
    public boolean live(long currentScene,long now){return scene!=0 && scene==currentScene && now>=received && now-received<1_000_000_000L;}
}
