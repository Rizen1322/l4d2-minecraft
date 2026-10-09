package dev.rehan.passthrough;
public final class AvatarPosePolicyTest {
    public static void main(String[] args) {
        for(float heading : new float[]{-180,-90,0,90,179}) {
            float back=AvatarPosePolicy.bodyYaw(false,heading,heading);
            float front=AvatarPosePolicy.bodyYaw(false,heading+180,heading);
            if(back!=front || front!=heading)throw new AssertionError("F5 orbit rotates survivor body");
        }
        if(AvatarPosePolicy.bodyYaw(true,45,0)!=45)throw new AssertionError("First-person body follows eye");
        if(!AvatarPosePolicy.prone("hunter"))throw new AssertionError("Hunter must pin survivor prone");
        for(String kind : new String[]{"none","jockey","smoker","charger","unknown"})
            if(AvatarPosePolicy.prone(kind))throw new AssertionError("Standing capture must remain upright");
        // Rotating a standing model +90 degrees around X makes every point on
        // its upright centerline horizontal, centered about the survivor root.
        double feet=-AvatarPosePolicy.PRONE_CENTER,head=1.5-AvatarPosePolicy.PRONE_CENTER;
        if(Math.abs(feet+head)>0.00001 || AvatarPosePolicy.PRONE_HEIGHT<=0.125)
            throw new AssertionError("Prone body must center and clear the floor");
        System.out.println("Survivor orbit/prone pose regression passed");
    }
}
