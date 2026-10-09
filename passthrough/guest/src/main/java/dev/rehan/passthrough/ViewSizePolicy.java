package dev.rehan.passthrough;
/** A repeated connect request must not restart an asynchronous native window resize. */
public final class ViewSizePolicy {
    private int width,height;
    private boolean pending;
    private long requestedAt;
    private static final long RETRY_NANOS=2_000_000_000L;
    public boolean accept(int w,int h,int actualWidth,int actualHeight){
        return accept(w,h,actualWidth,actualHeight,System.nanoTime());
    }
    public boolean accept(int w,int h,int actualWidth,int actualHeight,long now){
        if(w<320 || w>3840 || h<240 || h>2160)return false;
        if(actualWidth==w && actualHeight==h){
            width=w;height=h;pending=false;return false;
        }
        if(pending && width==w && height==h && now-requestedAt<RETRY_NANOS)return false;
        width=w;height=h;pending=true;requestedAt=now;
        return true;
    }
}
