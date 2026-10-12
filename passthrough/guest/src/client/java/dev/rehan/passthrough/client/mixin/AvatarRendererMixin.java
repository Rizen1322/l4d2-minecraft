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
        if(entity instanceof dev.rehan.passthrough.client.PeerAvatars.PeerAvatar peer){
            state.bodyRot=peer.member.yaw();state.yRot=0;state.xRot=peer.member.pitch();
            state.isCrouching=peer.member.crouching();
            // Client-only mannequins do not run LivingEntity's flight counter.
            // Supply the steady glide pose from the authoritative peer flag.
            if(peer.member.flying()){state.isFallFlying=true;state.fallFlyingTimeInTicks=10;state.shouldApplyFlyingYRot=false;}
            if(peer.member.incap() || AvatarPosePolicy.prone(peer.member.pin())){state.walkAnimationSpeed=0;state.isCrouching=false;state.isFallFlying=false;state.xRot=0;}
            if(HostState.peerReviving(peer.member.id()))passthrough$helpPose(state);
            return;
        }
		if (p == null || entity != Minecraft.getInstance().player) {
			return;
		}

        // Vanilla extraction can clamp the body toward its head or retain a
        // tick's previous orientation. An orbit camera must not turn Steve.
        state.bodyRot=AvatarPosePolicy.bodyYaw(p.firstPerson(),p.yaw(),p.lookYaw());
        state.yRot=0;state.xRot=p.firstPerson()?p.pitch():p.lookPitch();
        state.isCrouching=HostState.isCrouching();
        if(AvatarPosePolicy.prone(p.pin()) || HostState.incapacitated()) {
            state.walkAnimationPos=0;state.walkAnimationSpeed=0;
            state.isCrouching=false;state.isPassenger=false;state.isFallFlying=false;
            state.isVisuallySwimming=false;state.swimAmount=0;state.xRot=0;
        }
        if(HostState.reviving()){state.bodyRot=HostState.reviveYaw();state.yRot=0;passthrough$helpPose(state);}
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
        boolean local=p!=null && player!=null && state.id==player.getId() && (AvatarPosePolicy.prone(p.pin()) || HostState.incapacitated());
        boolean peer=dev.rehan.passthrough.client.PeerAvatars.prone(state.id);
        if(!local && !peer)return;
        stack.translate(0,AvatarPosePolicy.PRONE_HEIGHT,0);
        stack.rotateDegrees(Axis.YP,180-state.bodyRot);
        stack.rotateDegrees(Axis.XP,90);
        stack.translate(0,-AvatarPosePolicy.PRONE_CENTER,0);
        ci.cancel();
    }
    private static void passthrough$helpPose(AvatarRenderState state) {
        // A deliberately frantic two-handed "Minecraft CPR" while Source owns
        // the real revive timer. Purely visual: no extra revive progress or input.
        state.isCrouching=true;state.xRot=35;
        state.rightArmPose=HumanoidModel.ArmPose.CROSSBOW_CHARGE;
        state.leftArmPose=HumanoidModel.ArmPose.CROSSBOW_CHARGE;
        state.isUsingItem=true;
        state.useItemHand=net.minecraft.world.InteractionHand.MAIN_HAND;
        state.maxCrossbowChargeDuration=20;
        state.ticksUsingItem=(float)(10+9*Math.sin(state.ageInTicks*1.4));
    }
}
