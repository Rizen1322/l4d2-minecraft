package dev.rehan.passthrough;

import java.util.Collection;
import java.util.LinkedHashMap;

/** Server-thread index. An old unload must not erase a newer reused entity ID. */
public final class LoadedEntityIndex<T> {
    private final LinkedHashMap<Integer,T> values=new LinkedHashMap<>();
    public void load(int id,T entity){values.put(id,entity);}
    public void unload(int id,T entity){if(values.get(id)==entity)values.remove(id);}
    public Collection<T> values(){return values.values();}
    public void clear(){values.clear();}
}
