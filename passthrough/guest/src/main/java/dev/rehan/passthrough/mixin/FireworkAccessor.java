package dev.rehan.passthrough.mixin;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.projectile.FireworkRocketEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;
/** Verified mapped26.3 target; floor/crossbow fireworks have no attached player. */
@Mixin(FireworkRocketEntity.class)
public interface FireworkAccessor {
    @Accessor("attachedToEntity") LivingEntity l4d2mc$attachedToEntity();
}
