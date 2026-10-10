// Protocol regression without Source: the first pearl snapshot must trace its launch segment.
function Time(){return 1.0;}function printl(s){}function RandomInt(a,b){return a;}
class V {
    x=0;y=0;z=0;constructor(a,b,c){x=a.tofloat();y=b.tofloat();z=c.tofloat();}
    function _add(v){return V(x+v.x,y+v.y,z+v.z);}
    function _sub(v){return V(x-v.x,y-v.y,z-v.z);}
    function _mul(s){return V(x*s,y*s,z*s);}
    function Length(){return sqrt(x*x+y*y+z*z);}
}
function Vector(x,y,z){return V(x,y,z);}
::L4D2MCBridge<-{};::L4D2MCPreviousGameplay<-null;
dofile("passthrough/host/l4d2mc_gameplay.nut");
local b=L4D2MCBridge,traces=0,teleports=0,damage=0,start=null;
b.Integer=function(s){return s.tointeger();};b.Number=function(s,limit=999999){return s.tofloat();};
b.Raycast=function(a,z,p){traces++;start=a;return {hit=true,pos=Vector(12,0,64)};};
b.TeleportPlayer=function(p,pos){teleports++;return true;};
local p={TakeDamage=function(d,t,a){damage+=d;}};
b.Projectile(["projectile","7","ender_pearl","48","0","64","0","0","0","64"],p);
if(traces!=1 || teleports!=1 || damage!=5 || start.x!=0)throw "Initial pearl segment was lost";
b.Projectile(["projectile","7","ender_pearl","96","0","64","0","0","0","64"],p);
if(teleports!=1 || damage!=5)throw "Repeated mailbox sample teleported twice";
if(traces!=1)throw "Resolved projectile kept issuing Source traces while awaiting acknowledgement";
if(!(7 in b.gameplay.replies))throw "Authoritative hit was not returned to guest";
// Old guest records continue to work, with their second sample supplying the segment.
b.Projectile(["projectile","8","ender_pearl","0","0","64","0"],p);
b.Projectile(["projectile","8","ender_pearl","48","0","64","0"],p);
if(teleports!=2)throw "Legacy projectile compatibility failed";
// A delayed first mailbox snapshot can already be beyond the old per-tick
// 512-unit limit, while its retained launch segment remains safely bounded.
b.Projectile(["projectile","9","ender_pearl","1200","0","64","0","0","0","64"],p);
if(teleports!=3)throw "Coalesced launch snapshot lost its initial wall collision";
local earlier=traces;
b.Raycast=function(a,z,p){traces++;return {hit=false};};
b.Projectile(["projectile","10","ender_pearl","48","0","64","0","0","0","64"],p);
b.Projectile(["projectile","10","ender_pearl","48","0","64","0","0","0","64"],p);
if(traces!=earlier+1)throw "Unchanged mailbox position issued a zero-length Source ray";
print("Projectile launch/authority regressions passed\n");
