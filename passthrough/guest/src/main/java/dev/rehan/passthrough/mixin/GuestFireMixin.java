package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.GuestFire;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.LevelReader;
import net.minecraft.world.level.block.FireBlock;
import net.minecraft.world.level.block.state.BlockState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.Redirect;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** Treat a validated Source floor like nonflammable stone for vanilla fire aging/rain rules. */
@Mixin(FireBlock.class)
abstract class GuestFireMixin {
    @Inject(method="canSurvive",at=@At("HEAD"),cancellable=true)
    private void l4d2mc$floor(BlockState state,LevelReader level,BlockPos pos,CallbackInfoReturnable<Boolean> ci){
        if(GuestFire.support(level,pos))ci.setReturnValue(true);
    }
    @Redirect(method="tick",at=@At(value="INVOKE",target="Lnet/minecraft/server/level/ServerLevel;getBlockState(Lnet/minecraft/core/BlockPos;)Lnet/minecraft/world/level/block/state/BlockState;"))
    private BlockState l4d2mc$tickFloor(ServerLevel level,BlockPos at){return GuestFire.floor(level,at);}
    @Redirect(method="getStateForPlacement(Lnet/minecraft/world/level/BlockGetter;Lnet/minecraft/core/BlockPos;)Lnet/minecraft/world/level/block/state/BlockState;",
        at=@At(value="INVOKE",target="Lnet/minecraft/world/level/BlockGetter;getBlockState(Lnet/minecraft/core/BlockPos;)Lnet/minecraft/world/level/block/state/BlockState;"))
    private BlockState l4d2mc$visualFloor(BlockGetter level,BlockPos at){return GuestFire.floor(level,at);}
}
