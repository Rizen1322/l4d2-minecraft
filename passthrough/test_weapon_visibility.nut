// Real hiding helpers, no game launched. Inactive shoulder weapons and dropped items matter.
function RandomInt(a,b){return a;}
local now=0.0;function Time(){return now;}
::L4D2MCPreviousGameplay<-null;::L4D2MCBridge<-{};
dofile("passthrough/host/l4d2mc_gameplay.nut");
class Model {
    id=0;props=null;valid=true;
    constructor(i,flags=0,mode=0,color=-1){id=i;props={m_fEffects=flags,m_nRenderMode=mode,m_clrRender=color};}
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
function Hidden(e){return (e.props.m_fEffects&32)!=0 && e.props.m_nRenderMode==1 && (e.props.m_clrRender&0xFF000000)==0;}
function Native(e,flags=0,mode=0){return e.props.m_fEffects==flags && e.props.m_nRenderMode==mode && e.props.m_clrRender==-1;}
local b=L4D2MCBridge,held=Model(1),holstered=Model(2),world=Model(3),view=Model(4),mapItem=Model(5);
held.props.m_hWeaponWorldModel<-world;
local player=Model(6);player.props.m_hMyWeapons<-[held,holstered];player.props.m_hActiveWeapon<-held;player.props.m_hViewModel<-[view];
local attached=Model(8),otherGun=Model(9),otherPlayer=Model(10);
attached.props.moveparent<-holstered;otherGun.props.m_hOwnerEntity<-otherPlayer;
::Entities<-{FindByClassname=function(previous,pattern){local entries=pattern=="prop_dynamic"?[attached]:pattern=="weapon_*"?[otherGun,mapItem]:[];if(previous==null)return entries.len()>0?entries[0]:null;for(local i=0;i<entries.len()-1;i++)if(entries[i]==previous)return entries[i+1];return null;}};
b.HidePlayerWeapons(player);
if(!Hidden(attached))throw "Owned bonemerge attachment visible in F5";
if(!Native(otherGun))throw "Other survivor gun hidden";
foreach(e in [held,holstered,world])if(!Hidden(e))throw "Third-person model visible";
if(view.props.m_fEffects!=0 || view.props.m_nRenderMode!=1 || (view.props.m_clrRender&0xFF000000)!=0)throw "Predicted viewmodel: EF_NODRAW written or not transparent";
if(!Native(mapItem))throw "Map pickup hidden";
// Camera change clears visibility locally; the next update must hide it again.
holstered.props.m_fEffects=0;holstered.props.m_nRenderMode=0;holstered.props.m_clrRender=-1;b.HidePlayerWeapons(player);
if(!Hidden(holstered))throw "F5 visibility refresh not handled";
// Source drops a formerly hidden carry item; it must be visible on the floor.
player.props.m_hMyWeapons=[held];attached.props.moveparent=null;b.HidePlayerWeapons(player);
if(!Native(attached))throw "Detached model not restored between scans";
// A newly attached model is found by the next full scan, not by the cached recheck.
attached.props.moveparent=held;b.HidePlayerWeapons(player);
if(!Native(attached))throw "Cached recheck ran a full entity scan";
now=0.3;b.HidePlayerWeapons(player);
if(!Hidden(attached))throw "Periodic scan missed a new attachment";
attached.props.moveparent=null;now=0.31;b.HidePlayerWeapons(player);
if(!Native(attached))throw "Detached cached model stayed hidden";
if(!Native(holstered))throw "Dropped item remained invisible";
local ids=[];foreach(id,v in b.gameplay.hidden)ids.append(id);foreach(id in ids)b.RestoreHidden(id);
foreach(e in [held,world,view])if(!Native(e))throw "Native appearance not restored";
local alreadyHidden=Model(7,32,10);player.props.m_hMyWeapons=[alreadyHidden];player.props.m_hActiveWeapon=alreadyHidden;player.props.m_hViewModel=[];
b.HidePlayerWeapons(player);alreadyHidden.props.m_fEffects=0;player.props.m_hMyWeapons=[];player.props.m_hActiveWeapon=null;b.HidePlayerWeapons(player);
if(!Native(alreadyHidden,32,10))throw "Originally hidden item forcibly shown";
local survivor=Model(20,0,1,-1);b.HideSurvivor(survivor);
if(!Hidden(survivor))throw "Survivor attachments still drawn in F5";
b.HideSurvivor(survivor);b.RestoreHidden(20);
if(!Native(survivor,0,1))throw "Survivor appearance not restored";
print("Third-person weapon and drop visibility regressions passed\n");
