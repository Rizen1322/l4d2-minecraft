package dev.rehan.passthrough.client.mixin;
import dev.rehan.passthrough.client.TeamHud;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.Hud;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
@Mixin(Hud.class)
abstract class TeamHudMixin {
    @Inject(method="extractRenderState",at=@At("TAIL"))
    private void passthrough$teammates(GuiGraphicsExtractor gui,DeltaTracker delta,CallbackInfo ci){TeamHud.extract(gui);dev.rehan.passthrough.client.ActionHud.extract(gui);}
}
