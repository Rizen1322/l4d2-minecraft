// Execute the real JSON helpers without launching Source.
::L4D2MCBridge<-{};
local file=file("passthrough/host/l4d2mc_bridge.nut","rb"),code="";
while(!file.eos())code+=format("%c",file.readn('b'));file.close();
local start=code.find("L4D2MCBridge.HudJsonString <-"),end=code.find("L4D2MCBridge.anchor = SpawnEntityFromTable");
compilestring(code.slice(start,end))();
class Member {
    model="";name="";hp=100;dead=false;incap=false;props=null;
    constructor(m,n){model=m;name=n;props={m_iMaxHealth=100,m_healthBuffer=20.0,m_healthBufferTime=10.0};}
    function IsSurvivor(){return true;}function GetModelName(){return model;}
    function GetPlayerName(){return name;}function GetHealth(){return hp;}
    function IsDead(){return dead;}function IsIncapacitated(){return incap;}
}
function Time(){return 20.0;}
::NetProps<-{HasProp=function(e,k){return k in e.props;},GetPropInt=function(e,k){return e.props[k];},GetPropFloat=function(e,k){return e.props[k];}};
::Convars<-{GetFloat=function(key){return key=="survivor_incap_health"?300.0:1.0;}};
local me=Member("survivor_producer.mdl","Me"),nick=Member("survivor_gambler.mdl","Nick \"quote\""),ellis=Member("survivor_mechanic.mdl","Ellis"),coach=Member("survivor_coach.mdl","Coach");
ellis.incap=true;ellis.hp=150;coach.dead=true;
local rows=[me,nick,ellis,coach,Member("survivor_manager.mdl","Extra")];
::Entities<-{FindByClassname=function(previous,kind){local i=previous==null?0:rows.find(previous)+1;return i<rows.len()?rows[i]:null;}};
local json=L4D2MCBridge.TeamHudJson(me);
if(json.find("Nick \\\"quote\\\"")==null)throw "HUD name was not safely JSON escaped";
if(json.find("\"character\":\"nick\"")==null || json.find("\"character\":\"ellis\"")==null)throw "Survivor portrait mapping incorrect";
if(json.find("\"temp\":10.000")==null || json.find("\"max\":300")==null)throw "Team temporary/incap health incorrect";
if(json.find("\"dead\":true")==null || json.find("Extra")!=null)throw "Team death/count incorrect";
rows=[me];if(L4D2MCBridge.TeamHudJson(me)!="[]")throw "Missing teammates must clear alpha HUD";
print("Teammate alpha HUD source export regressions passed\n");
