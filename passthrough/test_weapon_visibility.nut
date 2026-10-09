// Real hiding helpers, no game launched. Inactive shoulder weapons and dropped items matter.
function RandomInt(a,b){return a;}
::L4D2MCPreviousGameplay<-null;::L4D2MCBridge<-{};
dofile("passthrough/host/l4d2mc_gameplay.nut");
class Model {
    id=0;props=null;valid=true;
    constructor(i,flags=0,mode=0){id=i;props={m_fEffects=flags,m_nRenderMode=mode};}
    function IsValid(){return valid;}
    function GetEntityIndex(){return id;}
}
::NetProps<-{
    HasProp=function(e,p){return p in e.props;},
    GetPropInt=function(e,p){return e.props[p];},
    SetPropInt=function(e,p,v){e.props[p]=v;},
    GetPropEntity=function(e,p){return e.props[p];},
    GetPropArraySize=function(e,p){return e.props[p].len();},
    GetPropEntityArray=function(e,p,i){return e.props[p][i];}
};
local b=L4D2MCBridge,held=Model(1),holstered=Model(2),world=Model(3),view=Model(4),mapItem=Model(5);
held.props.m_hWeaponWorldModel<-world;
local player=Model(6);player.props.m_hMyWeapons<-[held,holstered];player.props.m_hActiveWeapon<-held;player.props.m_hViewModel<-[view];
b.HidePlayerWeapons(player);
foreach(e in [held,holstered,world,view])if((e.props.m_fEffects&32)==0 || e.props.m_nRenderMode!=10)throw "Third-person model visible";
if(mapItem.props.m_fEffects!=0 || mapItem.props.m_nRenderMode!=0)throw "Map pickup hidden";
// Camera change clears visibility locally; the next update must hide it again.
holstered.props.m_fEffects=0;holstered.props.m_nRenderMode=0;b.HidePlayerWeapons(player);
if(holstered.props.m_nRenderMode!=10 || (holstered.props.m_fEffects&32)==0)throw "F5 visibility refresh not handled";
// Source drops a formerly hidden carry item; it must be visible on the floor.
player.props.m_hMyWeapons=[held];b.HidePlayerWeapons(player);
if(holstered.props.m_fEffects!=0 || holstered.props.m_nRenderMode!=0)throw "Dropped item remained invisible";
local ids=[];foreach(id,v in b.gameplay.hidden)ids.append(id);foreach(id in ids)b.RestoreHidden(id);
foreach(e in [held,world,view])if(e.props.m_fEffects!=0 || e.props.m_nRenderMode!=0)throw "Native appearance not restored";
local alreadyHidden=Model(7,32,10);player.props.m_hMyWeapons=[alreadyHidden];player.props.m_hActiveWeapon=alreadyHidden;player.props.m_hViewModel=[];
b.HidePlayerWeapons(player);player.props.m_hMyWeapons=[];player.props.m_hActiveWeapon=null;b.HidePlayerWeapons(player);
if(alreadyHidden.props.m_fEffects!=32 || alreadyHidden.props.m_nRenderMode!=10)throw "Originally hidden item forcibly shown";
print("Third-person weapon and drop visibility regressions passed\n");
