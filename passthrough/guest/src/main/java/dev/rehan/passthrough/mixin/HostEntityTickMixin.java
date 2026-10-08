package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.HostTerrain;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Unknown host terrain or host shutdown must not drop persistent mobs/items into the void. */
@Mixin(ServerLevel.class)
abstract class HostEntityTickMixin {
    @Inject(method="tickNonPassenger",at=@At("HEAD"),cancellable=true)
    private void passthrough$waitForHost(Entity entity,CallbackInfo ci){
        if(HostTerrain.shouldFreeze(entity))ci.cancel();
    }
}
