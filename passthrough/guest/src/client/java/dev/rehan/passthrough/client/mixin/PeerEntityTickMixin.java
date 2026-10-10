package dev.rehan.passthrough.client.mixin;
import dev.rehan.passthrough.client.PeerEntities;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.world.entity.Entity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
@Mixin(ClientLevel.class)
abstract class PeerEntityTickMixin {
    @Inject(method="tickNonPassenger",at=@At("HEAD"),cancellable=true)
    private void passthrough$visualOnly(Entity entity,CallbackInfo ci){if(PeerEntities.owns(entity)){PeerEntities.tick(entity);ci.cancel();}}
}
