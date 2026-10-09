package dev.rehan.passthrough;

/** Bounded teammate display values, independent of either game's renderer. */
public final class TeamHudPolicy {
    private TeamHudPolicy() {}
    public record Member(String name,String character,float hp,float temporary,float maximum,boolean incapacitated,boolean dead) {
        public Member {
            name=name==null?"Survivor":name.replaceAll("[\\p{Cntrl}§]","");
            if(name.length()>64)name=name.substring(0,64);
            if(name.isEmpty())name="Survivor";
            character=java.util.Set.of("coach","ellis","nick","rochelle","bill","zoey","francis","louis").contains(character==null?"":character)?character:"unknown";
            maximum=Float.isFinite(maximum) && maximum>0?Math.min(maximum,10000):100;
            hp=Float.isFinite(hp)?Math.clamp(hp,0,maximum):0;
            temporary=Float.isFinite(temporary)?Math.clamp(temporary,0,maximum-hp):0;
            if(dead){hp=0;temporary=0;}
        }
        public int healthPixels(int width){return Math.round(width*hp/maximum);}
        public int temporaryPixels(int width){return Math.min(width-healthPixels(width),Math.round(width*temporary/maximum));}
    }
    public static boolean visible(boolean live,boolean screen,boolean overlay,boolean hidden){return live && !screen && !overlay && !hidden;}
    /** A 480-high HUD canvas makes card size independent of Minecraft's GUI scale. */
    public static float scale(int guiHeight){return Math.max(1,guiHeight)/480.0F;}
    public static int rowY(int guiHeight,int index){return guiHeight-48-index*32;}
}
