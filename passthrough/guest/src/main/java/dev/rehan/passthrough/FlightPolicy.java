package dev.rehan.passthrough;
/** Pure authority snapshot; local movement speed/position never enter the Source flight solver. */
public final class FlightPolicy {
    private FlightPolicy() {}
    public static String snapshot(long scene,boolean flying,boolean elytra,int boost,boolean boosting) {
        if(scene<=0 || boost<0)return null;
        boolean on=flying && elytra;
        return "{\"t\":\"flight\",\"scene\":"+scene+",\"on\":"+on+",\"elytra\":"+elytra+",\"boost\":"+boost+",\"boosting\":"+(on && boosting && boost>0)+"}";
    }
    public static boolean consuming(boolean using,String animation){return using && ("EAT".equals(animation) || "DRINK".equals(animation));}
    public static String avatar(long scene,String main,String off,String chest) {
        if(scene<=0)return null;
        for(String id:new String[]{main,off,chest})if(id==null || !id.matches("[a-z0-9_.-]+:[a-z0-9_/.-]{1,96}"))return null;
        return "{\"t\":\"avatar\",\"scene\":"+scene+",\"main\":\""+main+"\",\"off\":\""+off+"\",\"chest\":\""+chest+"\"}";
    }
}
