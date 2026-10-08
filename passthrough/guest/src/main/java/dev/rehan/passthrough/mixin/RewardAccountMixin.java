package dev.rehan.passthrough.mixin;
import dev.rehan.passthrough.*;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.storage.ValueInput;
import net.minecraft.world.level.storage.ValueOutput;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
/** Inventory, payout receipt, reserve, repair and XP commit together in player.dat. */
@Mixin(Player.class)
abstract class RewardAccountMixin implements RewardAccount {
    @Unique private RewardLedger l4d2mc$ledger=new RewardLedger();
    @Unique private String l4d2mc$invalid;
    public RewardLedger l4d2mc$rewards(){return l4d2mc$ledger;}
    @Unique private boolean l4d2mc$privateWorld(){
        var server=((Player)(Object)this).level().getServer();
        return server!=null && server.getWorldPath(net.minecraft.world.level.storage.LevelResource.ROOT).normalize().getFileName().toString().equals("l4d2mc-guest");
    }
    @Inject(method="addAdditionalSaveData",at=@At("TAIL"))
    private void l4d2mc$save(ValueOutput output,CallbackInfo ci){
        if(!l4d2mc$privateWorld())return;
        output.putString("l4d2mcRewards",l4d2mc$ledger==null?l4d2mc$invalid:l4d2mc$ledger.encode());
    }
    @Inject(method="readAdditionalSaveData",at=@At("TAIL"))
    private void l4d2mc$load(ValueInput input,CallbackInfo ci){
        if(!l4d2mc$privateWorld())return;
        String raw=input.getStringOr("l4d2mcRewards","{}");
        try{l4d2mc$ledger=RewardLedger.decode(raw);l4d2mc$invalid=null;}
        catch(RuntimeException ex){l4d2mc$ledger=null;l4d2mc$invalid=raw;Passthrough.LOG.error("Reward data invalid; preserved without issuing more rewards",ex);}
    }
}
