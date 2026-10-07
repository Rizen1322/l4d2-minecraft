foreach (name in ["TraceHull","TraceLine","GetMapName","PrecacheModel","IsPlayerABot","ClientPrint","GetPlayerFromUserID","EntFire","CommandABot"])
    printl("[L4D2MC PROBE] " + name + "=" + (name in getroottable()));
printl("[L4D2MC PROBE] mode="+Director.GetGameMode()+" base="+Director.GetGameModeBase());
printl("[L4D2MC PROBE] registered="+("MCSandbox" in getroottable()));
printl("[L4D2MC PROBE] mode callback="+("UserConsoleCommand" in g_ModeScript));
local player=Entities.FindByClassname(null,"player");
if (player!=null) {
    printl("[L4D2MC PROBE] player="+player.GetOrigin());
    foreach (name in ["SnapEyeAngles","SetAngles","GetBoundingMins","GetBoundingMaxs","EyePosition","EyeAngles","IsIncapacitated","IsHangingFromLedge","IsSurvivor","IsDead","GetPlayerUserId","GetButtonMask","GetHealth"])
        printl("[L4D2MC PROBE] player."+name+"="+(name in player));
    local t={start=player.EyePosition(),end=player.EyePosition()+Vector(0,0,-200),ignore=player,mask=33636363};
    TraceLine(t);
    foreach(k,v in t) printl("[L4D2MC PROBE] trace."+k+"="+v);
}
