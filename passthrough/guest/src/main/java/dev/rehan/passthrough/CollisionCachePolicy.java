package dev.rehan.passthrough;

/** Bounded reuse of a COMPLETE snapshot; every block edit invalidates it. */
public final class CollisionCachePolicy {
    private Object world;private long scene,revision,at;private String bounds;
    public void store(Object world,long scene,long revision,String bounds,long now){
        this.world=world;this.scene=scene;this.revision=revision;this.bounds=bounds;this.at=now;
    }
    public boolean reusable(Object world,long scene,long revision,String bounds,long now){
        return this.world==world && this.bounds!=null && this.scene==scene && this.revision==revision
            && this.bounds.equals(bounds) && now>=at && now-at<1_000_000_000L;
    }
    public void clear(){world=null;bounds=null;}
}
