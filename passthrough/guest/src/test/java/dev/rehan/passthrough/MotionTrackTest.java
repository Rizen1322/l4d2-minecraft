package dev.rehan.passthrough;
public final class MotionTrackTest {
 public static void main(String[] args){
  MotionTrack motion=new MotionTrack();motion.observe(0,0,0,0);motion.observe(4,0,0,100_000_000);
  if(Math.abs(motion.sample(125_000_000)[0]-2)>.001)throw new AssertionError("Moving peer did not interpolate");
  motion.observe(4,0,0,125_000_000);if(Math.abs(motion.sample(150_000_000)[0]-4)>.001)throw new AssertionError("Repeated frame reset interpolation");
  motion.observe(30,0,0,200_000_000);if(motion.sample(200_000_000)[0]!=30)throw new AssertionError("Teleport smeared across map");
  double source=Math.tan(Math.toRadians(70)*.5),guest=Math.tan(Math.toRadians(WorldProjection.renderFov(70))*.5);
  if(Math.abs(guest/source-1.2)>.00001)throw new AssertionError("World guard band metadata differs from camera FOV");
  NavCursor cursor=new NavCursor(new double[][]{{0,0,0},{3,0,0},{6,0,0}});cursor.resume(2,0,0);
  if(cursor.next(2,0,0)[0]!=3)throw new AssertionError("Refreshed route walked back to its origin");
  cursor=new NavCursor(new double[][]{{0,5,0},{3,5,0}});cursor.resume(2,0,0);
  if(cursor.next(2,0,0)[0]!=0)throw new AssertionError("Resume skipped a waypoint on another floor");
  System.out.println("V2 peer motion, teleport, guard band and route resume regressions passed");
 }
}
