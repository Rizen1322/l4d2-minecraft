package dev.rehan.passthrough;
/** Snapshot-safe swing generation: retained counters outlive brief animations. */
public final class PeerActions {
    private boolean active;private float progress;private int sequence;
    public void reset(){active=false;progress=0;sequence=0;}
    public void observe(boolean swinging,float now){
        if(swinging && (!active || now<progress) && sequence<Integer.MAX_VALUE)sequence++;
        active=swinging;progress=now;
    }
    public int sequence(){return sequence;}
}
