// No Source engine: native collision remains responsible for movement; flight never teleports.
local now=0.0;function Time(){return now;}function printl(s){}function RandomInt(a,b){return a;}
class V {
    x=0;y=0;z=0;constructor(a,b,c){x=a.tofloat();y=b.tofloat();z=c.tofloat();}
    function _mul(s){return V(x*s,y*s,z*s);}function Length(){return sqrt(x*x+y*y+z*z);}
}
function Vector(x,y,z){return V(x,y,z);}
::L4D2MCBridge<-{Integer=function(s){return s.tointeger();},GameplayLease=function(){return true;}};
::NetProps<-{
    HasProp=function(p,k){return k=="m_flGravity" || k=="m_fFlags" || k=="m_tongueOwner" || k=="m_nWaterLevel";},
    GetPropFloat=function(p,k){return p.gravity;},GetPropInt=function(p,k){return k=="m_fFlags"?p.flags:0;},
    GetPropEntity=function(p,k){return p.pin;}
};
class Flyer {
    flags=0;gravity=0.6;vel=null;pin=null;dead=false;incap=false;sets=0;
    constructor(){vel=Vector(640,0,0);}
    function GetEntityIndex(){return 1;}function IsValid(){return true;}
    function IsDead(){return dead;}function IsIncapacitated(){return incap;}function IsHangingFromLedge(){return false;}
    function SetGravity(g){gravity=g;}function GetVelocity(){return vel;}function SetVelocity(v){sets++;vel=v;}
    function EyeAngles(){return {x=0.0,Forward=function(){return Vector(1,0,0);}};}
    function SetOrigin(p){throw "Elytra moved through native geometry using teleport";}
}
dofile("passthrough/host/l4d2mc_flight.nut");local b=L4D2MCBridge,p=Flyer();
function near(a,v){if(abs(a-v)>0.001)throw "Vanilla flight physics regression";}
local glide=b.FlightStep(Vector(640,0,0),Vector(1,0,0),0,false);
near(glide.x,634.74048);near(glide.z,-11.2896);
local rocket=b.FlightStep(Vector(0,0,0),Vector(1,0,0),0,true);
if(rocket.x<540 || rocket.z>=0)throw "Attached rocket did not accelerate forward";
local high=b.FlightStep(Vector(10000,10000,-10000),Vector(1,0,0),0,true);
if(high.Length()>1600.001)throw "Native flight exceeded bounded speed";
b.Flight(["flight","1","0","1","1"],p);b.FlightTick(p);
if(p.gravity!=0.6 || p.sets!=0)throw "Flight without usable Elytra";
p.flags=1;b.Flight(["flight","1","1","1","1"],p);b.FlightTick(p);
if(p.gravity!=0.6 || p.sets!=0)throw "Flight bypassed native grounded jump";
p.flags=0;b.Flight(["flight","1","1","1","0"],p);b.FlightTick(p);
if(p.gravity!=0.001)throw "Native default gravity zero was used for flight";
now=0.051;b.FlightTick(p);if(p.sets!=1)throw "Flight did not use native velocity";
near(p.vel.x,glide.x);near(p.vel.z,glide.z);
p.vel=Vector(0,0,0);now=0.102;b.FlightTick(p);
near(p.vel.x,1.14048);near(p.vel.z,-11.2896);
if(!b.FlightActive(p))throw "Active native glide not exported to peers";
p.pin={};b.FlightTick(p);if(p.gravity!=0.6)throw "Pin did not restore native gravity";
p.pin=null;b.Flight(["flight","1","1","2","1"],p);b.FlightTick(p);p.flags=32;b.FlightTick(p);
if(p.gravity!=0.6)throw "GUI frozen state did not restore gravity";
p.flags=0;b.Flight(["flight","1","1","3","1"],p);b.FlightTick(p);now+=0.8;b.FlightTick(p);
if(p.gravity!=0.6)throw "Stale flight heartbeat retained gravity override";
p.gravity=0;b.Flight(["flight","1","1","4","0"],p);b.FlightTick(p);b.FlightCleanup(p);
if(p.gravity!=0 || b.flight.players.len()!=0)throw "Detach lost original zero/default gravity";
// Food/drink factor stacks once against native baseline, potion and sprint;
// missing, stale or GUI consumption never leaves a sticky movement override.
::L4D2MCPreviousGameplay<-null;dofile("passthrough/host/l4d2mc_gameplay.nut");
b.survival<-{speed=1.5,effectsAt=Time(),player=p};
b.GameplayLease=function(){return true;};
local scale=0.8;
NetProps.GetPropFloat=function(p,k){return k=="m_flLaggedMovementValue"?scale:p.gravity;};
NetProps.SetPropFloat<-function(p,k,value){if(k=="m_flLaggedMovementValue")scale=value;};
NetProps.SetPropInt<-function(p,k,value){p.flags=value;};
::SendToConsole<-function(command){};
b.Consume(["consume","1"]);b.Movement(p,false,true);near(scale,0.24);
b.Movement(p,false,true);near(scale,0.24);
b.Movement(p,true,true);near(scale,0.8);
b.Movement(p,false,false);near(scale,0.24);
now+=0.8;b.Movement(p,false,false);near(scale,0.8);
b.Consume(["consume","0"]);b.Movement(p,false,false);near(scale,0.8);
b.Consume(["consume","1"]);b.Movement(p,false,false);near(scale,0.16);
b.RestoreAppearance();near(scale,0.8);
if(b.gameplay.consuming || b.gameplay.consumeAt!=-100)throw "Consumption survived cleanup";
// Exercise the real complete-mailbox dispatcher. A partial file may retain
// the last good lease but cannot introduce a new flight/consumption snapshot.
b.survival.fireZones<-[];b.epoch<-7;
b.HeldActions=function(...){};b.Hide=function(p){};b.GroundPhysics=function(){};
b.SurvivalTick<-function(p){};b.NavTick<-function(){};b.HidePlayerWeapons=function(p){};
::Director<-{GetMapName=function(){return "map";}};
local mailbox="owner map 1 100 0 0 0 0 7\nflight 1 1 9 0\nconsume 1\nend 100 2";
::FileToString<-function(path){return mailbox;};
b.gameplay.generation="owner";b.gameplay.content="previous";b.gameplay.armed=true;b.gameplay.at=now;
if(!b.ReadGameplay(p) || !b.FlightActive(p) || !b.gameplay.consuming)throw "Complete flight/consume mailbox not applied";
mailbox="owner map 1 101 0 0 0 0 7\nflight 0 0 10 0\nconsume 0";
b.ReadGameplay(p);
if(!b.FlightActive(p) || !b.gameplay.consuming)throw "Partial flight snapshot was applied";
mailbox="owner map 1 102 0 0 0 0 7\nflight 1 1 9\nconsume 2\nend 102 2";
b.ReadGameplay(p);
if(b.gameplay.consuming || b.gameplay.consumeAt!=-100)throw "Invalid consume value retained eating slowdown";
mailbox="owner map 1 103 1 0 0 0 7\nflight 1 1 9 0\nconsume 1\nend 103 2";
b.ReadGameplay(p);near(p.gravity,0);near(scale,0.8);
if(b.FlightActive(p))throw "GUI mailbox kept flight active";
print("Source Elytra native flight and cleanup regressions passed\n");
