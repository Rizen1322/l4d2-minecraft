package dev.rehan.passthrough;
public final class TeamHudPolicyTest {
    public static void main(String[] args){
        var member=new TeamHudPolicy.Member("Coach","coach",60,30,100,false,false);
        if(member.healthPixels(80)!=48 || member.temporaryPixels(80)!=24)throw new AssertionError("Separate health and pills bars");
        var capped=new TeamHudPolicy.Member("bad\nname","../../secret",90,50,100,false,false);
        if(capped.temporaryPixels(80)!=8 || !capped.character().equals("unknown") || capped.name().contains("\n"))throw new AssertionError("Unsafe or overflowing HUD values");
        var down=new TeamHudPolicy.Member("Ellis","ellis",150,0,300,true,false);
        if(down.healthPixels(80)!=40)throw new AssertionError("Incapacitated health uses own maximum");
        var dead=new TeamHudPolicy.Member("Nick","nick",90,20,100,false,true);
        if(dead.healthPixels(80)+dead.temporaryPixels(80)!=0)throw new AssertionError("Dead bars must be empty");
        if(!TeamHudPolicy.visible(true,false,false,false))throw new AssertionError("Live HUD missing");
        if(TeamHudPolicy.visible(false,false,false,false) || TeamHudPolicy.visible(true,true,false,false)
            || TeamHudPolicy.visible(true,false,true,false) || TeamHudPolicy.visible(true,false,false,true))throw new AssertionError("HUD during menu/loading/inventory");
        if(TeamHudPolicy.rowY(360,0)<=TeamHudPolicy.rowY(360,1))throw new AssertionError("Team must stack upward");
        for(int guiScale : new int[]{1,2,3,4,6}){
            int guiHeight=1440/guiScale;
            float physicalWidth=116*TeamHudPolicy.scale(guiHeight)*guiScale;
            if(Math.abs(physicalWidth-348)>0.01)throw new AssertionError("Card size changes with Minecraft GUI scale");
        }
        System.out.println("Teammate alpha HUD health/layout/visibility regression passed");
    }
}
