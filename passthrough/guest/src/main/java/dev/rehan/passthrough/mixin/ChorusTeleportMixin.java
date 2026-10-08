package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.Passthrough;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.consume_effects.TeleportRandomlyConsumeEffect;
import net.minecraft.world.level.Level;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** Chorus fruit must search Source floors, since they are intentionally AIR in Minecraft. */
@Mixin(TeleportRandomlyConsumeEffect.class)
abstract class ChorusTeleportMixin {
    @Inject(method="apply",at=@At("HEAD"),cancellable=true)
    private void passthrough$chorus(Level level,ItemStack item,LivingEntity consumer,CallbackInfoReturnable<Boolean> ci) {
        if(Passthrough.active && consumer instanceof ServerPlayer) {
            Passthrough.events.accept("{\"t\":\"chorus\"}");
            ci.setReturnValue(true);
        }
    }
}
