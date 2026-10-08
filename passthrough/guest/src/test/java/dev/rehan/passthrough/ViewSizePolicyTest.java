package dev.rehan.passthrough;
public final class ViewSizePolicyTest {
    public static void main(String[] args){
        var gate=new ViewSizePolicy();
        if(!gate.accept(2560,1440,1280,720))throw new AssertionError("First 2K request");
        if(gate.accept(2560,1440,1280,720))throw new AssertionError("Repeating pending native resize");
        if(gate.accept(2560,1440,2560,1440))throw new AssertionError("Repeated matching size");
        if(gate.accept(100000,20,1280,720))throw new AssertionError("Invalid native dimensions");
        if(!gate.accept(1280,720,2560,1440))throw new AssertionError("Intentional different size");
        System.out.println("Reconnect resize regression passed");
    }
}
