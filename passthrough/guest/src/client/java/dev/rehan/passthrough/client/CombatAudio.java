package dev.rehan.passthrough.client;

import net.minecraft.client.Minecraft;
import net.minecraft.sounds.SoundEvents;

/** Vanilla assets and the user's Minecraft volume settings; no bundled audio. */
final class CombatAudio {
    private CombatAudio() {}
    static void play(String kind) {
        var player=Minecraft.getInstance().player;
        if(player==null)return;
        var sound=switch(kind) {
            case "sweep" -> SoundEvents.PLAYER_ATTACK_SWEEP;
            case "strong" -> SoundEvents.PLAYER_ATTACK_STRONG;
            case "weak" -> SoundEvents.PLAYER_ATTACK_WEAK;
            case "crit" -> SoundEvents.PLAYER_ATTACK_CRIT;
            case "miss" -> SoundEvents.PLAYER_ATTACK_NODAMAGE;
            default -> null;
        };
        if(sound!=null)player.playSound(sound,0.85F,1.0F);
    }
}
