// Verify actual Source input helper, not entity Toggle/Press shortcuts.
function RandomInt(a,b){return a;}
local now=0.0;function Time(){return now;}
::L4D2MCPreviousGameplay<-null;::L4D2MCBridge<-{};
dofile("passthrough/host/l4d2mc_gameplay.nut");
class Vec {
    function _add(v){return this;}function _mul(n){return this;}
    function _sub(v){return this;}function Length(){return 32;}
}
function Vector(x,y,z){return Vec();}
local door={GetClassname=function(){return "prop_door_rotating_checkpoint";},GetName=function(){return "checkpoint_exit";}};
local melee={GetClassname=function(){return "weapon_melee";}};
local gascan={GetClassname=function(){return "weapon_gascan";}};
local p={flags=64,weapon=null,drops=0,rescue=null,GetOrigin=function(){return Vec();},
    GetEntityIndex=function(){return 1;},EyePosition=function(){return Vec();},
    EyeAngles=function(){return {Forward=function(){return Vec();}};},
    GetActiveWeapon=function(){return weapon;},DropItem=function(kind){drops++;weapon=null;},IsValid=function(){return true;}
};
local hasForced=false;
::NetProps<-{
    HasProp=function(e,k){return k!="m_afButtonForced" || hasForced;},GetPropInt=function(e,k){return e.flags;},
    SetPropInt=function(e,k,v){e.flags=v;},GetPropEntity=function(e,k){return k=="m_reviveTarget"?e.rescue:e.weapon;}
};
::EntFire<-function(...){throw "Native checkpoint use replaced with forced entity input";};
local commands=[],useDown=false;
::SendToConsole<-function(command){
    if(command!="+use 32766" && command!="-use 32766")throw "Unexpected/executable native use command";
    commands.append(command);useDown=command=="+use 32766";
};
local b=L4D2MCBridge;b.survival<-{};
b.Raycast=function(...){return {enthit=door,hit=true};};
b.HeldActions(p,false,true,false);
if(useDown || commands.len()!=0)throw "MC context click leaked IN_USE to door behind mob";
b.Event(["event","1","interact"],p);
b.HeldActions(p,false,true,false);
if(!useDown || commands.len()!=1 || p.flags!=64)throw "Door client press depends on unavailable server forced-button field";
b.HeldActions(p,false,true,false);
if(commands.len()!=1)throw "Hold spammed native press instead of one edge";
now=0.2;b.HeldActions(p,false,false,false);
if(useDown || commands.top()!="-use 32766")throw "IN_USE stuck after RMB release";
p.weapon=gascan;b.Event(["event","2","interact"],p);
if(p.drops!=1)throw "Carried prop not dropped";
b.HeldActions(p,false,true,false);
if(useDown)throw "Carry drop reused same click for checkpoint stage";
b.HeldActions(p,false,false,false);b.Event(["event","3","interact"],p);b.HeldActions(p,false,true,false);
if(!useDown)throw "Next RMB press cannot remove checkpoint bar";
b.HeldActions(p,false,true,true);
if(useDown)throw "Inventory click forwarded to native door";
b.Event(["event","4","interact"],p);b.HeldActions(p,false,false,false);
if(!useDown)throw "Quick RMB press+release between mailbox snapshots lost native use";
now=0.4;b.HeldActions(p,false,false,false);
if(useDown)throw "Short native use pulse stayed pressed";
hasForced=true;
b.Event(["event","5","interact"],p);b.HeldActions(p,false,true,false);
if(!useDown || (p.flags&32)!=0)throw "Server forced-use bit still substitutes for real client input";
now=0.42;b.Event(["event","6","interact"],p);b.HeldActions(p,false,true,false);
if(useDown)throw "Rapid second click lacked a released usercmd interval";
now=0.48;b.HeldActions(p,false,true,false);
if(!useDown)throw "Rapid second click did not re-press native use after gap";
b.RestoreAppearance();
if(useDown || b.gameplay.nativeUseIntent || b.gameplay.usePulseUntil!=0)throw "Disconnect/reload cleanup left owned native use pressed";
b.Event(["event","7","interact"],p);b.HeldActions(p,false,true,false);
if(!useDown)throw "Dead-path test did not begin with a native hold";
b.epoch<-123;b.TotemPendingFor<-function(player){return true;};b.TotemTick<-function(player){};
::Director<-{GetMapName=function(){return "map";}};
::FileToString<-function(path){return "owner map 0 333 0 0 0 0 123\nend 333 0";};
if(!b.ReadGameplay(p) || useDown || b.gameplay.nativeUseIntent || b.gameplay.usePulseUntil!=0)throw "Pending dead-player rescue kept native use held";
p.weapon=melee;p.drops=0;b.Event(["event","8","interact"],p);
if(p.drops!=0 || p.weapon!=melee)throw "Door use dropped the hidden melee sidearm";
local downed={GetClassname=function(){return "player";},GetName=function(){return "";},IsSurvivor=function(){return true;},IsDead=function(){return false;},IsIncapacitated=function(){return true;},IsHangingFromLedge=function(){return false;}};
downed.IsValid<-function(){return true;};downed.GetOrigin<-function(){return Vec();};
b.Raycast=function(...){return {enthit=downed,hit=true};};
if(!b.Usable(p))throw "Downed teammate is not a native RMB use target";
downed.IsIncapacitated=function(){return false;};downed.IsHangingFromLedge=function(){return true;};
if(!b.Usable(p))throw "Hanging teammate is not a native RMB use target";
downed.IsHangingFromLedge=function(){return false;};
if(b.Usable(p))throw "Healthy survivor captured native item clicks";
downed.IsIncapacitated=function(){return true;};p.rescue=downed;
b.Raycast=function(...){return {hit=false};};
if(!b.Usable(p))throw "Moving aim cancelled a nearby native revive";
b.Raycast=function(...){return {hit=true,enthit=null};};
if(b.Usable(p))throw "Revive hold ignored a wall";
print("Native checkpoint press/hold and carry-drop regressions passed\n");
