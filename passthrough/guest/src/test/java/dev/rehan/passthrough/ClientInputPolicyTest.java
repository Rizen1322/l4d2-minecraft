package dev.rehan.passthrough;
public final class ClientInputPolicyTest {
    public static void main(String[] args) {
        for(String action:new String[]{"attack","use","pick","drop","swap","sprint","sneak"}) {
            if(ClientInputPolicy.acceptKey(action,true,true))throw new AssertionError("Queued world press behind inventory: "+action);
            if(!ClientInputPolicy.acceptKey(action,false,true))throw new AssertionError("GUI must not leave a held world key: "+action);
            if(!ClientInputPolicy.acceptKey(action,true,false))throw new AssertionError("Normal gameplay input rejected: "+action);
        }
        if(!ClientInputPolicy.acceptKey("inventory",true,true) || !ClientInputPolicy.acceptKey("escape",true,true))
            throw new AssertionError("E/Escape must remain able to close inventory");
        System.out.println("Queued GUI/world key press and release regression passed");
    }
}
