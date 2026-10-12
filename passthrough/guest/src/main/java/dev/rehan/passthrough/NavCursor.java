package dev.rehan.passthrough;
/** Waypoints advance only when both horizontal position AND floor height match. */
public final class NavCursor {
    private final double[][] points;
    private int index;
    public NavCursor(double[][] points){this.points=points;}
    public void resume(double x,double y,double z){
        double nearest=1.0;int next=0;
        for(int i=0;i+1<points.length;i++) {
            double[] a=points[i],b=points[i+1];double dx=b[0]-a[0],dz=b[2]-a[2],length=dx*dx+dz*dz;
            if(length<1e-8)continue;
            double t=Math.clamp(((x-a[0])*dx+(z-a[2])*dz)/length,0,1);
            if(Math.abs(y-(a[1]+t*(b[1]-a[1])))>.75)continue;
            double distance=Math.hypot(x-a[0]-t*dx,z-a[2]-t*dz);
            if(distance<nearest){nearest=distance;next=i+1;}
        }
        index=next;
    }
    public double[] next(double x,double y,double z){
        while(index<points.length) {
            double[] p=points[index];
            if(Math.hypot(x-p[0],z-p[2])>.35 || Math.abs(y-p[1])>.5)return p;
            index++;
        }
        return null;
    }
}
