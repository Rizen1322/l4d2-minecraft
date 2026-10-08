package dev.rehan.passthrough;
/** Waypoints advance only when both horizontal position AND floor height match. */
public final class NavCursor {
    private final double[][] points;
    private int index;
    public NavCursor(double[][] points){this.points=points;}
    public double[] next(double x,double y,double z){
        while(index<points.length) {
            double[] p=points[index];
            if(Math.hypot(x-p[0],z-p[2])>.35 || Math.abs(y-p[1])>.5)return p;
            index++;
        }
        return null;
    }
}
