package dev.rehan.passthrough.mixin;

import net.minecraft.world.entity.projectile.Projectile;
import net.minecraft.world.phys.HitResult;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Invoker;

/** Lets the host's trace break a thrown potion/snowball/egg where it hit Source geometry. */
@Mixin(Projectile.class)
public interface ProjectileInvoker {
	@Invoker("onHit")
	void l4d2mc$onHit(HitResult result);
}
