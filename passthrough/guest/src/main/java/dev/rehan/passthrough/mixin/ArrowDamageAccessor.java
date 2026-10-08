package dev.rehan.passthrough.mixin;
import net.minecraft.world.entity.projectile.arrow.AbstractArrow;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;
/** Verified mapped Minecraft 26.3 field; includes bow Power enchantment. */
@Mixin(AbstractArrow.class)
public interface ArrowDamageAccessor {
    @Accessor("baseDamage") double l4d2mc$baseDamage();
}
