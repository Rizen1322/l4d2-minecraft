package dev.rehan.passthrough;
import com.google.gson.Gson;
import java.util.*;
/** Pure per-player ledger, encoded in the same player NBT as inventory and experience. */
public final class RewardLedger {
    private static final Gson JSON=new Gson();
    public Set<String> claimed=new LinkedHashSet<>();
    public Set<String> pickups=new LinkedHashSet<>();
    public Map<String,Boolean> totems=new LinkedHashMap<>();
    public Map<String,Integer> reserve=new LinkedHashMap<>();
    public String encode(){String value=JSON.toJson(this);if(value.length()>48000)throw new IllegalStateException("Reward ledger full");return value;}
    /** Validate the whole mixed-family budget before changing inventory, XP or receipts. */
    public boolean stage(java.util.function.Consumer<RewardLedger> mutation){
        final RewardLedger candidate;
        try{
            candidate=decode(encode());mutation.accept(candidate);decode(candidate.encode());
        }catch(RuntimeException full){return false;}
        claimed=candidate.claimed;pickups=candidate.pickups;totems=candidate.totems;reserve=candidate.reserve;
        return true;
    }
    public static RewardLedger decode(String value){
        if(value.length()>48000)throw new IllegalArgumentException("Reward ledger too large");
        RewardLedger d=JSON.fromJson(value,RewardLedger.class);
        if(d!=null && d.pickups==null)d.pickups=new LinkedHashSet<>();
        if(d!=null && d.totems==null)d.totems=new LinkedHashMap<>();
        if(d==null || d.claimed==null || d.reserve==null || d.claimed.size()>256 || d.reserve.size()>32 || d.pickups.size()>512)throw new IllegalArgumentException("Invalid reward ledger");
        for(String key:d.pickups)if(key==null || !key.matches("[A-Za-z0-9_]{1,128}"))throw new IllegalArgumentException("Invalid pickup receipt");
        for(String key:d.claimed)if(key==null || !key.matches("[A-Za-z0-9_]{1,128}"))throw new IllegalArgumentException("Invalid reward receipt");
        if(d.totems.size()>256)throw new IllegalArgumentException("Too many totem receipts");
        for(var e:d.totems.entrySet())if(e.getKey()==null || !e.getKey().matches("totem_[A-Za-z0-9_]{1,112}") || e.getValue()==null)throw new IllegalArgumentException("Invalid totem receipt");
        for(var r:d.reserve.entrySet())if(!r.getKey().matches("[a-z0-9_]{1,64}") || r.getValue()==null || r.getValue()<0 || r.getValue()>10000)throw new IllegalArgumentException("Invalid reserve");
        return d;
    }
}
