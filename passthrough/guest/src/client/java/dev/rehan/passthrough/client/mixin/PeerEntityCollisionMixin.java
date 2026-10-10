package dev.rehan.passthrough.client.mixin;
import dev.rehan.passthrough.client.PeerEntities;
import net.minecraft.world.entity.Entity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;
@Mixin(Entity.class)
abstract class PeerEntityCollisionMixin {
    @Inject(method="isPickable",at=@At("HEAD"),cancellable=true)
    private void passthrough$remoteTarget(CallbackInfoReturnable<Boolean> cir){if(PeerEntities.owns((Entity)(Object)this))cir.setReturnValue(PeerEntities.attackable((Entity)(Object)this));}
    @Inject(method="isPushable",at=@At("HEAD"),cancellable=true)
    private void passthrough$nonInteractive(CallbackInfoReturnable<Boolean> cir){if(PeerEntities.owns((Entity)(Object)this))cir.setReturnValue(false);}
    @Inject(method={"canCollideWith","canBeCollidedWith"},at=@At("HEAD"),cancellable=true)
    private void passthrough$nonColliding(Entity other,CallbackInfoReturnable<Boolean> cir){if(PeerEntities.owns((Entity)(Object)this) || PeerEntities.owns(other))cir.setReturnValue(false);}
}
