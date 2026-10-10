package dev.rehan.passthrough;
public final class PeerAttackPolicyTest {
    public static void main(String[] args) {
        var policy=new PeerAttackPolicy();
        if(!policy.accept(12,12,2,1,7,25))throw new AssertionError("Valid nearby hit rejected");
        if(policy.accept(12,12,2,1,7,25))throw new AssertionError("Reliable retry damaged mob twice");
        if(policy.accept(12,12,2,2,7,25.01))throw new AssertionError("Out of reach hit accepted");
        if(policy.accept(12,13,2,2,7,0))throw new AssertionError("Old scene hit accepted");
        if(policy.accept(12,12,2,2,Double.NaN,0) || policy.accept(12,12,2,2,-1,0))throw new AssertionError("Invalid damage accepted");
        if(!policy.accept(12,12,2,2,7,0))throw new AssertionError("Invalid request consumed valid sequence");
        if(!policy.accept(12,12,3,1,7,0))throw new AssertionError("Attackers shared replay state");
        if(!policy.accept(13,13,2,1,7,0))throw new AssertionError("New scene retained replay sequence");
        System.out.println("Peer combat scene, reach, damage and replay regressions passed");
    }
}
