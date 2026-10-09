// Exercise the real Source snapshot parser with a deliberately torn file.
function RandomInt(a,b){return 12;}function Time(){return 1.0;}function printl(s){}
function PrecacheModel(s){}function AddThinkToEnt(e,s){}
function UniqueString(s){return s;}
function Vector(x,y,z){return {x=x,y=y,z=z};}
class FakeEntity {
    valid=true;scope=null;
    constructor(){scope={};}
    function IsValid(){return valid;}
    function Kill(){valid=false;}
    function ValidateScriptScope(){}
    function GetScriptScope(){return scope;}
}
function SpawnEntityFromTable(cls,data){return FakeEntity();}
::Entities<-{FindByClassname=function(previous,kind){return null;},Next=function(previous){return null;}};
::Director<-{GetMapName=function(){return "c1m1_hotel";}};
local data="";
function FileToString(name){return data;}
function IncludeScript(name){dofile("passthrough/host/"+name+".nut");}
dofile("passthrough/host/l4d2mc_bridge.nut");
local b=L4D2MCBridge;
data="1 c1m1_hotel 12\n1 2 3\n4 5 6\nend 1 2";b.SyncCollision();
if(b.blocks.len()!=2 || b.collisionSequence!="1")throw "Initial full snapshot failed";
data="2 c1m1_hotel 12\n1 2 3";b.SyncCollision();
if(b.blocks.len()!=2 || b.collisionSequence!="1")throw "Torn prefix removed collider or advanced sequence";
data="2 c1m1_hotel 12\n1 2 3\n4 5 6\nend 2 2";b.SyncCollision();
if(b.blocks.len()!=2 || b.collisionSequence!="2")throw "Complete same sequence ignored after torn prefix";
data="3 c1m1_hotel 11\n1 2 3\nend 3 1";b.SyncCollision();
if(b.blocks.len()!=2 || b.collisionSequence!="2")throw "Prior round colliders accepted";
data="3 c1m1_hotel 12\n1 2 3\nend 3 1";b.SyncCollision();
if(b.blocks.len()!=1 || b.collisionSequence!="3")throw "Authoritative removal failed";
data="owner c1m1_hotel 1 999 0 0 0 0 11\nend 999 0";
b.ReadGameplay(null);
if(b.gameplay.content!=null || b.gameplay.armed)throw "Prior round gameplay accepted";
data="owner c1m1_hotel 1 999 0 0 0 0 12\nevent 1 heal 5";
b.ReadGameplay(null);
if(b.gameplay.content!=null || b.gameplay.armed)throw "Partial gameplay accepted";
print("Actual collision/gameplay framing and epoch regressions passed\n");
