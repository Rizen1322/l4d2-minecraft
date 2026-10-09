// Real Source hit handler: common one-hit, SI balance, corpse and occlusion guards.
function RandomInt(a,b){return a;}function Time(){return 1.0;}function printl(s){}
class V {
    x=0;y=0;z=0;constructor(a,b,c){x=a.tofloat();y=b.tofloat();z=c.tofloat();}
    function _add(v){return V(x+v.x,y+v.y,z+v.z);}
    function _sub(v){return V(x-v.x,y-v.y,z-v.z);}
    function _mul(s){return V(x*s,y*s,z*s);}
    function Length(){return sqrt(x*x+y*y+z*z);}
}
function Vector(a,b,c){return V(a,b,c);}
::L4D2MCPreviousGameplay<-null;::L4D2MCBridge<-{};
dofile("passthrough/host/l4d2mc_gameplay.nut");
class Enemy {
    hp=50;life=0;kind="infected";hits=0;amount=0;id=4;pos=null;
    constructor(i=4,x=16){id=i;pos=Vector(x,0,0);}
    function GetHealth(){return hp;}function GetClassname(){return kind;}
    function GetOrigin(){return pos;}function IsValid(){return true;}function GetEntityIndex(){return id;}
    function IsSurvivor(){return false;}
    function TakeDamage(d,t,attacker){hits++;amount=d;hp-=d;}
}
::NetProps<-{HasProp=function(e,p){return p=="m_lifeState";},GetPropInt=function(e,p){return e.life;}};
local enemy=Enemy(),blocked=false;
L4D2MCBridge.FindActor=function(id){return enemy;};
L4D2MCBridge.Raycast=function(a,b,i){return blocked?{hit=true,enthit=null}:{hit=false};};
local b=L4D2MCBridge;
b.Event(["event","1","mobhit","4","35","0","0","0","9","iron_golem"],null);
if(enemy.hp>=0 || enemy.hits!=1)throw "Low-roll iron golem did not one-hit common";
enemy.hp=250;enemy.kind="player";
b.Event(["event","2","mobhit","4","35","0","0","0","9","iron_golem"],null);
if(enemy.hp<=0 || enemy.amount!=180)throw "Special infected golem damage not balanced";
enemy.hp=50;enemy.kind="infected";enemy.life=2;local hits=enemy.hits;
b.Event(["event","3","mobhit","4","35","0","0","0","9","iron_golem"],null);
if(enemy.hits!=hits)throw "Dead actor hit despite positive stale HP";
enemy.life=0;blocked=true;
b.Event(["event","4","mobhit","4","35","0","0","0","9","iron_golem"],null);
if(enemy.hits!=hits)throw "Golem hit through Source wall";
blocked=false;
b.Event(["event","5","mobhit","4","35","0","0","0","9","snow_golem"],null);
if(enemy.amount!=35 || enemy.hp!=15)throw "Snow golem incorrectly got iron one-hit";
// A low car bumper ends at z=12 Source units. Old z=24 foot rays miss it.
b.blocks<-{};b.gameplay.physics[9]<-{proxy=null,pos=Vector(0,0,0),width=44.8,height=86.4,at=1.0};
b.RecoverMob<-function(id,v){};
b.WalkableFloor=function(t,i){return false;};
local bumperHit=false,nativeFloor=0.0;
function TraceLine(t){
    t.hit<-false;t.startsolid<-false;
    if(t.start.z<nativeFloor){t.startsolid=true;return;}
    if(t.start.x==t.end.x && t.start.y==t.end.y && t.start.z>nativeFloor && t.end.z<nativeFloor){t.hit=true;t.pos<-Vector(t.start.x,t.start.y,nativeFloor);return;}
    if(t.start.z==t.end.z && t.start.z>nativeFloor && t.start.z<=nativeFloor+12 && t.start.x<32 && t.end.x>32){
        bumperHit=true;t.hit=true;t.pos<-Vector(32,t.start.y,t.start.z);
    }
}
b.GroundPhysics();
if(!bumperHit || b.gameplay.ground.len()!=1 || b.gameplay.ground[0].find(",1.0000,")==null)throw "Golem hull skipped low vehicle bumper";
// Primed TNT starts 12 Source units below rough native floor (less than half a cube).
nativeFloor=12.0;b.gameplay.physics[9]={proxy=null,pos=Vector(0,0,0),width=31.36,height=31.36,at=1.0,mob=0};
b.GroundPhysics();
if(b.gameplay.ground.len()!=1 || b.gameplay.ground[0].find(",1,0.3750,")==null)throw "Embedded TNT did not receive actual native floor";
// A falling TNT 96 units in the air receives the lower floor, not its current height.
b.gameplay.physics[9].pos=Vector(0,0,108);b.GroundPhysics();
if(b.gameplay.ground.len()!=1 || b.gameplay.ground[0].find(",1,0.3750,")==null)throw "Airborne TNT pinned to an invented floor";
// More than 48 actors in engine enumeration must still include the nearest enemy.
local actors=[];for(local i=0;i<55;i++)actors.append(Enemy(100+i,1000+i));
local nearest=Enemy(900,8),byGolem=Enemy(901,2500);actors.append(nearest);actors.append(byGolem);
::Entities<-{FindByClassname=function(previous,kind){
    if(kind!="infected")return null;
    local next=previous==null?0:actors.find(previous)+1;return next<actors.len()?actors[next]:null;
}};
b.survival<-{golems={}};b.survival.golems[1]<-{entity=nearest,pos=Vector(2400,0,0),at=1.0};
local json=b.ActorJson(Enemy(902,0));
if(json.find("0.2500,0.0000,")==null)throw "Enumeration cap starved nearby live target";
if(json.find("78.1250,0.0000,")==null)throw "Player-only range starved golem enemy";
print("Source golem one-hit, corpse and wall regressions passed\n");
