package dev.rehan.passthrough.client;

import dev.rehan.passthrough.TeamHudPolicy;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.resources.Identifier;

/** Actual GUI alpha composition; the Source picture never cuts holes in the shield. */
public final class TeamHud {
    private TeamHud() {}
    public static void extract(GuiGraphicsExtractor gui){
        Minecraft mc=Minecraft.getInstance();
        HostState.Pose pose=HostState.frame();
        HostState.Pose live=HostState.live();
        if(!TeamHudPolicy.visible(pose!=null && live!=null && pose.scene()==live.scene(),mc.gui.screen()!=null,mc.gui.overlay()!=null,gui.guiRenderState.isHudHidden))return;
        if(pose.teamHud().isEmpty())return;
        gui.nextStratum();
        gui.pose().pushMatrix();
        float scale=TeamHudPolicy.scale(gui.guiHeight());
        gui.pose().scale(scale,scale);
        try {
        for(int index=0;index<Math.min(3,pose.teamHud().size());index++){
            var member=pose.teamHud().get(index);
            int x=6,y=TeamHudPolicy.rowY(480,index);
            if(y<2)break;
            gui.fill(x,y,x+116,y+28,0x88000000);
            gui.fill(x+1,y+1,x+27,y+27,0xA0202528);
            Identifier portrait=Identifier.fromNamespaceAndPath("passthrough","textures/gui/teammates/"+member.character()+".png");
            if(mc.getResourceManager().getResource(portrait).isPresent())
                gui.blit(portrait,x+3,y+3,x+25,y+25,0,1,0,1);
            else {
                // Compact white survivor silhouette when a custom portrait is absent.
                gui.fill(x+10,y+5,x+18,y+13,0xFFE0E0E0);
                gui.fill(x+6,y+14,x+22,y+25,0xFFB0B8BC);
            }
            String name=mc.font.plainSubstrByWidth(member.name(),80);
            gui.text(mc.font,name,x+30,y+3,member.dead()?0xFFAAAAAA:0xFFFFFFFF,true);
            int barX=x+30,barY=y+16,width=80;
            gui.fill(barX,barY,barX+width,barY+7,0xDD151515);
            int health=member.healthPixels(width),temporary=member.temporaryPixels(width);
            int color=member.incapacitated()?0xFFE3962D:member.hp()/member.maximum()>0.4F?0xFF70BF37:0xFFCE4840;
            if(health>0)gui.fill(barX,barY,barX+health,barY+7,color);
            if(temporary>0)gui.fill(barX+health,barY,barX+health+temporary,barY+7,0xFFF0D56B);
            if(member.dead())gui.text(mc.font,"X",x+17,y+16,0xFFFF5555,true);
            else if(member.incapacitated()){
                gui.fill(x+18,y+15,x+21,y+25,0xFFFFB640);
                gui.fill(x+15,y+18,x+24,y+21,0xFFFFB640);
            }
        }
        } finally {gui.pose().popMatrix();}
    }
}
