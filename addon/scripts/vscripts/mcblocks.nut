IncludeScript("l4d2mc/core", getroottable());
IncludeScript("l4d2mc/runtime", getroottable());
DirectorOptions <- {};
function InterceptChat(message, player) { return ::MCSandbox.Chat(message, player); }
function UserConsoleCommand(player, argument) { ::MCSandbox.Command(player, split(argument,",")); }
function Update() { ::MCSandbox.Update(); }
function OnGameplayStart() {
    ::MCSandbox.Welcome();
    ScriptedMode_AddUpdate(function() { ::MCSandbox.Update(); });
}
printl("[L4D2MC] Block Sandbox 0.1 loaded on " + Director.GetMapName());
