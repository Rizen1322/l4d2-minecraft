package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.Passthrough;
import net.minecraft.core.component.DataComponents;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Heal Source only after the server completed genuine Minecraft food consumption. */
@Mixin(LivingEntity.class)
abstract class FoodHealMixin {
    @Unique private int passthrough$meal;
    @Unique private boolean passthrough$golden;
    @Inject(method="completeUsingItem",at=@At(value="INVOKE",target="Lnet/minecraft/world/item/ItemStack;finishUsingItem(Lnet/minecraft/world/level/Level;Lnet/minecraft/world/entity/LivingEntity;)Lnet/minecraft/world/item/ItemStack;"))
    private void passthrough$beforeMeal(CallbackInfo ci) {
        LivingEntity self=(LivingEntity)(Object)this;
        passthrough$meal=0;passthrough$golden=false;
        if(!Passthrough.active || !(self instanceof ServerPlayer))return;
        passthrough$golden=self.getUseItem().is(net.minecraft.world.item.Items.GOLDEN_APPLE) || self.getUseItem().is(net.minecraft.world.item.Items.ENCHANTED_GOLDEN_APPLE);
        var food=self.getUseItem().get(DataComponents.FOOD);
        if(food!=null)passthrough$meal=Math.clamp(food.nutrition()*4,0,100);
    }
    @Inject(method="completeUsingItem",at=@At(value="INVOKE",target="Lnet/minecraft/world/item/ItemStack;finishUsingItem(Lnet/minecraft/world/level/Level;Lnet/minecraft/world/entity/LivingEntity;)Lnet/minecraft/world/item/ItemStack;",shift=At.Shift.AFTER))
    private void passthrough$afterMeal(CallbackInfo ci) {
        if(passthrough$meal>0)Passthrough.events.accept("{\"t\":\"meal\",\"h\":"+passthrough$meal+",\"golden\":"+passthrough$golden+"}");
        passthrough$meal=0;
    }
}
