// Verify actual Source input helper, not entity Toggle/Press shortcuts.
function RandomInt(a,b){return a;}
local now=0.0;function Time(){return now;}
::L4D2MCPreviousGameplay<-null;::L4D2MCBridge<-{};
dofile("passthrough/host/l4d2mc_gameplay.nut");
class Vec {
    function _add(v){return this;}function _mul(n){return this;}
}
local door={GetClassname=function(){return "prop_door_rotating_checkpoint";},GetName=function(){return "checkpoint_exit";}};
local melee={GetClassname=function(){return "weapon_melee";}};
local p={flags=64,weapon=null,drops=0,
    GetEntityIndex=function(){return 1;},EyePosition=function(){return Vec();},
    EyeAngles=function(){return {Forward=function(){return Vec();}};},
    GetActiveWeapon=function(){return weapon;},DropItem=function(kind){drops++;weapon=null;}
};
::NetProps<-{
    HasProp=function(e,k){return true;},GetPropInt=function(e,k){return e.flags;},
    SetPropInt=function(e,k,v){e.flags=v;},GetPropEntity=function(e,k){return e.weapon;}
};
::EntFire<-function(...){throw "Native checkpoint use replaced with forced entity input";};
local b=L4D2MCBridge;b.survival<-{};
b.Raycast=function(...){return {enthit=door,hit=true};};
b.HeldActions(p,false,true,false);
if(p.flags!=64)throw "MC context click leaked IN_USE to door behind mob";
b.Event(["event","1","interact"],p);
b.HeldActions(p,false,true,false);
if(p.flags!=96)throw "Door press did not remain held";
now=0.2;b.HeldActions(p,false,false,false);
if(p.flags!=64)throw "IN_USE stuck after RMB release";
p.weapon=melee;b.Event(["event","2","interact"],p);
if(p.drops!=1)throw "Hidden starter carry weapon not dropped";
b.HeldActions(p,false,true,false);
if(p.flags!=64)throw "Carry drop reused same click for checkpoint stage";
b.HeldActions(p,false,false,false);b.Event(["event","3","interact"],p);b.HeldActions(p,false,true,false);
if(p.flags!=96)throw "Next RMB press cannot remove checkpoint bar";
b.HeldActions(p,false,true,true);
if(p.flags!=64)throw "Inventory click forwarded to native door";
b.Event(["event","4","interact"],p);b.HeldActions(p,false,false,false);
if(p.flags!=96)throw "Quick RMB press+release between mailbox snapshots lost native use";
now=0.4;b.HeldActions(p,false,false,false);
if(p.flags!=64)throw "Short native use pulse stayed pressed";
print("Native checkpoint press/hold and carry-drop regressions passed\n");
