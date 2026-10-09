package dev.rehan.passthrough.client.mixin;

import dev.rehan.passthrough.client.HostState;
import net.minecraft.client.Minecraft;
import net.minecraft.client.model.HumanoidModel;
import net.minecraft.client.renderer.entity.player.AvatarRenderer;
import net.minecraft.client.renderer.entity.state.AvatarRenderState;
import net.minecraft.world.entity.Avatar;
import net.minecraft.world.item.ItemStack;
import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.math.Axis;
import dev.rehan.passthrough.AvatarPosePolicy;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Holding one of the host's guns (drawn by the host): Steve aims with both arms forward, and holds nothing of his own. */
@Mixin(AvatarRenderer.class)
abstract class AvatarRendererMixin {
	@Inject(method = "extractRenderState(Lnet/minecraft/world/entity/Avatar;Lnet/minecraft/client/renderer/entity/state/AvatarRenderState;F)V", at = @At("TAIL"))
	private void passthrough$gunPose(final Avatar entity, final AvatarRenderState state, final float partialTick, final CallbackInfo ci) {
		HostState.Pose p = HostState.frame();
		if (p == null || entity != Minecraft.getInstance().player) {
			return;
		}

        // Vanilla extraction can clamp the body toward its head or retain a
        // tick's previous orientation. An orbit camera must not turn Steve.
        state.bodyRot=AvatarPosePolicy.bodyYaw(p.firstPerson(),p.yaw(),p.lookYaw());
        state.yRot=0;state.xRot=p.firstPerson()?p.pitch():p.lookPitch();
        if(AvatarPosePolicy.prone(p.pin())) {
            state.walkAnimationPos=0;state.walkAnimationSpeed=0;
            state.isCrouching=false;state.isPassenger=false;state.isFallFlying=false;
            state.isVisuallySwimming=false;state.swimAmount=0;state.xRot=0;
        }
        if(!p.gun())return;

		state.rightArmPose = HumanoidModel.ArmPose.CROSSBOW_HOLD;
		state.leftArmPose = HumanoidModel.ArmPose.EMPTY;
		state.rightHandItemState.clear();
		state.leftHandItemState.clear();
		state.rightHandItemStack = ItemStack.EMPTY;
		state.leftHandItemStack = ItemStack.EMPTY;
	}

    @Inject(method="setupRotations(Lnet/minecraft/client/renderer/entity/state/AvatarRenderState;Lcom/mojang/blaze3d/vertex/PoseStack;FF)V",at=@At("HEAD"),cancellable=true)
    private void passthrough$hunterPin(AvatarRenderState state,PoseStack stack,float bodyYaw,float scale,CallbackInfo ci) {
        HostState.Pose p=HostState.frame();
        var player=Minecraft.getInstance().player;
        if(p==null || player==null || state.id!=player.getId() || !AvatarPosePolicy.prone(p.pin()))return;
        stack.translate(0,AvatarPosePolicy.PRONE_HEIGHT,0);
        stack.rotateDegrees(Axis.YP,180-state.bodyRot);
        stack.rotateDegrees(Axis.XP,90);
        stack.translate(0,-AvatarPosePolicy.PRONE_CENTER,0);
        ci.cancel();
    }
}
