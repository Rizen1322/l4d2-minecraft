// Actual per-actor contexts and framed manifests; no Source runtime required.
local clock=1.0,manifest="12 1\n2\nend 1 1",consoleCalls=[];
function Time(){return clock;}function RandomInt(a,b){return a;}
function FileToString(name){return manifest;}function printl(s){}
class Player {
    userid=0;constructor(id){userid=id;}
    function IsValid(){return true;}function IsSurvivor(){return true;}
    function GetPlayerUserId(){return userid;}function GetEntityIndex(){return userid+10;}
}
local host=Player(1),peer=Player(2);
function GetListenServerHost(){return host;}function IsPlayerABot(p){return false;}
function GetPlayerFromUserID(id){return id==1?host:id==2?peer:null;}
::L4D2MCBridge<-{epoch=12,frame=0,blocks={},
    gameplay={content=null,at=-100.0,generation="",lastEvent=0,armed=false,replies={},actors={},physics={},ground=[],hidden={},frozen={},movement={},forced={},nativeUseDown=false,wheel=0},
    survival={player=null,armor=0,hookLiveAt=-100.0,shieldCharge=6,shieldHits={},golems={}},navigation={jobs={},index=0}};
local b=L4D2MCBridge;
b.NativeUse<-function(pressed){consoleCalls.append(pressed);gameplay.nativeUseDown=pressed;};
b.RestoreAppearance<-function(){gameplay.armed=false;NativeUse(false);};
b.Protection<-function(p,a,d,t){return survival.player==p?survival.armor:0;};
b.Integer<-function(t){foreach(c in t)if(c<48 || c>57)throw "integer";return t.tointeger();};
b.CompleteMailbox<-function(lines,sequence){local f=split(lines.top()," ");return f.len()==3 && f[0]=="end" && f[1]==sequence && f[2].tointeger()==lines.len()-2;};
dofile("passthrough/host/l4d2mc_coop.nut");b.CoopInit();
b.CoopReadSessions();
if(!(2 in b.coop.allowed))throw "Framed peer manifest rejected";
manifest="12 2\n3";clock=1.1;b.CoopReadSessions();
if(!(2 in b.coop.allowed) || 3 in b.coop.allowed)throw "Torn manifest changed allowed actors";
clock=2;b.CoopReadSessions();if(b.coop.allowed.len()!=0)throw "Stale peer manifest never expired";
manifest="11 3\n2\nend 3 1";b.CoopReadSessions();if(b.coop.allowed.len()!=0)throw "Prior epoch allowed peer";
foreach(bad in ["12 4\n2\n2\nend 4 2","12 5\n65536\nend 5 1","12 6\n../2\nend 6 1"]){manifest=bad;b.CoopReadSessions();if(b.coop.allowed.len()!=0)throw "Invalid manifest gained actor authority";}
local localCtx=b.CoopContext(host,true),peerCtx=b.CoopContext(peer,false);
b.CoopWith(localCtx,function(){survival.player=host;survival.armor=4;});
b.CoopWith(peerCtx,function(){survival.player=peer;survival.armor=16;gameplay.replies[7]<-"peer";});
if(b.survival.armor!=4 || b.gameplay.replies.len()!=0)throw "Peer state leaked into host";
try{b.CoopWith(peerCtx,function(){throw "test";});}catch(e){}
if(b.survival.armor!=4 || b.coop.current!=null)throw "Exception left peer context installed";
b.CoopWith(peerCtx,function(){NativeUse(true);});
if(consoleCalls.len()!=0 || !peerCtx.gameplay.nativeUseDown)throw "Peer use hijacked host client console";
b.CoopWith(localCtx,function(){NativeUse(true);});if(consoleCalls.len()!=1)throw "Listen host lost native use";
local callbacks={OnGameEvent_player_hurt=function(event){L4D2MCBridge.survival.armor--;}};
b.CoopWrapEvents(callbacks);callbacks.OnGameEvent_player_hurt({userid=2});
if(peerCtx.survival.armor!=15 || localCtx.survival.armor!=4)throw "Damage callback used wrong player's armor";
local outbox="";
b.CoopWith(peerCtx,function(){outbox=CoopOutbox("pickups");});
if(outbox!="l4d2mc_coop_2_pickups.txt" || b.CoopOutbox("pickups")!="l4d2mc_pickups.txt")throw "Pickup ownership crosses actors";
// Actual tick dispatch must preserve actor scope even when entity enumeration starts with peer.
local entities=[peer,host],reads=[],savedFiles={};
::Entities<-{FindByClassname=function(previous,kind){if(previous==null)return entities[0];return previous==entities[0]?entities[1]:null;}};
b.ReadGameplay<-function(p,path="l4d2mc_gameplay.txt"){reads.append([p,path]);gameplay.armed=true;gameplay.at=Time();gameplay.content="live";return true;};
b.GameplayLease<-function(){return gameplay.armed;};
b.HudJsonString<-function(s){return "\""+s+"\"";};
::Director<-{GetMapName=function(){return "coop_map";}};
::StringToFile<-function(path,data){savedFiles[path]<-data;};
b.ActorPoseJson<-function(p){return format("{\"nativeuse\":%s}",gameplay.nativeUseDown?"true":"false");};
clock=3;manifest="12 7\n2\nend 7 1";b.CoopTick(host);
if(reads.len()!=1 || reads[0][0]!=peer || reads[0][1]!="l4d2mc_coop_2.txt" || !peerCtx.active)throw "Peer mailbox dispatched to wrong actor";
if(localCtx.gameplay.content!=null)throw "Peer tick changed host mailbox";
if(b.Protection(peer,null,5,0)!=15 || b.survival.armor!=4 || peerCtx.survival.hookLiveAt!=3)throw "Predamage hook crossed actor context";
b.CoopExport(host);
local pose=savedFiles["l4d2mc_coop_pose.txt"];
if(pose.find("\"local_id\":1")==null || pose.find("\"userid\":2")==null || pose.find("\"nativeuse\":true")==null)throw "Roster dropped explicit host identity or peer native use";
local beforeConsole=consoleCalls.len();clock=4;b.CoopTick(host);
if(peerCtx.active || peerCtx.gameplay.armed || peerCtx.gameplay.nativeUseDown || consoleCalls.len()!=beforeConsole)throw "Expired peer lease failed safe cleanup";
local transitionCalls=[];
local globalCallbacks={OnGameEvent_map_transition=function(e){transitionCalls.append(L4D2MCBridge.survival.player);},OnGameEvent_round_start=function(e){L4D2MCBridge.epoch++;}};
peerCtx.active=true;b.CoopWrapEvents(globalCallbacks);globalCallbacks.OnGameEvent_map_transition({});
if(transitionCalls.len()!=2 || transitionCalls[0]!=host || transitionCalls[1]!=peer)throw "Chapter completion did not route all active actors";
globalCallbacks.OnGameEvent_round_start({});
if(b.epoch!=13 || b.coop.contexts.len()!=0 || b.coop.allowed.len()!=0)throw "Round reset leaked remote actors or advanced epoch twice";
print("Source coop context, callback and manifest regressions passed\n");
