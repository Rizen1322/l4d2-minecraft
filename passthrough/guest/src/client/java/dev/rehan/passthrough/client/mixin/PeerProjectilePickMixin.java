package dev.rehan.passthrough.client.mixin;
import java.util.function.Predicate;
import dev.rehan.passthrough.client.PeerEntities;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.projectile.ProjectileUtil;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.ModifyVariable;
/** Filter before target selection, including projectile subclasses overriding isPickable. */
@Mixin(ProjectileUtil.class)
abstract class PeerProjectilePickMixin {
    @ModifyVariable(method={"getEntityHitResult","getManyEntityHitResult"},at=@At("HEAD"),argsOnly=true,ordinal=0)
    private static Predicate<Entity> passthrough$skipVisuals(Predicate<Entity> original){return entity->!PeerEntities.owns(entity) && original.test(entity);}
}
