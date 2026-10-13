// Offline regression: strict mock signatures reproduce the retail nav API.
function RandomInt(a,b){return a;}function printl(s){}
local now=0.0;function Time(){return now;}
class Vec {
    x=0;y=0;z=0;
    constructor(a,b,c){x=a;y=b;z=c;}
    function _add(v){return Vec(x+v.x,y+v.y,z+v.z);}
    function _sub(v){return Vec(x-v.x,y-v.y,z-v.z);}
    function _mul(v){return Vec(x*v,y*v,z*v);}
    function Length(){return sqrt(x*x+y*y+z*z);}
}
function Vector(x,y,z){return Vec(x,y,z);}
local traceReads=0;
function TraceLine(t){traceReads++;t.hit<-t.start.z>t.end.z;t.startsolid<-false;t.pos<-Vec(t.start.x,t.start.y,0);}
::L4D2MCPreviousGameplay<-null;::L4D2MCBridge<-{};
dofile("passthrough/host/l4d2mc_gameplay.nut");
dofile("passthrough/host/l4d2mc_survival.nut");
dofile("passthrough/host/l4d2mc_navigation.nut");
local b=L4D2MCBridge,queueReply=L4D2MCBridge.Reply;
if(b.CompleteMailbox(["3 map 7","1 2 3"],"3"))throw "Partial collision file accepted";
if(!b.CompleteMailbox(["3 map 7","1 2 3","4 5 6","end 3 2"],"3"))throw "Complete file rejected";
if(b.CompleteMailbox(["3 map 7","1 2 3","end 3 2"],"3"))throw "Wrong row count accepted";
if(b.CompleteMailbox(["3 map 7","1 2 3","end 2 1"],"3"))throw "Old footer accepted";

if(!b.WalkableFloor({hit=true,pos=Vec(0,0,0)},null))throw "Retail trace without normal rejected";
local cornerReads=0;
class Area {
    id=0;east=null;constructor(i){id=i;}
    function GetID(){return id;}
    function GetAdjacentCount(dir){return east!=null && dir==1?1:0;}
    function GetAdjacentArea(dir,n){return east;}
    function IsBlocked(team,ignoreBlockers){return false;}
    function IsDamaging(){return false;}
    function GetCorner(i){cornerReads++;return Vec((id-1)*128+(i==2?128:0),i==2?128:0,0);}
    function GetZ(pos){return 0.0;}
}
local a=Area(1),c=Area(2);a.east=c;
if(b.NavPortal(a,c,1,28,88)==null)throw "Valid portal rejected";
local readBefore=cornerReads,traceBefore=traceReads;
if(b.NavPortal(a,c,1,28,88)==null)throw "Cached portal rejected";
if(cornerReads!=readBefore || readBefore!=4)throw "Static nav bounds fetched repeatedly";
if(traceReads<=traceBefore)throw "Dynamic portal traces were incorrectly cached";
::NavMesh<-{GetNavArea=function(pos,beneath){return pos.x<128?a:c;}};
local answer=null;b.Reply=function(v){answer=v;return true;};
local player={GetOrigin=function(){return Vec(0,0,0);}};
b.NavRequest(["nav","1","1","0","0","0","200","0","0","44","90"],player);
b.NavTick();
if(answer==null || answer.find("200")!=null || answer.find("6.2500")==null)throw "Connected floor nav failed";
class Enemy {id=0;constructor(i){id=i;}function GetEntityIndex(){return id;}function GetClassname(){return "infected";}}
local shieldSounds=[];b.Reply=function(value){shieldSounds.append(value);return true;};
local repeated=Enemy(999);b.ShieldSpend(repeated);b.ShieldSpend(repeated);
if(shieldSounds.len()!=1 || shieldSounds[0].find("shieldblock")==null)throw "Repeated shield contact duplicated block sound";
b.survival.shieldCharge=6;b.survival.shieldHitAt.clear();shieldSounds.clear();
for(local i=0;i<6;i++)if(!b.ShieldSpend(Enemy(i+1)))throw "Shield capacity too small";
local blocks=0,breaks=0;foreach(value in shieldSounds){if(value.find("shieldblock")!=null)blocks++;if(value.find("shielddisable")!=null)breaks++;}
if(blocks!=6 || breaks!=1)throw "Shield sound/cooldown count incorrect";
if(b.ShieldSpend(Enemy(7)) || b.ShieldAvailable())throw "Shield must enter cooldown";
now=6;b.ShieldTick(player);
if(!b.ShieldAvailable() || b.survival.shieldCharge!=6)throw "Shield did not recover";
b.survival.shieldHitAt.clear();
class Special extends Enemy {function GetClassname(){return "player";}}
for(local i=0;i<3;i++)if(!b.ShieldSpend(Special(i+20)))throw "Special capacity too small";
if(b.ShieldAvailable())throw "Three special attacks must exhaust shield";
b.survival.meal=32;b.survival.nextMeal=999;b.survival.nextIgnite=999;
b.survival.nextBurn=999;b.survival.nextShield=999;b.survival.nextAggro=999;
b.survival.links["1 2 3"]<-{entity=null};
b.SurvivalCleanup();
if(b.survival.meal!=0 || b.survival.nextMeal!=0 || b.survival.nextIgnite!=0
    || b.survival.nextBurn!=0 || b.survival.nextShield!=0 || b.survival.nextAggro!=0
    )throw "Prior-round heal/timers survived cleanup";
if(b.survival.links.len()!=1)throw "Temporary disconnect lost door link";
local collisionCleared=false;b.ClearCollision<-function(){collisionCleared=true;};b.epoch<-1;
b.collisionSequence<-"old";b.gameplay.content="old";b.gameplay.armed=true;b.gameplay.replies[5]<-"old";
L4D2MCSurvivalEvents.OnGameEvent_round_start({});
if(!collisionCleared || b.collisionSequence!="" || b.gameplay.content!=null || b.gameplay.armed
    || b.gameplay.replies.len()!=0 || b.survival.links.len()!=0 || b.navigation.jobs.len()!=0)throw "Prior-round collision/replies/door links/nav jobs survived round_start";
local hits=[];
class Target {
    id=0;kind="";pos=null;friendly=false;
    constructor(i,k,p,ally=false){id=i;kind=k;pos=p;friendly=ally;}
    function IsValid(){return true;}
    function GetClassname(){return kind;}
    function GetHealth(){return 100;}
    function GetOrigin(){return pos;}
    function IsSurvivor(){return friendly;}
    function TakeDamage(amount,type,attacker){hits.append([id,amount]);}
}
local targets=[Target(1,"infected",Vec(64,0,32)),Target(2,"infected",Vec(80,16,32)),
    Target(3,"player",Vec(60,0,32),true),Target(4,"infected",Vec(-32,0,32)),Target(5,"infected",Vec(60,-20,32))];
::Entities<-{FindByClassnameWithin=function(previous,kind,p,r){
    local next=previous==null?0:targets.find(previous)+1;
    for(local i=next;i<targets.len();i++)if(targets[i].kind==kind)return targets[i];return null;
}};
::NetProps<-{HasProp=function(e,p){return false;}};
b.Raycast=function(start,end,ignore){
    if(end.y==-20)return {hit=true,enthit=null};
    return {hit=true,enthit=end.y==16?targets[1]:targets[0]};
};
player.EyePosition<-function(){return Vec(0,0,64);};
player.EyeAngles<-function(){return {Forward=function(){return Vec(1,0,0);}};};
b.Event(["event","1","melee","105","96","1","1"],player);
if(hits.len()!=2 || hits[0][0]!=1 || hits[1][0]!=2 || hits[0][1]!=101 || hits[1][1]!=101)throw "Sword cleave hit ally, wall, rear or failed one-hit common";
local floorSpawns=0;::DropFire<-function(p){floorSpawns++;};
b.IgniteGround(["event","2","ignite","0","0","0"],player);
if(floorSpawns!=0)throw "Flint created native ground fire";
if(!b.FireOverlap(Vec(0,0,0),Vec(-8,-24,0),Vec(8,-8,72)))throw "Fire missed body standing in cell";
if(b.FireOverlap(Vec(0,0,0),Vec(40,-24,0),Vec(56,-8,72)))throw "Fire hit outside cell";
if(b.FireOverlap(Vec(0,0,0),Vec(-8,-24,40),Vec(8,-8,112)))throw "Fire hit actor on another floor";
class BurningTarget extends Target {
    name="";function GetName(){return name;}
    function __KeyValueFromString(k,v){name=v;}
    function GetEntityIndex(){return id;}
}
targets=[BurningTarget(10,"infected",Vec(8,-16,0)),BurningTarget(11,"player",Vec(8,-16,0),true)];
Entities.Next<-function(previous){return null;};
::UniqueString<-function(prefix){return prefix;};local ignitions=[];
::EntFire<-function(name,input,value,delay,activator){ignitions.append([name,input,value]);};
b.Raycast=function(start,end,ignore){return {hit=false};};hits.clear();
b.FireZone(["fire","0","0","0"],player);b.FireTick(player);
if(ignitions.len()!=2 || ignitions[0][1]!="IgniteLifetime" || hits.len()!=0)throw "Fire contact failed native ignite or doubled initial damage";
if(!b.ContactBurning(targets[1]))throw "Friendly Source fire did not export Minecraft burning state";
now=6.4;b.FireTick(player);
if(hits.len()!=2 || hits[0][1]+hits[1][1]!=12)throw "Missing native flame did not receive fallback burn damage";
b.survival.fireZones.clear();now=11;b.FireTick(player);
if(b.survival.fireActors.len()!=0)throw "Fire contact continued after expiration";
if(b.ContactBurning(targets[1]))throw "Expired teammate burning state retained";
class RescuePlayer {
    hp=0;dead=false;incap=true;revives=0;fail=false;pos=null;velocity=null;baseVelocity=null;fallVelocity=0;motionResets=0;
    constructor(){pos=Vec(0,0,0);velocity=Vec(0,0,0);baseVelocity=Vec(0,0,0);}
    function IsValid(){return true;}function GetEntityIndex(){return 22;}
    function GetHealth(){return hp;}function SetHealth(h){hp=h;}
    function IsDead(){return dead;}function IsIncapacitated(){return incap;}
    function IsHangingFromLedge(){return false;}
    function GetOrigin(){return pos;}function SetOrigin(p){pos=p;}function GetVelocity(){return velocity;}
    function SetVelocity(p){motionResets++;velocity=p;}
    function ReviveFromIncap(){revives++;if(!fail)incap=false;}
    function ReviveByDefib(){revives++;if(!fail){dead=false;incap=false;}}
}
local rescued=RescuePlayer(),notices=[];b.Reply=function(body){notices.append(body);return true;};
b.gameplay.armed=true;b.gameplay.at=now;b.survival.player=rescued;
b.TotemRequest(rescued);
if(b.survival.totemPending!=null)throw "Rescue requested without held totem";
b.TotemHeld(["totemheld","1"]);b.TotemRequest(rescued);
local rejected=b.survival.totemPending.key;
b.TotemResult(["event","1","totemresult",rejected,"0"],rescued);
if(rescued.revives!=0 || b.survival.totemPending!=null)throw "Unconsumed totem granted free revive";
b.TotemHeld(["totemheld","1"]);b.TotemRequest(rescued);
local consumed=b.survival.totemPending.key;
local mailbox="owner map 0 777 0 0 0 0 "+b.epoch+"\nevent 500 interact\nevent 501 totemresult "+consumed+" 1\nend 777 2";
::FileToString<-function(path){return mailbox;};::Director<-{GetMapName=function(){return "map";}};
if(!b.ReadGameplay(rescued) || rescued.hp!=100 || rescued.incap || rescued.revives!=1)throw "Inactive-frame totem transaction failed";
b.TotemResult(["event","502","totemresult",consumed,"1"],rescued);
if(rescued.revives!=1)throw "Repeated totem result revived twice";
if(!b.TotemPendingFor(rescued) || notices.top().find("totemapplied")!=null)throw "Totem announced success before another physics frame";
now+=0.2;b.TotemTick(rescued);
if(b.survival.totemPending!=null || notices.top().find("totemapplied")==null)throw "Surviving rescue was not confirmed";
rescued.hp=0;rescued.dead=true;rescued.fail=true;b.gameplay.armed=true;b.gameplay.at=now;
b.TotemHeld(["totemheld","1"]);b.TotemRequest(rescued);
local finalKey=b.survival.totemPending.key,noticeCount=notices.len();
b.TotemResult(["event","503","totemresult",finalKey,"1"],rescued);
if(notices.len()!=noticeCount || b.survival.totemPending==null)throw "Failed native defib falsely announced success";
rescued.fail=false;b.TotemResult(["event","504","totemresult",finalKey,"1"],rescued);
if(rescued.hp!=100 || rescued.dead)throw "Native defib rescue did not set HP100";
now+=0.2;b.TotemTick(rescued);
if(notices.top().find("totemapplied")==null)throw "Native defib rescue did not confirm HP100 after physics";
// A corpse inside a kill volume must return to this player's grounded point,
// rather than replay its old downward velocity and instantly die again.
local hurt={GetOrigin=function(){return Vec(0,0,0);}};
Entities.FindByClassname<-function(previous,kind){return kind=="trigger_hurt" && previous==null?hurt:null;};
NetProps.HasProp=function(e,k){return k=="m_Collision.m_vecMins" || k=="m_Collision.m_vecMaxs" || k=="m_vecVelocity" || k=="m_vecBaseVelocity" || k=="m_flFallVelocity";};
NetProps.GetPropVector<-function(e,k){
    if(e==hurt)return k=="m_Collision.m_vecMins"?Vec(-1024,-1024,-1024):Vec(1024,1024,0);
    return k=="m_Collision.m_vecMins"?Vec(-16,-16,0):Vec(16,16,72);
};
NetProps.SetPropVector<-function(e,k,p){if(k=="m_vecVelocity")e.velocity=p;else if(k=="m_vecBaseVelocity")e.baseVelocity=p;};
NetProps.SetPropFloat<-function(e,k,v){e.fallVelocity=v;};
::TraceLine=function(t){
    t.startsolid<-false;t.hit<-t.start.z>=100 && t.end.z<=100 && t.start.z>t.end.z;
    t.pos<-Vec(t.start.x,t.start.y,100);
};
rescued.hp=0;rescued.dead=true;rescued.pos=Vec(0,0,-500);rescued.velocity=Vec(20,30,-900);rescued.fallVelocity=900;
b.survival.totemGround={entity=rescued,epoch=b.epoch,pos=Vec(12,24,100),at=now};
b.gameplay.armed=true;b.gameplay.at=now;b.TotemDamage(rescued,{type=32});b.TotemHeld(["totemheld","1"]);b.TotemRequest(rescued);
local fallKey=b.survival.totemPending.key;
b.TotemResult(["event","505","totemresult",fallKey,"1"],rescued);
if(rescued.pos.x!=12 || rescued.pos.y!=24 || rescued.pos.z!=101 || rescued.velocity.Length()!=0 || rescued.baseVelocity.Length()!=0 || rescued.fallVelocity!=0 || rescued.hp!=100 || rescued.motionResets==0)
    throw "Fall totem failed safe native floor or retained fall momentum";
now+=0.2;b.TotemTick(rescued);
if(b.survival.totemPending!=null || notices.top().find("totemapplied")==null)throw "Safe fall rescue not confirmed";
rescued.hp=0;rescued.dead=true;rescued.pos=Vec(0,0,-500);
b.survival.totemGround={entity=rescued,epoch=b.epoch+1,pos=Vec(12,24,100),at=now};
b.gameplay.armed=true;b.gameplay.at=now;b.TotemDamage(rescued,{type=32});b.TotemHeld(["totemheld","1"]);b.TotemRequest(rescued);
local staleFloorKey=b.survival.totemPending.key,oldNotices=notices.len();
b.TotemResult(["event","506","totemresult",staleFloorKey,"1"],rescued);
if(rescued.pos.z!=-500 || notices.len()!=oldNotices || b.survival.totemPending.applied)throw "Fall rescue used another map's anchor or falsely announced success";
// The anchor is above the hazard, but its vanished platform snaps the final
// destination into trigger_hurt. Neither the anchor nor fallback XY may win.
rescued.dead=false;rescued.incap=false;rescued.pos=Vec(0,0,200);
NetProps.GetPropVector=function(e,k){
    if(e==hurt)return k=="m_Collision.m_vecMins"?Vec(-1024,-1024,-1024):Vec(1024,1024,60);
    return k=="m_Collision.m_vecMins"?Vec(-16,-16,0):Vec(16,16,72);
};
::TraceLine=function(t){t.startsolid<-false;t.hit<-t.start.z>0 && t.end.z<=0;t.pos<-Vec(t.start.x,t.start.y,0);t.normal<-Vec(0,0,1);};
local anchor=Vec(12,24,100);
if(b.TotemHazard(rescued,anchor))throw "Test anchor must be safe before floor snap";
if(b.TeleportPlayer(rescued,anchor,false,true) || rescued.pos.z!=200)throw "Rescue accepted dangerous snapped destination";
Entities.FindByClassname=function(previous,kind){return null;};
::TraceLine=function(t){t.startsolid<-false;t.hit<-t.start.z>0 && t.end.z<=0;t.pos<-Vec(t.start.x,t.start.y,0);t.normal<-Vec(1,0,0.2);};
if(b.TeleportPlayer(rescued,anchor,false,true) || rescued.pos.z!=200)throw "Rescue accepted steep snapped floor";
// Real bounded outbox: an applied totem and a finished route both survive
// congestion, enqueue exactly once when capacity returns, and never revive twice.
b.Reply=queueReply;b.gameplay.replies.clear();
for(local i=0;i<64;i++)b.gameplay.replies[i]<-"busy";
if(b.Reply("\"t\":\"test\"") || b.gameplay.replies.len()!=64)throw "Reply exceeded its bounded outbox";
b.survival.totemPending=null;rescued.hp=0;rescued.incap=true;rescued.dead=false;
b.survival.totemDamageAt=-100;b.survival.totemFallingAt=-100;
b.gameplay.armed=true;b.gameplay.at=now;b.TotemHeld(["totemheld","1"]);b.TotemRequest(rescued);
local congestedKey=b.survival.totemPending.key;
b.TotemResult(["event","507","totemresult",congestedKey,"1"],rescued);
local revives=rescued.revives;now+=0.2;b.TotemTick(rescued);
if(!b.TotemPendingFor(rescued) || !b.survival.totemPending.applied || b.gameplay.replies.len()!=64)throw "Congestion lost applied totem transaction";
delete b.gameplay.replies[0];b.TotemTick(rescued);
if(b.survival.totemPending!=null || b.gameplay.replies.len()!=64 || rescued.revives!=revives)throw "Totem queue recovery failed or revived twice";
local confirmations=0;foreach(id,body in b.gameplay.replies)if(body.find("totemapplied")!=null)confirmations++;
b.TotemTick(rescued);if(confirmations!=1 || b.gameplay.replies.len()!=64)throw "Repeated totem confirmation";
::TraceLine=function(t){t.hit<-t.start.z>t.end.z;t.startsolid<-false;t.pos<-Vec(t.start.x,t.start.y,0);};
b.NavRequest(["nav","77","901","0","0","0","200","0","0","44","90"],player);b.NavTick();
local job=b.navigation.jobs[77];
if(!job.done || job.answered || job.answer==null || b.gameplay.replies.len()!=64)throw "Full outbox lost completed nav response";
local cachedAnswer=job.answer;
b.NavRequest(["nav","77","901","0","0","0","200","0","0","44","90"],player);
if(job.answered)throw "Nav falsely accepted queued answer";
delete b.gameplay.replies[1];b.NavTick();
if(!job.answered || job.answer!=cachedAnswer || b.gameplay.replies.len()!=64)throw "Nav result not retried after congestion";
b.NavTick();b.NavRequest(["nav","77","901","0","0","0","200","0","0","44","90"],player);
local routeCount=0;foreach(id,body in b.gameplay.replies)if(body.find("navpath")!=null)routeCount++;
if(routeCount!=1)throw "Completed nav retry duplicated queued result";
print("Retail floor/nav and shield capacity regressions passed\n");
