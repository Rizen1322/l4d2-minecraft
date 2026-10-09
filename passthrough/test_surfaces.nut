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
function TraceLine(t){t.hit<-t.start.z>t.end.z;t.startsolid<-false;t.pos<-Vec(t.start.x,t.start.y,0);}
::L4D2MCPreviousGameplay<-null;::L4D2MCBridge<-{};
dofile("passthrough/host/l4d2mc_gameplay.nut");
dofile("passthrough/host/l4d2mc_survival.nut");
dofile("passthrough/host/l4d2mc_navigation.nut");
local b=L4D2MCBridge;
if(b.CompleteMailbox(["3 map 7","1 2 3"],"3"))throw "Partial collision file accepted";
if(!b.CompleteMailbox(["3 map 7","1 2 3","4 5 6","end 3 2"],"3"))throw "Complete file rejected";
if(b.CompleteMailbox(["3 map 7","1 2 3","end 3 2"],"3"))throw "Wrong row count accepted";
if(b.CompleteMailbox(["3 map 7","1 2 3","end 2 1"],"3"))throw "Old footer accepted";

if(!b.WalkableFloor({hit=true,pos=Vec(0,0,0)},null))throw "Retail trace without normal rejected";
class Area {
    id=0;east=null;constructor(i){id=i;}
    function GetID(){return id;}
    function GetAdjacentCount(dir){return east!=null && dir==1?1:0;}
    function GetAdjacentArea(dir,n){return east;}
    function IsBlocked(team,ignoreBlockers){return false;}
    function IsDamaging(){return false;}
    function GetCorner(i){return Vec((id-1)*128+(i==2?128:0),i==2?128:0,0);}
    function GetZ(pos){return 0.0;}
}
local a=Area(1),c=Area(2);a.east=c;
::NavMesh<-{GetNavArea=function(pos,beneath){return pos.x<128?a:c;}};
local answer=null;b.Reply=function(v){answer=v;};
local player={GetOrigin=function(){return Vec(0,0,0);}};
b.NavRequest(["nav","1","1","0","0","0","200","0","0","44","90"],player);
b.NavTick();
if(answer==null || answer.find("200")!=null || answer.find("6.2500")==null)throw "Connected floor nav failed";
class Enemy {id=0;constructor(i){id=i;}function GetEntityIndex(){return id;}function GetClassname(){return "infected";}}
for(local i=0;i<6;i++)if(!b.ShieldSpend(Enemy(i+1)))throw "Shield capacity too small";
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
    || b.gameplay.replies.len()!=0 || b.survival.links.len()!=0)throw "Prior-round collision/replies/door links survived round_start";
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
now=6.4;b.FireTick(player);
if(hits.len()!=2 || hits[0][1]+hits[1][1]!=12)throw "Missing native flame did not receive fallback burn damage";
b.survival.fireZones.clear();now=11;b.FireTick(player);
if(b.survival.fireActors.len()!=0)throw "Fire contact continued after expiration";
class RescuePlayer {
    hp=0;dead=false;incap=true;revives=0;fail=false;
    function IsValid(){return true;}function GetEntityIndex(){return 22;}
    function GetHealth(){return hp;}function SetHealth(h){hp=h;}
    function IsDead(){return dead;}function IsIncapacitated(){return incap;}
    function IsHangingFromLedge(){return false;}
    function ReviveFromIncap(){revives++;if(!fail)incap=false;}
    function ReviveByDefib(){revives++;if(!fail){dead=false;incap=false;}}
}
local rescued=RescuePlayer(),notices=[];b.Reply=function(body){notices.append(body);};
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
rescued.hp=0;rescued.dead=true;rescued.fail=true;b.gameplay.armed=true;b.gameplay.at=now;
b.TotemHeld(["totemheld","1"]);b.TotemRequest(rescued);
local finalKey=b.survival.totemPending.key,noticeCount=notices.len();
b.TotemResult(["event","503","totemresult",finalKey,"1"],rescued);
if(notices.len()!=noticeCount || b.survival.totemPending==null)throw "Failed native defib falsely announced success";
rescued.fail=false;b.TotemResult(["event","504","totemresult",finalKey,"1"],rescued);
if(rescued.hp!=100 || rescued.dead || notices.top().find("totemapplied")==null)throw "Native defib rescue did not confirm HP100";
print("Retail floor/nav and shield capacity regressions passed\n");
