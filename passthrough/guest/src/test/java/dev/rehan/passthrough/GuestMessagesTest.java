package dev.rehan.passthrough;
import java.util.Locale;
/** Standalone JVM regression: no Minecraft window/server or test library needed. */
public final class GuestMessagesTest {
    private static void equal(String actual,String expected){if(!actual.equals(expected))throw new AssertionError(actual);}
    public static void main(String[] args){
        equal(GuestMessages.equipment(0,0,false),"{\"t\":\"equipment\",\"armor\":0,\"toughness\":0.00,\"blocking\":false}");
        equal(GuestMessages.equipment(20,8,true),"{\"t\":\"equipment\",\"armor\":20,\"toughness\":8.00,\"blocking\":true}");
        if(GuestMessages.health(50,100,false)!=10 || GuestMessages.health(1,100,false)!=.2f
                || GuestMessages.health(300,100,true)!=.01f || GuestMessages.health(120,100,false)!=20)throw new AssertionError("Source heart scaling");
        Locale.setDefault(Locale.GERMANY);
        equal(GuestMessages.equipment(30,2.5,true),"{\"t\":\"equipment\",\"armor\":20,\"toughness\":2.50,\"blocking\":true}");
        equal(GuestMessages.equipment(-1,Double.NaN,false),"{\"t\":\"equipment\",\"armor\":0,\"toughness\":0.00,\"blocking\":false}");
        System.out.println("Guest equipment serialization regression passed");
    }
}
