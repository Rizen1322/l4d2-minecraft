package dev.rehan.passthrough;
public final class ViewSizePolicyTest {
    public static void main(String[] args){
        var gate=new ViewSizePolicy();
        if(!gate.accept(2560,1440,1280,720))throw new AssertionError("First 2K request");
        if(gate.accept(2560,1440,1280,720))throw new AssertionError("Repeating pending native resize");
        if(gate.accept(2560,1440,2560,1440))throw new AssertionError("Repeated matching size");
        if(!gate.accept(2560,1440,1280,720))throw new AssertionError("Acknowledged resize followed by external size change must recover");
        if(gate.accept(100000,20,1280,720))throw new AssertionError("Invalid native dimensions");
        if(!gate.accept(1280,720,2560,1440))throw new AssertionError("Intentional different size");
        var retry=new ViewSizePolicy();
        if(!retry.accept(2560,1440,1280,720,0))throw new AssertionError("Initial timed request");
        for(long time:new long[]{1,500_000_000L,1_999_999_999L})
            if(retry.accept(2560,1440,1280,720,time))throw new AssertionError("Reconnect must not restart an in-flight resize");
        if(!retry.accept(2560,1440,1280,720,2_000_000_000L))throw new AssertionError("A failed resize must permit bounded recovery");
        if(retry.accept(2560,1440,1280,720,2_000_000_001L))throw new AssertionError("Failed resize retry must be throttled again");
        if(retry.accept(2560,1440,2560,1440,2_000_000_010L))throw new AssertionError("Observed matching size acknowledges request");
        if(!retry.accept(2560,1440,1920,1080,2_000_000_020L))throw new AssertionError("Later manual resize must not remain stuck forever");
        System.out.println("Reconnect resize regression passed");
    }
}
