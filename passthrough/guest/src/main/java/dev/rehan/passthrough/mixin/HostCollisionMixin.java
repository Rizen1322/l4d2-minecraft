package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.HostTerrain;
import java.util.ArrayList;
import java.util.List;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.shapes.VoxelShape;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(Entity.class)
abstract class HostCollisionMixin {
    @Inject(method="collectCollidersIgnoringWorldBorder(Lnet/minecraft/world/entity/Entity;Lnet/minecraft/world/level/Level;Ljava/util/List;Lnet/minecraft/world/phys/AABB;)Ljava/util/List;",at=@At("RETURN"),cancellable=true)
    private static void passthrough$hostPlanes(Entity entity,Level level,List<VoxelShape> other,AABB box,CallbackInfoReturnable<List<VoxelShape>> cir){
        var host=HostTerrain.shapes(entity,box);
        if(!host.isEmpty()){var all=new ArrayList<>(cir.getReturnValue());all.addAll(host);cir.setReturnValue(all);}
    }
}
