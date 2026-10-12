// Private offline bridge. Mailbox values are parsed as DATA, never RunScriptCode.
L4D2MCBridge.gameplay <- L4D2MCPreviousGameplay!=null?L4D2MCPreviousGameplay:
    {content=null, at=-100.0, generation="", lastEvent=0, armed=false,
    hidden={}, frozen={}, movement={}, actors={}, actorSerial=RandomInt(1000,1000000000), projectiles={}, replies={},
    physics={},physIndex=0,ground=[],wheel=0};
L4D2MCPreviousGameplay=null;
if(!("forced" in L4D2MCBridge.gameplay))L4D2MCBridge.gameplay.forced<-{};
if(!("nativeUseIntent" in L4D2MCBridge.gameplay))L4D2MCBridge.gameplay.nativeUseIntent<-false;
if(!("usePulseUntil" in L4D2MCBridge.gameplay))L4D2MCBridge.gameplay.usePulseUntil<-0.0;
if(!("nativeUseDown" in L4D2MCBridge.gameplay))L4D2MCBridge.gameplay.nativeUseDown<-false;
if(!("useGapUntil" in L4D2MCBridge.gameplay))L4D2MCBridge.gameplay.useGapUntil<-0.0;
if(!("consuming" in L4D2MCBridge.gameplay)){L4D2MCBridge.gameplay.consuming<-false;L4D2MCBridge.gameplay.consumeAt<- -100.0;}
L4D2MCBridge.Consume <- function(f) {
    if(f.len()!=2)return;local using=Integer(f[1]);if(using>1)return;
    gameplay.consuming=using==1;gameplay.consumeAt=Time();
};
L4D2MCBridge.NativeUse <- function(pressed) {
    if(pressed==gameplay.nativeUseDown)return;
    // This is the real client command route, including L4D2's selected-use
    // entity/usercmd processing. A server forced-button bit alone is insufficient.
    // Own key id avoids releasing somebody else's physical +use bind.
    SendToConsole(pressed?"+use 32766":"-use 32766");
    gameplay.nativeUseDown=pressed;
};
L4D2MCBridge.Number <- function(token,limit=32768.0) {
    if(token.len()==0 || token.len()>32)throw "invalid number";
    for(local i=0;i<token.len();i++)if("0123456789-+.eE".find(token.slice(i,i+1))==null)throw "invalid numeric token";
    local n=token.tofloat();if(!(n>=-limit&&n<=limit))throw "number outside bounds";
    return n;
};
L4D2MCBridge.Integer <- function(token) {
    if(token.len()==0 || token.len()>10)throw "invalid integer";
    for(local i=0;i<token.len();i++)if(token[i]<48 || token[i]>57)throw "invalid integer token";
    local n=token.tointeger();if(n<0)throw "integer overflow";return n;
};
// A streamed file prefix is never an authoritative snapshot.
L4D2MCBridge.CompleteMailbox <- function(lines,identity) {
    if(lines.len()<2)return false;
    local footer=split(lines.top()," ");
    if(footer.len()!=3 || footer[0]!="end" || footer[1]!=identity)return false;
    try{return Integer(footer[2])==lines.len()-2;}catch(error){return false;}
};
L4D2MCBridge.Hide <- function(e) {
    if(e==null || !e.IsValid() || !NetProps.HasProp(e,"m_fEffects"))return;
    local id=e.GetEntityIndex(),flags=NetProps.GetPropInt(e,"m_fEffects");
    if(!(id in gameplay.hidden) || gameplay.hidden[id].entity!=e)gameplay.hidden[id]<-{entity=e,old=(flags&32)!=0};
    NetProps.SetPropInt(e,"m_fEffects",flags|32);
};
// Client-side attachments (held melee, holstered sidearms) ignore their weapon
// entity's flags but are drawn with the survivor; make the survivor transparent too.
L4D2MCBridge.HideSurvivor <- function(player) {
    Hide(player);
    if(!NetProps.HasProp(player,"m_nRenderMode") || !NetProps.HasProp(player,"m_clrRender"))return;
    local saved=gameplay.hidden[player.GetEntityIndex()];
    // Replace only a bridged survivor's original outline. A native, non-solid
    // six-box proxy follows Source directly, so its aura works behind map walls.
    if(NetProps.HasProp(player,"m_Glow.m_iGlowType") && "SpawnEntityFromTable" in getroottable()) {
        local kind=NetProps.GetPropInt(player,"m_Glow.m_iGlowType");
        if(!("aura" in saved) || saved.aura==null || !saved.aura.IsValid()) {
            local aura=SpawnEntityFromTable("prop_dynamic_override",{model="models/l4d2mc/steve_aura.mdl",solid=0,rendermode=1,renderamt=0,disableshadows=1});
            if(aura!=null && aura.IsValid() && NetProps.HasProp(aura,"m_Glow.m_iGlowType")) {
                saved.aura<-aura;saved.glowType<-kind;
                aura.SetOrigin(player.GetOrigin());
            }else if(aura!=null && aura.IsValid())aura.Kill();
        }
        if("aura" in saved && saved.aura!=null && saved.aura.IsValid()) {
            if(kind!=0)saved.glowType=kind;
            NetProps.SetPropInt(player,"m_Glow.m_iGlowType",0);
            if(NetProps.HasProp(player,"m_bSurvivorGlowEnabled")) {
                if(!("survivorGlow" in saved))saved.survivorGlow<-NetProps.GetPropInt(player,"m_bSurvivorGlowEnabled");
                NetProps.SetPropInt(player,"m_bSurvivorGlowEnabled",0);
            }
            saved.aura.SetOrigin(player.GetOrigin());saved.aura.SetAngles(player.GetAngles());
            NetProps.SetPropInt(saved.aura,"m_Glow.m_iGlowType",saved.glowType>0?saved.glowType:3);
            foreach(prop in ["m_Glow.m_glowColorOverride","m_Glow.m_bFlashing"])
                if(NetProps.HasProp(player,prop) && NetProps.HasProp(saved.aura,prop))NetProps.SetPropInt(saved.aura,prop,NetProps.GetPropInt(player,prop));
            if(NetProps.HasProp(saved.aura,"m_Glow.m_nGlowRangeMin"))NetProps.SetPropInt(saved.aura,"m_Glow.m_nGlowRangeMin",96);
            if(NetProps.HasProp(saved.aura,"m_Glow.m_nGlowRange"))NetProps.SetPropInt(saved.aura,"m_Glow.m_nGlowRange",3000);
            if(saved.glowType==0 && NetProps.HasProp(saved.aura,"m_Glow.m_glowColorOverride"))NetProps.SetPropInt(saved.aura,"m_Glow.m_glowColorOverride",player.GetHealth()<25?0x4040FF:0xFFCC44);
        }
    }
    local mode=NetProps.GetPropInt(player,"m_nRenderMode"),color=NetProps.GetPropInt(player,"m_clrRender");
    if(!(mode==1 && (color&0xFF000000)==0)) {
        saved.renderMode<-mode;
        saved.renderColor<-color;
    }
    NetProps.SetPropInt(player,"m_nRenderMode",1);
    NetProps.SetPropInt(player,"m_clrRender",color&0x00FFFFFF);
};
L4D2MCBridge.RestoreHidden <- function(id) {
    if(!(id in gameplay.hidden))return;
    local saved=gameplay.hidden[id],e=saved.entity;
    if("aura" in saved && saved.aura!=null && saved.aura.IsValid())saved.aura.Kill();
    if(e.IsValid()) {
        if("survivorGlow" in saved && NetProps.HasProp(e,"m_bSurvivorGlowEnabled") && NetProps.GetPropInt(e,"m_bSurvivorGlowEnabled")==0)NetProps.SetPropInt(e,"m_bSurvivorGlowEnabled",saved.survivorGlow);
        if("glowType" in saved && NetProps.HasProp(e,"m_Glow.m_iGlowType") && NetProps.GetPropInt(e,"m_Glow.m_iGlowType")==0)NetProps.SetPropInt(e,"m_Glow.m_iGlowType",saved.glowType);
        // old==null: render-colour-only record (predicted viewmodel); never write its flags.
        if(saved.old!=null) {
            local flags=NetProps.GetPropInt(e,"m_fEffects");
            NetProps.SetPropInt(e,"m_fEffects",saved.old?(flags|32):(flags&(~32)));
        }
        if("renderMode" in saved && "renderColor" in saved && NetProps.GetPropInt(e,"m_nRenderMode")==1 &&
            (NetProps.GetPropInt(e,"m_clrRender")&0xFF000000)==0) {
            NetProps.SetPropInt(e,"m_nRenderMode",saved.renderMode);
            NetProps.SetPropInt(e,"m_clrRender",saved.renderColor);
        }
    }
    delete gameplay.hidden[id];
};
L4D2MCBridge.HideOwnedWeaponModel <- function(e,player,wanted) {
    if(e==null || !e.IsValid() || !NetProps.HasProp(e,"m_fEffects"))return;
    Hide(e);local id=e.GetEntityIndex(),saved=gameplay.hidden[id];
    saved.weaponOwner<-player;wanted[id]<-e;
    // The client draws an owner's active weapon in third person regardless of
    // EF_NODRAW/kRenderNone; only a transparent render colour hides it.
    if(NetProps.HasProp(e,"m_nRenderMode") && NetProps.HasProp(e,"m_clrRender")) {
        local mode=NetProps.GetPropInt(e,"m_nRenderMode"),color=NetProps.GetPropInt(e,"m_clrRender");
        if(!(mode==1 && (color&0xFF000000)==0)) {
            saved.renderMode<-mode;
            saved.renderColor<-color;
        }
        NetProps.SetPropInt(e,"m_nRenderMode",1); // kRenderTransColor
        NetProps.SetPropInt(e,"m_clrRender",color&0x00FFFFFF);
    }
};
// Render-colour-only hiding for client-predicted models; restored by RestoreHidden.
L4D2MCBridge.TransparentModel <- function(e) {
    if(e==null || !e.IsValid() || !NetProps.HasProp(e,"m_nRenderMode") || !NetProps.HasProp(e,"m_clrRender"))return;
    local id=e.GetEntityIndex();
    if(!(id in gameplay.hidden) || gameplay.hidden[id].entity!=e)gameplay.hidden[id]<-{entity=e,old=null};
    local saved=gameplay.hidden[id];
    local mode=NetProps.GetPropInt(e,"m_nRenderMode"),color=NetProps.GetPropInt(e,"m_clrRender");
    if(!(mode==1 && (color&0xFF000000)==0)) {
        saved.renderMode<-mode;
        saved.renderColor<-color;
    }
    if(mode!=1)NetProps.SetPropInt(e,"m_nRenderMode",1);
    if((color&0xFF000000)!=0)NetProps.SetPropInt(e,"m_clrRender",color&0x00FFFFFF);
};
// Ownership must lead to this survivor or an inventory weapon within four parent/owner hops.
L4D2MCBridge.OwnedAttachment <- function(attachment,player,wanted) {
    local current=attachment;
    for(local depth=0;depth<4 && current!=null && current.IsValid();depth++) {
        if(current==player || (current.GetEntityIndex() in wanted && wanted[current.GetEntityIndex()]==current))return true;
        local owner=NetProps.HasProp(current,"m_hOwnerEntity")?NetProps.GetPropEntity(current,"m_hOwnerEntity"):null;
        if(owner==player || (owner!=null && owner.IsValid() && owner.GetEntityIndex() in wanted && wanted[owner.GetEntityIndex()]==owner))return true;
        current=NetProps.HasProp(current,"m_hMoveParent")?NetProps.GetPropEntity(current,"m_hMoveParent"):
            NetProps.HasProp(current,"moveparent")?NetProps.GetPropEntity(current,"moveparent"):null;
    }
    return false;
};
L4D2MCBridge.HidePlayerWeapons <- function(player) {
    local wanted={};
    if(NetProps.HasProp(player,"m_hMyWeapons")) {
        for(local i=0;i<NetProps.GetPropArraySize(player,"m_hMyWeapons");i++) {
            local weapon=NetProps.GetPropEntityArray(player,"m_hMyWeapons",i);
            HideOwnedWeaponModel(weapon,player,wanted);
            if(weapon!=null && weapon.IsValid() && NetProps.HasProp(weapon,"m_hWeaponWorldModel"))
                HideOwnedWeaponModel(NetProps.GetPropEntity(weapon,"m_hWeaponWorldModel"),player,wanted);
        }
    }
    if(NetProps.HasProp(player,"m_hActiveWeapon"))HideOwnedWeaponModel(NetProps.GetPropEntity(player,"m_hActiveWeapon"),player,wanted);
    // predicted_viewmodel: the client toggles its EF_NODRAW while deploying, so a server
    // write to that flag makes it replay the deploy (constant draw/holster sound). Use
    // the render colour only.
    if(NetProps.HasProp(player,"m_hViewModel"))
        for(local i=0;i<NetProps.GetPropArraySize(player,"m_hViewModel");i++)
            TransparentModel(NetProps.GetPropEntityArray(player,"m_hViewModel",i));
    // Bonemerged models are sometimes separate entities rather than the
    // weapon's world-model handle. Ownership must lead to this survivor or an
    // inventory weapon; never hide map pickups or another survivor's equipment.
    // The full entity scan is the most expensive part of the 30 Hz tick. Run it four
    // times a second; between scans re-check only the attachments it found, so a
    // detached/dropped model is still restored on the very next tick.
    if(!("attachments" in gameplay))gameplay.attachments<-{};
    if(!("attachmentScanAt" in gameplay))gameplay.attachmentScanAt<--100.0;
    local now=Time();
    local scan=now-gameplay.attachmentScanAt>=0.25 || now<gameplay.attachmentScanAt;
    local cachedIds=[];foreach(id,cached in gameplay.attachments)if(cached.owner==player)cachedIds.append(id);
    if(scan) {
        gameplay.attachmentScanAt=now;
        foreach(id in cachedIds)delete gameplay.attachments[id];
        if("Entities" in getroottable())foreach(pattern in ["weapon_*","prop_dynamic","prop_dynamic_override"]) {
            local attachment=null,scanned=0;
            while((attachment=Entities.FindByClassname(attachment,pattern))!=null && ++scanned<=512) {
                if(!attachment.IsValid() || !OwnedAttachment(attachment,player,wanted))continue;
                HideOwnedWeaponModel(attachment,player,wanted);
                gameplay.attachments[attachment.GetEntityIndex()]<-{entity=attachment,owner=player};
            }
        }
    } else foreach(id in cachedIds) {
        local cached=gameplay.attachments[id];
        if(cached.entity.IsValid() && OwnedAttachment(cached.entity,player,wanted))HideOwnedWeaponModel(cached.entity,player,wanted);
        else delete gameplay.attachments[id];
    }
    // Never leave a dropped gun/quest item invisible after it leaves this survivor.
    local restore=[];
    foreach(id,saved in gameplay.hidden)if("weaponOwner" in saved && saved.weaponOwner==player && (!(id in wanted) || wanted[id]!=saved.entity))restore.append(id);
    foreach(id in restore)RestoreHidden(id);
};
L4D2MCBridge.RestoreAppearance <- function() {
    NativeUse(false);gameplay.nativeUseIntent=false;gameplay.usePulseUntil=0.0;gameplay.useGapUntil=0.0;
    gameplay.consuming=false;gameplay.consumeAt=-100.0;
    if("FlightCleanup" in this) {
        local owner=("coop" in this && coop.current!=null)?coop.current.player:
            (("survival" in this && "player" in survival)?survival.player:null);
        if(owner==null && "CoopListenHost" in this)owner=CoopListenHost();
        if(owner!=null)FlightCleanup(owner);else if(!("coop" in this))FlightCleanup();
    }
    if("SurvivalCleanup" in this)SurvivalCleanup();
    local hiddenIds=[];foreach(id,v in gameplay.hidden)hiddenIds.append(id);
    foreach(id in hiddenIds)RestoreHidden(id);
    foreach(id,v in gameplay.forced)if(v.entity.IsValid()) {
        local flags=NetProps.GetPropInt(v.entity,"m_afButtonForced");
        NetProps.SetPropInt(v.entity,"m_afButtonForced",(flags&(~33))|v.old);
    }
    gameplay.forced.clear();
    foreach(id,v in gameplay.frozen)if(v.entity.IsValid() && !v.old)
        NetProps.SetPropInt(v.entity,"m_fFlags",NetProps.GetPropInt(v.entity,"m_fFlags")&(~32));
    gameplay.frozen.clear();
    foreach(id,v in gameplay.movement)if(v.entity.IsValid())NetProps.SetPropFloat(v.entity,"m_flLaggedMovementValue",v.old);
    gameplay.movement.clear();
    foreach(id,v in gameplay.physics)if(v.proxy!=null && v.proxy.IsValid())v.proxy.Kill();
    gameplay.physics.clear();gameplay.ground.clear();
};
L4D2MCBridge.Movement <- function(player,gui,sprint) {
    local id=player.GetEntityIndex();
    if(gui) {
        local flags=NetProps.GetPropInt(player,"m_fFlags");
        if(!(id in gameplay.frozen) || gameplay.frozen[id].entity!=player)gameplay.frozen[id]<-{entity=player,old=(flags&32)!=0};
        NetProps.SetPropInt(player,"m_fFlags",flags|32);
    } else if(id in gameplay.frozen) {
        if(gameplay.frozen[id].entity==player && !gameplay.frozen[id].old)NetProps.SetPropInt(player,"m_fFlags",NetProps.GetPropInt(player,"m_fFlags")&(~32));
        delete gameplay.frozen[id];
    }
    // Retain Source acceleration/jumping; potion speed only multiplies its native movement scale.
    local factor=("effectsAt" in survival && Time()-survival.effectsAt<0.75)?survival.speed:1.0;
    if(!gui && gameplay.consuming && Time()-gameplay.consumeAt<0.75 && GameplayLease()
        && !player.IsDead() && !player.IsIncapacitated())factor*=0.2;
    if(factor!=1.0 && !gui) {
        if(id in gameplay.movement && gameplay.movement[id].entity!=player) {
            local previous=gameplay.movement[id];
            if(previous.entity.IsValid())NetProps.SetPropFloat(previous.entity,"m_flLaggedMovementValue",previous.old);
            delete gameplay.movement[id];
        }
        if(!(id in gameplay.movement))gameplay.movement[id]<-{entity=player,old=NetProps.GetPropFloat(player,"m_flLaggedMovementValue")};
        NetProps.SetPropFloat(player,"m_flLaggedMovementValue",gameplay.movement[id].old*factor);
    } else if(id in gameplay.movement) {
        local saved=gameplay.movement[id];
        if(saved.entity.IsValid())NetProps.SetPropFloat(saved.entity,"m_flLaggedMovementValue",saved.old);
        delete gameplay.movement[id];
    }
};
L4D2MCBridge.Actor <- function(e) {
    local index=e.GetEntityIndex();
    if(!(index in gameplay.actors) || gameplay.actors[index].entity!=e) {
        gameplay.actorSerial++;
        gameplay.actors[index]<-{entity=e,id=gameplay.actorSerial,seen=Time()};
    }
    gameplay.actors[index].seen=Time();return gameplay.actors[index].id;
};
L4D2MCBridge.FindActor <- function(id) {
    foreach(index,v in gameplay.actors)
        if(v.id==id && v.entity.IsValid() && Time()-v.seen<1.0)return v.entity;
    return null;
};
L4D2MCBridge.ActorJson <- function(player) {
    local out="[",n=0,candidates=[];
    foreach(kind in ["player","infected","witch"]) {
        local e=null;
        while((e=Entities.FindByClassname(e,kind))!=null) {
            if(!ActorAlive(e))continue;
            local p=e.GetOrigin(),distance=(p-player.GetOrigin()).Length();
            if("survival" in this && "golems" in survival)foreach(id,golem in survival.golems)
                if(golem.entity.IsValid() && Time()-golem.at<1){local d=(p-golem.pos).Length();if(d<distance)distance=d;}
            if(distance>1536)continue;
            candidates.append({entity=e,pos=p,distance=distance,faction=(kind=="player" && e.IsSurvivor())?0:1});
        }
    }
    // Enumeration order must not let distant corpses/hordes starve nearby targets.
    candidates.sort(function(a,b){return a.distance<b.distance?-1:a.distance>b.distance?1:0;});
    foreach(row in candidates){
        if(n>=48)break;
        local id=Actor(row.entity),p=row.pos;
        out+=format("%s[%d,%.4f,%.4f,%.4f,%d]",n++==0?"":",",id,p.x/32,p.z/32,-p.y/32,row.faction);
    }
    local dead=[];foreach(index,v in gameplay.actors)if(!v.entity.IsValid() || Time()-v.seen>2)dead.append(index);
    foreach(index in dead)delete gameplay.actors[index];
    return out+"]";
};
L4D2MCBridge.ActorAlive <- function(e) {
    return e!=null && e.IsValid() && e.GetHealth()>0 && (!NetProps.HasProp(e,"m_lifeState") || NetProps.GetPropInt(e,"m_lifeState")==0);
};
L4D2MCBridge.IsCombatTarget <- function(e) {
    return e!=null && e.IsValid() && (e.GetClassname()=="infected" || e.GetClassname()=="witch" || e.GetClassname()=="player");
};
L4D2MCBridge.CombatDamage <- function(target,amount,attacker,origin,blade=false) {
    if(!ActorAlive(target) || amount<=0)return false;
    local at=target.GetOrigin()+Vector(0,0,32),delta=at-origin,length=delta.Length();
    delta.z=0;length=delta.Length();
    local force=length>0.01?delta*(1.0/length):Vector(1,0,0);
    // Native force/hit position let Source drive blood, pain, dismemberment and
    // ragdolls. Do not SetHealth/Kill or spawn one particle entity per hit.
    force=force*((amount<300?amount:300)*18)+Vector(0,0,200);
    local before=target.GetHealth();
    if("TakeDamageEx" in target)target.TakeDamageEx(attacker,attacker,null,force,at,amount,blade?4:128);
    else target.TakeDamage(amount,blade?4:128,attacker);
    return !target.IsValid() || target.GetHealth()<before;
};
L4D2MCBridge.Raycast <- function(start,end,ignore) {
    local trace={start=start,end=end,ignore=ignore,mask=1174421507}; // MASK_SHOT, world + hitboxes.
    TraceLine(trace);return trace;
};
// Retail TraceLine omits plane normals. Estimate the slope from two local floor probes.
L4D2MCBridge.WalkableFloor <- function(t,ignore) {
    if (!("hit" in t && t.hit) || ("startsolid" in t && t.startsolid))return false;
    if("normal" in t)return t.normal.z>=0.7;
    if("plane_normal" in t)return t.plane_normal.z>=0.7;
    local slopes=[];
    foreach(offset in [Vector(4,0,0),Vector(0,4,0)]) {
        local q=t.pos+offset;
        local probe={start=q+Vector(0,0,8),end=q-Vector(0,0,8),ignore=ignore,mask=16395};TraceLine(probe);
        if (!("hit" in probe && probe.hit) || ("startsolid" in probe && probe.startsolid))return false;
        slopes.append((probe.pos.z-t.pos.z)/4);
    }
    return slopes[0]*slopes[0]+slopes[1]*slopes[1]<=1.0408; // normal.z >= .7
};
L4D2MCBridge.Usable <- function(player) {
    local p=player.EyePosition(),trace=Raycast(p,p+player.EyeAngles().Forward()*96,player);
    if(!("enthit" in trace) || trace.enthit==null)return false;
    local kind=trace.enthit.GetClassname();local name=trace.enthit.GetName();
    if(name!=null && (name.find("l4d2mc_collision_")==0 || name.find("l4d2mc_entity_")==0))return false;
    return kind.find("door")!=null || kind=="func_button" || kind.find("weapon_")==0 || kind.find("prop_physics")==0 || kind=="func_useableladder";
};
L4D2MCBridge.CarryItem <- function(kind) {
    return kind=="weapon_gascan" || kind=="weapon_cola_bottles" || kind=="weapon_gnome" || kind=="weapon_fireworkcrate" || kind.find("weapon_upgradepack_")==0;
};
L4D2MCBridge.HeldActions <- function(player,attack,use,gui) {
    if(!use && "dropLatch" in survival)survival.dropLatch=false;
    local weapon=player.GetActiveWeapon(),kind=weapon!=null?weapon.GetClassname():"";
    local carry=CarryItem(kind);
    // Checkpoint doors use their native survivor use logic to remove the bar
    // before opening. Toggle/Press inputs bypass that first stage and map outputs.
    // Only an explicit guest native-use edge owns this hold. MC mob/item clicks
    // must not open a Source door behind their non-solid Minecraft target.
    if(gui){gameplay.nativeUseIntent=false;gameplay.usePulseUntil=0.0;gameplay.useGapUntil=0.0;}
    local nativeUse=(use && gameplay.nativeUseIntent) || Time()<gameplay.usePulseUntil;
    if(!use)gameplay.nativeUseIntent=false;
    NativeUse(!gui && nativeUse && Time()>=gameplay.useGapUntil && !("dropLatch" in survival && survival.dropLatch) && (Usable(player) || carry));
    // Carry-item attack still owns only IN_ATTACK in the server fallback; USE
    // above must work even if this retail datamap property is unavailable.
    if(!NetProps.HasProp(player,"m_afButtonForced"))return;
    local id=player.GetEntityIndex(),flags=NetProps.GetPropInt(player,"m_afButtonForced");
    if(!(id in gameplay.forced) || gameplay.forced[id].entity!=player)gameplay.forced[id]<-{entity=player,old=flags&33};
    local wanted=0;
    if(!gui && attack && carry)wanted=wanted|1; // IN_ATTACK only for map carry/use items, never hidden guns.
    NetProps.SetPropInt(player,"m_afButtonForced",(flags&(~33))|gameplay.forced[id].old|wanted);
};
L4D2MCBridge.TeleportPlayer <- function(player,requested,random=false,safeFloor=false) {
    if(player.IsDead() || player.IsIncapacitated() || player.IsHangingFromLedge())return false;
    if(!random && (requested-player.GetOrigin()).Length()>4096)return false;
    local lo=NetProps.GetPropVector(player,"m_Collision.m_vecMins"),hi=NetProps.GetPropVector(player,"m_Collision.m_vecMaxs");
    for(local attempt=0;attempt<16;attempt++) {
        local p=requested;
        if(random)p=player.GetOrigin()+Vector(RandomInt(-256,256),RandomInt(-256,256),RandomInt(-64,64));
        else if(attempt>0)p=requested+Vector(RandomInt(-32,32),RandomInt(-32,32),0);
        local floor={start=p+Vector(0,0,32),end=p-Vector(0,0,256),ignore=player,mask=33570827};TraceLine(floor);
        if(!("hit" in floor) || !floor.hit || ("startsolid" in floor && floor.startsolid))continue;
        p=Vector(p.x,p.y,floor.pos.z+1);
        // Rescue candidates may move after an anchor/platform changes. Validate
        // the final floor and hull location, including every fallback offset.
        if(safeFloor && (!WalkableFloor(floor,player) || TotemHazard(player,p)))continue;
        local clear=true;
        // This retail VScript has no TraceHull. Check the standing hull with
        // central/corner vertical rays and horizontal cross sections instead.
        foreach(x in [lo.x,0,hi.x])foreach(y in [lo.y,0,hi.y]) {
            local t={start=p+Vector(x,y,1),end=p+Vector(x,y,hi.z),ignore=player,mask=33570827};TraceLine(t);
            if(("hit" in t && t.hit) || ("startsolid" in t && t.startsolid))clear=false;
        }
        foreach(z in [1,hi.z/2,hi.z]) {
            local a=p+Vector(lo.x,lo.y,z),b=p+Vector(hi.x,hi.y,z);
            local t={start=a,end=b,ignore=player,mask=33570827};TraceLine(t);
            if(("hit" in t && t.hit) || ("startsolid" in t && t.startsolid))clear=false;
            t={start=p+Vector(lo.x,hi.y,z),end=p+Vector(hi.x,lo.y,z),ignore=player,mask=33570827};TraceLine(t);
            if(("hit" in t && t.hit) || ("startsolid" in t && t.startsolid))clear=false;
        }
        if(!clear)continue;
        player.SetOrigin(p);NetProps.SetPropVector(player,"m_vecVelocity",Vector(0,0,0));
        if(NetProps.HasProp(player,"m_flFallVelocity"))NetProps.SetPropFloat(player,"m_flFallVelocity",0.0);
        printl("[L4D2MC TELEPORT] "+p);return true;
    }
    return false;
};
L4D2MCBridge.Event <- function(fields,player) {
    local serial=L4D2MCBridge.Integer(fields[1]);
    if(serial<=gameplay.lastEvent)return;
    // Consume BEFORE side effects: a failed engine call must never replay a spawn.
    gameplay.lastEvent=serial;
    local kind=fields[2];
    if(kind=="teleport" && fields.len()==6) {
        TeleportPlayer(player,Vector(Number(fields[3]),Number(fields[4]),Number(fields[5])));
    } else if(kind=="chorus" && fields.len()==3) {
        TeleportPlayer(player,player.GetOrigin(),true);
    } else if(kind=="explosion" && fields.len()==7) {
        local p=Vector(Number(fields[3]),Number(fields[4]),Number(fields[5]));
        local radius=Number(fields[6],1024);if(radius<=0)throw "invalid blast";
        local count=0,e=null;while((e=Entities.Next(e))!=null)count++;
        if(count>=1400)return;
        local name=UniqueString("l4d2mc_blast_");
        local blast=SpawnEntityFromTable("env_explosion",{origin=p,targetname=name,iMagnitude=(radius/32*40).tointeger(),iRadiusOverride=(radius*2).tointeger(),spawnflags=4|8|16|32});
        if(blast!=null) {
            if(NetProps.HasProp(blast,"m_hOwnerEntity"))NetProps.SetPropEntity(blast,"m_hOwnerEntity",player);
            EntFire(name,"Kill","",0.2,player);
            try {EntFire(name,"Explode","",0,player);}catch(error){blast.Kill();throw error;}
        }
        printl("[L4D2MC COMBAT] explosion "+p+" radius="+radius);
    } else if(kind=="pickupack" && fields.len()==4) {
        PickupAck(fields[3]);
    } else if(kind=="totemresult" && fields.len()==5) {
        TotemResult(fields,player);
    } else if(kind=="rewardack" && fields.len()==4) {
        RewardAck(fields[3]);
    } else if(kind=="link" && fields.len()==6) {
        Link(fields,player);
    } else if(kind=="meal" && fields.len()==5) {
        local amount=Number(fields[3],100),gold=Integer(fields[4]);if(amount<=0 || gold>1)throw "invalid meal";
        survival.meal+=amount;if(survival.meal>100)survival.meal=100;
        if(gold==1)AddTemporaryHealth(player,20);
    } else if(kind=="heal" && fields.len()==4) {
        local amount=Number(fields[3],100);
        if(amount<=0)throw "invalid food heal";
        if(player.GetHealth()>0 && !player.IsIncapacitated() && !player.IsHangingFromLedge()) {
            Heal(player,amount);
            printl("[L4D2MC FOOD] health="+player.GetHealth());
        }
    } else if(kind=="ignite" && fields.len()==6) {
        IgniteGround(fields,player);
    } else if(kind=="melee" && (fields.len()>=5 && fields.len()<=7)) {
        if(fields.len()>=6 && Integer(fields[5])==1)CutTongue(player);
        local damage=Number(fields[3],1500),range=Number(fields[4],256);
        if(damage<0 || range<=0)throw "invalid melee";
        local p=player.EyePosition(),forward=player.EyeAngles().Forward();
        local tier=fields.len()==7?Integer(fields[6]):0;if(tier>2)throw "invalid sword tier";
        local blade=fields.len()>=6 && Integer(fields[5])==1;
        if(blade) {
            if("swordAt" in survival && Time()-survival.swordAt<0.35)return;
            survival.swordAt<-Time();
        }
        if(tier>0){local extra=damage/15-(tier==2?8:7);if(extra<0)extra=0;damage=(tier==2?220.0:180.0)+extra*15;}
        local targets=[],direct=Raycast(p,p+forward*range,player);
        if("enthit" in direct && IsCombatTarget(direct.enthit))targets.append(direct.enthit);
        if(blade)foreach(cls in ["infected","player","witch"]) {
            local e=null;
            while((e=Entities.FindByClassnameWithin(e,cls,p,range+32))!=null && targets.len()<8) {
                if(e==player || e.GetHealth()<=0 || (cls=="player" && e.IsSurvivor()) || targets.find(e)!=null)continue;
                local delta=e.GetOrigin()+Vector(0,0,32)-p,d=delta.Length();
                if(d<0.01 || d>range || (delta.x*forward.x+delta.y*forward.y+delta.z*forward.z)/d<0.5)continue;
                local t=Raycast(p,p+delta,player);
                if("hit" in t && t.hit && (!("enthit" in t) || t.enthit!=e))continue;
                targets.append(e);
            }
        }
        local hits=0;
        foreach(e in targets) {
            if(e==player || (e.GetClassname()=="player" && e.IsSurvivor()))continue;
            if(!ActorAlive(e))continue;
            local hit=tier>0 && e.GetClassname()=="infected"?e.GetHealth()+1.0:damage;
            if(CombatDamage(e,hit,player,p,blade))hits++;
        }
        if(hits>0 && "Reply" in this)Reply(format("\"t\":\"attacksound\",\"kind\":\"%s\"",blade && hits>1?"sweep":damage>=60?"strong":"weak"));
    } else if(kind=="mobhit" && (fields.len()==9 || fields.len()==10)) {
        local id=Integer(fields[3]),damage=Number(fields[4],500);
        local from=Vector(Number(fields[5]),Number(fields[6]),Number(fields[7]));
        local target=FindActor(id);
        if(ActorAlive(target) && damage>=0 && (target.GetOrigin()-from).Length()<512) {
            if(fields.len()==10 && fields[9]=="iron_golem" && !(target.GetClassname()=="player" && target.IsSurvivor())) {
                if(target.GetClassname()=="infected"){local lethal=target.GetHealth()+1;if(damage<lethal)damage=lethal;}
                else if(damage<180)damage=180;
            }
            local attacker=Integer(fields[8]),ignore=attacker in gameplay.physics?gameplay.physics[attacker].proxy:null;
            local trace=Raycast(from+Vector(0,0,24),target.GetOrigin()+Vector(0,0,32),ignore);
            if(!("hit" in trace) || !trace.hit || ("enthit" in trace && trace.enthit==target)) {
                CombatDamage(target,damage,null,from,false);
                printl("[L4D2MC COMBAT] mobhit actor="+id+" damage="+damage);
            }
        }
    } else if(kind=="replyack" && fields.len()==4) {
        local id=Integer(fields[3]);
        if(id in gameplay.replies)delete gameplay.replies[id];
    } else if(kind=="interact" && fields.len()==3) {
        local held=player.GetActiveWeapon();
        // Only carried props drop; the hidden melee is the converted sidearm, not a carry item.
        if(held!=null && CarryItem(held.GetClassname())) {
            player.DropItem(held.GetClassname());survival.dropLatch<-true;
            NativeUse(false);gameplay.nativeUseIntent=false;gameplay.usePulseUntil=0.0;gameplay.useGapUntil=0.0;return;
        }
        // HeldActions forwards the actual IN_USE press/hold. Never force an
        // entity input: locked doors, checkpoint bars and button events belong
        // to the campaign's use implementation.
        if(Usable(player)) {
            // A second quick click needs an actual released usercmd between
            // presses (e.g. remove checkpoint bar, then open the same door).
            local again=gameplay.nativeUseDown;NativeUse(false);
            gameplay.useGapUntil=again?Time()+0.04:Time();
            gameplay.nativeUseIntent=true;gameplay.usePulseUntil=gameplay.useGapUntil+0.12;
        }
    } else throw "invalid event";
};
L4D2MCBridge.Projectile <- function(fields,player) {
    if(fields.len()!=6 && fields.len()!=7 && fields.len()!=10)throw "invalid projectile";
    local id=Integer(fields[1]);
    local p=Vector(Number(fields[3]),Number(fields[4]),Number(fields[5]));
    local launch=fields.len()==10 && !(id in gameplay.projectiles);
    if(launch) {
        // The mailbox keeps the newest snapshot. Preserve the actual launch
        // point so even a fast pearl's first segment cannot pass through a wall.
        local origin=Vector(Number(fields[7]),Number(fields[8]),Number(fields[9]));
        gameplay.projectiles[id]<-{pos=origin,at=Time(),hit=false};
    }
    if(id in gameplay.projectiles) {
        local before=gameplay.projectiles[id];
        local distance=(p-before.pos).Length();
        if(!before.hit && Time()-before.at<0.5 && distance>0.001 && distance<(launch?4096:512)) {
            local trace=Raycast(before.pos,p,player);
            if("hit" in trace && trace.hit) {
                local own="enthit" in trace && trace.enthit!=null &&
                    (trace.enthit.GetName().find("l4d2mc_collision_")==0 || trace.enthit.GetName().find("l4d2mc_entity_")==0);
                if(!own && !before.hit) {
                    if(fields[2]=="ender_pearl") {
                        local back=before.pos-p;
                        if(back.Length()>0.01)back=back*(24.0/back.Length());
                        if(TeleportPlayer(player,trace.pos+back))player.TakeDamage(5,0,null);
                    } else if(fields[2]!="thrown" && "enthit" in trace && IsCombatTarget(trace.enthit)) {
                        // Thrown potions/snowballs/eggs only break here; Minecraft applies their effect.
                        local damage=fields.len()>=7?Number(fields[6],1500):(fields[2]=="firework"?80:60);
                        if(damage<0)throw "invalid projectile damage";
                        trace.enthit.TakeDamage(damage,2,player);
                    }
                    local at=trace.pos;
                    gameplay.replies[id]<-format("{\"t\":\"projhit\",\"rid\":%d,\"id\":%d,\"pos\":[%.4f,%.4f,%.4f],\"stick\":true}",id,id,at.x/32,at.z/32,-at.y/32);
                    before.hit=true;
                }
            }
        }
        before.pos=p;before.at=Time();
    } else gameplay.projectiles[id]<-{pos=p,at=Time(),hit=false};
};
L4D2MCBridge.Physics <- function(fields,player) {
    if(fields.len()!=8)throw "invalid physics row";
    local id=Integer(fields[1]),p=Vector(Number(fields[2]),Number(fields[3]),Number(fields[4]));
    local width=Number(fields[5],512),height=Number(fields[6],512),mob=Integer(fields[7]);
    if(width<=0 || height<=0 || mob>1)throw "invalid physics dimensions";
    if((p-player.GetOrigin()).Length()>2048)return; // Out of range is ordinary during movement/teleports.
    if(!(id in gameplay.physics))gameplay.physics[id]<-{proxy=null,pos=p,width=width,height=height,at=Time()};
    local v=gameplay.physics[id];v.pos=p;v.width=width;v.height=height;v.at=Time();
    v.mob<-mob;
    // Mobs have no Source collision prop: they remain visible/attackable in
    // Minecraft while Source survivors can walk through them without trapping.
    if(v.proxy!=null){if(v.proxy.IsValid())v.proxy.Kill();v.proxy=null;}

};
L4D2MCBridge.RecoverMob <- function(id,v) {
    if("recoverAt" in v && Time()<v.recoverAt)return;v.recoverAt<-Time()+1;
    local candidates=[];
    if("safe" in v && (v.safe-v.pos).Length()<192)candidates.append(v.safe);
    foreach(dir in [Vector(1,0,0),Vector(-1,0,0),Vector(0,1,0),Vector(0,-1,0)])candidates.append(v.pos+dir*(v.width+48)+Vector(0,0,48));
    local radius=v.width/2;
    foreach(p in candidates) {
        local floor={start=p+Vector(0,0,16),end=p-Vector(0,0,128),ignore=null,mask=16395};TraceLine(floor);
        if(("startsolid" in floor && floor.startsolid) || !("hit" in floor && floor.hit))continue;
        local at=floor.pos+Vector(0,0,1),clear=true;
        foreach(x in [-radius,0,radius])foreach(y in [-radius,0,radius]) {
            local t={start=at+Vector(x,y,1),end=at+Vector(x,y,v.height+2),ignore=null,mask=16395};TraceLine(t);
            if(("startsolid" in t && t.startsolid) || ("hit" in t && t.hit)){clear=false;break;}
        }
        if(!clear)continue;
        foreach(h in [v.height/2,v.height-1])foreach(dir in [Vector(1,0,0),Vector(0,1,0)]) {
            local t={start=at+Vector(0,0,h)-dir*radius,end=at+Vector(0,0,h)+dir*radius,ignore=null,mask=16395};TraceLine(t);
            if(("startsolid" in t && t.startsolid) || ("hit" in t && t.hit)){clear=false;break;}
        }
        if(clear){Reply(format("\"t\":\"mobpos\",\"id\":%d,\"p\":[%.4f,%.4f,%.4f]",id,at.x/32,at.z/32,-at.y/32));return;}
    }
};
L4D2MCBridge.GroundPhysics <- function() {
    gameplay.ground.clear();local list=[],stale=[];
    foreach(id,v in gameplay.physics) {
        if(Time()-v.at>0.75) {if(v.proxy!=null && v.proxy.IsValid())v.proxy.Kill();stale.append(id);}
        else list.append(id);
    }
    foreach(id in stale)delete gameplay.physics[id];
    if(list.len()==0)return;
    // Minecraft already handles its own blocks/entities. Their Source collision
    // stand-ins must not become false terrain (especially the primed TNT's old cube).
    local masked=[];
    foreach(key,block in blocks)if(block.IsValid() && NetProps.HasProp(block,"m_Collision.m_usSolidFlags")) {
        local flags=NetProps.GetPropInt(block,"m_Collision.m_usSolidFlags");masked.append([block,flags]);
        NetProps.SetPropInt(block,"m_Collision.m_usSolidFlags",flags|4);
    }
    foreach(key,value in gameplay.physics)if(value.proxy!=null && value.proxy.IsValid() && NetProps.HasProp(value.proxy,"m_Collision.m_usSolidFlags")) {
        local flags=NetProps.GetPropInt(value.proxy,"m_Collision.m_usSolidFlags");masked.append([value.proxy,flags]);
        NetProps.SetPropInt(value.proxy,"m_Collision.m_usSolidFlags",flags|4);
    }
    local restore=function(){foreach(v in masked)if(v[0].IsValid())NetProps.SetPropInt(v[0],"m_Collision.m_usSolidFlags",v[1]);};
    // Bound wider body probes to three entities per think (each body probe is ~50 traces).
    try { for(local i=0;i<3 && i<list.len();i++) {
        local index=(gameplay.physIndex+i)%list.len(),id=list[index],v=gameplay.physics[id];
        local p=v.pos,ignore=v.proxy;
        local trace={start=p+Vector(0,0,8),end=p-Vector(0,0,512),ignore=ignore,mask=16395};
        TraceLine(trace);
        if("startsolid" in trace && trace.startsolid) {
            trace={start=p+Vector(0,0,32),end=p-Vector(0,0,512),ignore=ignore,mask=16395};TraceLine(trace);
            if(("startsolid" in trace && trace.startsolid) || ("hit" in trace && trace.hit && trace.pos.z>p.z+16))continue;
        }
        local floor=("hit" in trace && trace.hit && !("startsolid" in trace && trace.startsolid))?1:0;
        local y=floor?trace.pos.z/32:p.z/32;
        // A TNT/item may spawn slightly inside a sloping floor after grid
        // placement. Probe its hull above the verified surface; otherwise every
        // side ray starts solid and we never send the floor that would lift it.
        // Airborne entities retain their real position and gravity.
        if(floor && "mob" in v && v.mob==0 && trace.pos.z>p.z && trace.pos.z-p.z<=16)
            p=Vector(p.x,p.y,trace.pos.z+0.5);
        local xmin=-4096.0,xmax=4096.0,zmin=-4096.0,zmax=4096.0;
        // Probe the body's width and three heights, far enough ahead for
        // round-robin/network delay. A midpoint-only ray misses doors/corners.
        local radius=v.width/2,side=radius>1?radius-1:0,distance=radius+96;
        local low=v.height/4<4?v.height/4:4; // Feet/bumpers and low ledges, same probe budget.
        local tops=[p.z/32+8,p.z/32+8,p.z/32+8,p.z/32+8];
        local embedded=false,escapeAxis=-1,escapeDistance=radius+1;
        foreach(axis,dir in [Vector(-1,0,0),Vector(1,0,0),Vector(0,1,0),Vector(0,-1,0)]) {
            foreach(h in [low,v.height/2,v.height-1])foreach(offset in [-side,0,side]) {
                local across=axis<2?Vector(0,offset,0):Vector(offset,0,0);
                local start=p+Vector(0,0,h)+across;
                local t={start=start,end=start+dir*distance,ignore=ignore,mask=16395};TraceLine(t);
                if("startsolid" in t && t.startsolid) {
                    embedded=true;
                    // Startsolid says nothing about direction. Probe back from
                    // outside; the nearest exit within half a body width permits
                    // depenetration, rather than caging all four directions.
                    local reverse={start=start+dir*distance,end=start,ignore=ignore,mask=16395};TraceLine(reverse);
                    if(!("startsolid" in reverse && reverse.startsolid) && "hit" in reverse && reverse.hit) {
                        local gap=(reverse.pos-start).Length();
                        if(gap<escapeDistance){escapeDistance=gap;escapeAxis=axis;}
                    }
                } else if("hit" in t && t.hit) {
                    if(axis==0){local edge=t.pos.x/32;if(edge>xmin)xmin=edge;}
                    else if(axis==1){local edge=t.pos.x/32;if(edge<xmax)xmax=edge;}
                    else if(axis==2){local edge=-t.pos.y/32;if(edge>zmin)zmin=edge;}
                    else {local edge=-t.pos.y/32;if(edge<zmax)zmax=edge;}
                }
            }
        }
        // Resolve a one-block ledge, retaining tall walls when any probe is ambiguous.
        if(!embedded)foreach(axis,dir in [Vector(-1,0,0),Vector(1,0,0),Vector(0,1,0),Vector(0,-1,0)]) {
            local edge=axis==0?xmin:axis==1?xmax:axis==2?zmin:zmax;
            if(abs(edge)>2048)continue;
            local at=axis<2?Vector(edge*32,p.y,p.z):Vector(p.x,-edge*32,p.z);at+=dir*2;
            local top={start=at+Vector(0,0,40),end=at-Vector(0,0,2),ignore=ignore,mask=16395};TraceLine(top);
            if(("startsolid" in top && top.startsolid) || !("hit" in top && top.hit))continue;
            if(!WalkableFloor(top,ignore) || top.pos.z<=p.z+2 || top.pos.z>p.z+32)continue;
            local clear=true;
            foreach(offset in [-side,0,side]) {
                local across=axis<2?Vector(0,offset,0):Vector(offset,0,0);
                local start=p+Vector(0,0,40)+across;
                local t={start=start,end=start+dir*distance,ignore=ignore,mask=16395};TraceLine(t);
                if(("startsolid" in t && t.startsolid) || ("hit" in t && t.hit)){clear=false;break;}
                local roof={start=at+Vector(0,0,40)+across,end=at+Vector(0,0,40+v.height)+across,ignore=ignore,mask=16395};TraceLine(roof);
                if(("startsolid" in roof && roof.startsolid) || ("hit" in roof && roof.hit)){clear=false;break;}
            }
            if(clear)tops[axis]=top.pos.z/32;
        }
        if(embedded) {
            // Deep/ambiguous intersections retain the previous support until its
            // lease expires. Do not publish an unbounded path through the brush.
            if(escapeAxis<0){RecoverMob(id,v);continue;}
            // Preserve other samples' real wall hits. A shallow exit at one
            // corner must not erase the neighbouring brush at another corner.
            local clearance=escapeAxis==0?p.x-xmin*32-radius:
                escapeAxis==1?xmax*32-p.x-radius:
                escapeAxis==2?-zmin*32-p.y-radius:p.y+zmax*32-radius;
            if(clearance<=escapeDistance+1)continue;
            // Only the selected exit stays open, up to its real traced wall.
            // The other three planes prevent increasing the penetration.
            if(escapeAxis!=0)xmin=(p.x-radius)/32;
            if(escapeAxis!=1)xmax=(p.x+radius)/32;
            if(escapeAxis!=2)zmin=-(p.y+radius)/32;
            if(escapeAxis!=3)zmax=-(p.y-radius)/32;
        }
        if(!embedded && floor)v.safe<-Vector(p.x,p.y,y*32);
        gameplay.ground.append(format("[%d,%.4f,%.4f,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f]",id,p.x/32,-p.y/32,floor,y,xmin,xmax,zmin,zmax,tops[0],tops[1],tops[2],tops[3]));
    }
    } catch(error){restore();throw error;}
    restore();
    gameplay.physIndex=(gameplay.physIndex+3)%list.len();
};
L4D2MCBridge.GameplayLease <- function() { return gameplay.armed && Time()-gameplay.at<=0.5; };
L4D2MCBridge.ReadGameplay <- function(player,path="l4d2mc_gameplay.txt") {
    local text=FileToString(path);
    if(text==null || text.len()>32768)return GameplayLease();
    local lines=split(text,"\r\n");if(lines.len()<1 || lines.len()>384)return GameplayLease();
    local header=split(lines[0]," ");
    if(header.len()!=9 || !CompleteMailbox(lines,header[3]))return GameplayLease();
    if(header[1]!=Director.GetMapName() || header[8]!=epoch.tostring())return false;
    if(header[2]=="0" && TotemPendingFor(player)) {
        NativeUse(false);gameplay.nativeUseIntent=false;gameplay.usePulseUntil=0.0;gameplay.useGapUntil=0.0;
        gameplay.consuming=false;gameplay.consumeAt=-100.0;if("FlightCleanup" in this)FlightCleanup(player);
        if(header[0]!=gameplay.generation){gameplay.generation=header[0];gameplay.lastEvent=0;gameplay.content=null;gameplay.armed=false;}
        // A spectating/dead frame permits only the existing durable rescue.
        for(local i=1;i<lines.len()-1;i++) {
            local f=split(lines[i]," ");
            if(f.len()>=3 && f[0]=="event" && (f[2]=="totemresult" || f[2]=="replyack"))
                try{Event(f,player);}catch(error){printl("[L4D2MC TOTEM] "+error);}
            else if(f.len()==2 && f[0]=="replyack")try{local id=Integer(f[1]);if(id in gameplay.replies)delete gameplay.replies[id];}catch(error){printl("[L4D2MC ACK] "+error);}
        }
        TotemTick(player);return true;
    }
    if(header[2]!="1")return false;
    if(header[0]!=gameplay.generation) {
        if("FlightCleanup" in this)FlightCleanup(player);gameplay.consuming=false;gameplay.consumeAt=-100.0;
        gameplay.generation=header[0];gameplay.lastEvent=0;gameplay.projectiles.clear();gameplay.replies.clear();gameplay.armed=false;gameplay.content=null;
    }
    if(gameplay.content==null) {
        // A retained mailbox is not evidence of a live session. Baseline old
        // events, then wait for another heartbeat before enabling gameplay.
        foreach(line in lines) {
            local f=split(line," ");
            if(f.len()>=3 && f[0]=="event")try{local n=Integer(f[1]);if(n>gameplay.lastEvent)gameplay.lastEvent=n;}catch(error){}
        }
        gameplay.content=text;return false;
    }
    if(text!=gameplay.content){gameplay.content=text;gameplay.at=Time();gameplay.armed=true;}
    if(!gameplay.armed)return false;
    if(Time()-gameplay.at>0.5)return false;
    survival.fireZones.clear();
    gameplay.consuming=false;gameplay.consumeAt=-100.0;
    for(local i=1;i<lines.len()-1;i++) {
        local f=split(lines[i]," ");
        if(f.len()>0 && f[0]=="event")try{Event(f,player);}catch(error){printl("[L4D2MC EVENT] "+error);}
        else if(f.len()==2 && f[0]=="replyack")try{local id=Integer(f[1]);if(id in gameplay.replies)delete gameplay.replies[id];}catch(error){printl("[L4D2MC ACK] "+error);}
        else if(f.len()>0 && f[0]=="golem")try{GolemTarget(f,player);}catch(error){printl("[L4D2MC GOLEM] "+error);}
        else if(f.len()>0 && f[0]=="nav")try{NavRequest(f,player);}catch(error){printl("[L4D2MC NAV] "+error);}
        else if(f.len()>0 && f[0]=="projectile")try{Projectile(f,player);}catch(error){printl("[L4D2MC PROJECTILE] "+error);}
        else if(f.len()>0 && f[0]=="signal")try{Signal(f,player);}catch(error){printl("[L4D2MC SIGNAL] "+error);}
        else if(f.len()>0 && f[0]=="protection")try{ProtectionEquipment(f);}catch(error){printl("[L4D2MC PROTECTION] "+error);}
        else if(f.len()>0 && f[0]=="effects")try{Effects(f);}catch(error){printl("[L4D2MC EFFECTS] "+error);}
        else if(f.len()>0 && f[0]=="fire")try{FireZone(f,player);}catch(error){printl("[L4D2MC FIRE] "+error);}
        else if(f.len()>0 && f[0]=="totemheld")try{TotemHeld(f);}catch(error){printl("[L4D2MC TOTEM] "+error);}
        else if(f.len()==5 && f[0]=="flight")try{Flight(f,player);}catch(error){printl("[L4D2MC FLIGHT] "+error);}
        else if(f.len()==2 && f[0]=="consume")try{Consume(f);}catch(error){printl("[L4D2MC CONSUME] "+error);}
        else if(f.len()>0 && f[0]=="equipment")try{Equipment(f,player);}catch(error){printl("[L4D2MC EQUIPMENT] "+error);}
        else if(f.len()>0 && f[0]=="physics")try{Physics(f,player);}catch(error){printl("[L4D2MC PHYSICS] "+error);}
    }
    HeldActions(player,header.len()==9 && header[6]=="1",header.len()==9 && header[7]=="1",header[4]=="1");
    HideSurvivor(player);
    Movement(player,header[4]=="1",header[5]=="1");
    if("FlightTick" in this)FlightTick(player);
    GroundPhysics();
    SurvivalTick(player);
    try{NavTick();}catch(error){printl("[L4D2MC NAV] "+error);navigation.jobs.clear();}
    HidePlayerWeapons(player);
    local stale=[];foreach(id,v in gameplay.projectiles)if(Time()-v.at>1)stale.append(id);
    foreach(id in stale)delete gameplay.projectiles[id];
    return true;
};
