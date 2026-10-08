package dev.rehan.passthrough;
public final class NavCursorTest {
    public static void main(String[] args){
        var path=new NavCursor(new double[][]{{0,5,0},{2,5,0},{2,0,0}});
        if(path.next(0,0,0)==null || path.next(0,0,0)[1]!=5)throw new AssertionError("Skipped other floor by XY alone");
        if(path.next(0,5,0)[0]!=2)throw new AssertionError("Did not advance reached waypoint");
        if(path.next(2,5,0)[1]!=0)throw new AssertionError("Lost descent waypoint");
        if(path.next(2,0,0)!=null)throw new AssertionError("Route should finish");
        System.out.println("Navigation waypoint regression passed");
    }
}
