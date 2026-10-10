// Exercise real combat dispatch under actual per-player Source contexts.
local now=1.0;function Time(){return now;}function RandomInt(a,b){return a;}function printl(s){}
class Vec {
    x=0;y=0;z=0;constructor(a=0,b=0,c=0){x=a;y=b;z=c;}
    function _add(v){return Vec(x+v.x,y+v.y,z+v.z);}
    function _sub(v){return Vec(x-v.x,y-v.y,z-v.z);}
    function _mul(n){return Vec(x*n,y*n,z*n);}
    function Length(){return sqrt(x*x+y*y+z*z);}
}
function Vector(x,y,z){return Vec(x,y,z);}
class Actor {
    userid=0;origin=null;health=100;hits=null;
    constructor(id,x){userid=id;origin=Vec(x,0,0);hits=[];}
    function IsValid(){return true;}function IsSurvivor(){return userid<3;}
    function GetPlayerUserId(){return userid;}function GetEntityIndex(){return userid;}
    function EyePosition(){return origin;}function GetOrigin(){return origin;}
    function EyeAngles(){return {Forward=function(){return Vec(1,0,0);}};}
    function GetClassname(){return userid<3?"player":"infected";}
    function GetHealth(){return health;}
    function TakeDamage(d,t,p){hits.append([d,p]);health-=d;}
}
local host=Actor(1,0),peer=Actor(2,200),hostTarget=Actor(3,30),peerTarget=Actor(4,230);
function GetListenServerHost(){return host;}
::NetProps<-{HasProp=function(e,k){return false;}};
::L4D2MCPreviousGameplay<-null;::L4D2MCBridge<-{};
dofile("passthrough/host/l4d2mc_gameplay.nut");
local b=L4D2MCBridge;
b.survival<-{player=host};b.navigation<-{jobs={},index=0};
b.Integer<-function(s){return s.tointeger();};b.Number<-function(s,limit=99999){return s.tofloat();};
b.NativeUse=function(pressed){};
b.Raycast=function(start,end,ignore){return {hit=true,enthit=ignore==peer?peerTarget:hostTarget};};
dofile("passthrough/host/l4d2mc_coop.nut");b.CoopInit();
local own=b.CoopContext(host,true),remote=b.CoopContext(peer);
b.CoopWith(own,function(){Event(["event","1","melee","15","96"],host);});
b.CoopWith(remote,function(){Event(["event","1","melee","30","96"],peer);});
if(hostTarget.hits.len()!=1 || hostTarget.hits[0][1]!=host || peerTarget.hits.len()!=1 || peerTarget.hits[0][1]!=peer)
    throw "Peer melee used host aim or wrong damage attacker";
b.CoopWith(remote,function(){Event(["event","1","melee","30","96"],peer);});
if(peerTarget.hits.len()!=1)throw "Reliable peer melee retry applied damage twice";
local localId=0,remoteId=0;
b.CoopWith(own,function(){localId=Actor(hostTarget);});
b.CoopWith(remote,function(){remoteId=Actor(peerTarget);});
local found=null;b.CoopWith(remote,function(){found=FindActor(remoteId);});
if(found!=peerTarget)throw "Peer actor ID resolved in listen host registry";
b.CoopWith(own,function(){found=FindActor(localId);});
if(found!=hostTarget || b.gameplay!=own.gameplay || b.coop.current!=null)throw "Combat left remote context installed";
// Receipt snapshots must clear only this player's replies and leave combat serials alone.
b.epoch<-12;::Director<-{GetMapName=function(){return "coop_map";}};
local mailbox="live coop_map 1 2 0 0 0 0 12\nreplyack 7\nend 2 1";
::FileToString<-function(path){return mailbox;};
b.CompleteMailbox<-function(lines,sequence){return lines.top()=="end "+sequence+" "+(lines.len()-2);};
foreach(name in ["HeldActions","HideSurvivor","Movement","GroundPhysics","SurvivalTick","NavTick","HidePlayerWeapons"])
    b[name]<-function(...){};
own.gameplay.replies[7]<-"host";remote.gameplay.replies[7]<-"peer";
remote.gameplay.generation="live";remote.gameplay.content="old";remote.gameplay.armed=true;
remote.survival.fireZones<-{};
b.CoopWith(remote,function(){if(!ReadGameplay(peer))throw "Receipt mailbox rejected";});
if(7 in remote.gameplay.replies || !(7 in own.gameplay.replies) || remote.gameplay.lastEvent!=1)
    throw "Receipt snapshot crossed actors or consumed a combat sequence";
print("Source peer combat actor, aim and replay regressions passed\n");
