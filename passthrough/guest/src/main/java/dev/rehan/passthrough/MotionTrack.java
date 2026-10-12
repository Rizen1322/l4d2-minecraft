package dev.rehan.passthrough;
/** Short render-only correction. Teleports snap; it never moves an authoritative actor. */
public final class MotionTrack {
    private double[] start,target;private long at;
    private final long duration;
    public MotionTrack(){this(50_000_000L);}
    public MotionTrack(long duration){this.duration=Math.clamp(duration,10_000_000L,150_000_000L);}
    public void observe(double x,double y,double z,long now){
        double[] next={x,y,z};if(target!=null && x==target[0] && y==target[1] && z==target[2])return;
        double[] current=sample(now);
        if(current==null || Math.pow(x-current[0],2)+Math.pow(y-current[1],2)+Math.pow(z-current[2],2)>64)current=next.clone();
        start=current;target=next;at=now;
    }
    public double[] sample(long now){
        if(target==null)return null;
        double t=Math.clamp((now-at)/(double)duration,0,1);
        return new double[]{start[0]+(target[0]-start[0])*t,start[1]+(target[1]-start[1])*t,start[2]+(target[2]-start[2])*t};
    }
}
