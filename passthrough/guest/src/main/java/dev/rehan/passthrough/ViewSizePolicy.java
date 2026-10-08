package dev.rehan.passthrough;
/** A repeated connect request must not restart an asynchronous native window resize. */
public final class ViewSizePolicy {
    private int width,height;
    public boolean accept(int w,int h,int actualWidth,int actualHeight){
        if(w<320 || w>3840 || h<240 || h>2160)return false;
        if(width==w && height==h)return false;
        width=w;height=h;
        return actualWidth!=w || actualHeight!=h;
    }
}
