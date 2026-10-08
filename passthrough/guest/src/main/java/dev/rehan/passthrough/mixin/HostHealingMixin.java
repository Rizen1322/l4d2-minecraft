package dev.rehan.passthrough.mixin;
import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.MapBuilds;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
/** Instant healing and regeneration tick in Minecraft; the healed health belongs to Source. */
@Mixin(LivingEntity.class)
abstract class HostHealingMixin {
    @Inject(method="heal",at=@At("HEAD"),cancellable=true)
    private void l4d2mc$heal(float amount,CallbackInfo ci){
        if((Object)this instanceof ServerPlayer p && Passthrough.active && MapBuilds.ready
                && p.level().getServer().getWorldPath(net.minecraft.world.level.storage.LevelResource.ROOT).normalize().getFileName().toString().equals("l4d2mc-guest")) {
            if(Float.isFinite(amount) && amount>0)Passthrough.events.accept("{\"t\":\"heal\",\"h\":"+Math.min(100,amount*5)+"}");
            ci.cancel();
        }
    }
}
