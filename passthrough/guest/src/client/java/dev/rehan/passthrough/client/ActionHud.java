package dev.rehan.passthrough.client;

import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import dev.rehan.passthrough.TeamHudPolicy;

/** Source's real use timer, drawn after the guest world rather than cutting Steve out. */
public final class ActionHud {
    private ActionHud(){}
    public static void extract(GuiGraphicsExtractor gui) {
        var mc=Minecraft.getInstance();float progress=HostState.actionProgress();
        if(progress<0 || !TeamHudPolicy.visible(HostState.frame()!=null,mc.gui.screen()!=null,mc.gui.overlay()!=null,gui.guiRenderState.isHudHidden))return;
        gui.nextStratum();gui.pose().pushMatrix();
        float scale=TeamHudPolicy.scale(gui.guiHeight());gui.pose().scale(scale,scale);
        try {
            int x=Math.round(gui.guiWidth()/scale/2)-150,y=250;
            String label=HostState.reviving()?"REVIVING TEAMMATE":"INTERACTING";
            gui.fill(x,y,x+300,y+39,0xDD101010);
            gui.text(mc.font,label,x+12,y+7,0xFFFFFFFF,true);
            gui.fill(x+12,y+22,x+288,y+30,0xFF292929);
            int width=Math.clamp(Math.round(276*progress),0,276);
            if(width>0)gui.fill(x+12,y+22,x+12+width,y+30,0xFFE8D35B);
        } finally {gui.pose().popMatrix();}
    }
}
