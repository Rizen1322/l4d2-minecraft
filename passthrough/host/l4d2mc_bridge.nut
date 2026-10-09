// Local, listen-server prototype. No movement ownership changes.
::L4D2MCPreviousGameplay <- null;
if ("L4D2MCBridge" in getroottable()) {
    if("gameplay" in L4D2MCBridge) {
        L4D2MCBridge.RestoreAppearance();
        L4D2MCPreviousGameplay=L4D2MCBridge.gameplay;
    }
    if (L4D2MCBridge.anchor != null && L4D2MCBridge.anchor.IsValid())
        L4D2MCBridge.anchor.Kill();
    if ("blocks" in L4D2MCBridge)
        foreach (key, block in L4D2MCBridge.blocks)
            if (block.IsValid()) block.Kill();
}
// Old saved sessions may retain an invisible mob collider after its table
// disappeared. Remove only this mod's numbered cube stand-ins, never map props.
local staleMobProps=[],staleMobProp=null;
foreach(staleClass in ["prop_dynamic","prop_dynamic_override"]) {
    staleMobProp=null;
    while((staleMobProp=Entities.FindByClassname(staleMobProp,staleClass))!=null) {
    local name=staleMobProp.GetName(),prefix="l4d2mc_entity_";
    if(name==null || name.find(prefix)!=0 || name.len()<=prefix.len() || staleMobProp.GetModelName()!="models/l4d2mc/cube.mdl")continue;
    local owned=true;
    for(local i=prefix.len();i<name.len();i++)if(name[i]<48 || name[i]>57)owned=false;
    if(owned)staleMobProps.append(staleMobProp);
    }
}
foreach(prop in staleMobProps)if(prop.IsValid())prop.Kill();
PrecacheModel("models/l4d2mc/cube.mdl");
::L4D2MCBridge <- { frame = 0, epoch=RandomInt(1,2000000000), anchor = null, blocks = {}, collisionSequence = "", collisionAt = 0, collisionChangedAt = -100 };
IncludeScript("l4d2mc_gameplay");
IncludeScript("l4d2mc_survival");
IncludeScript("l4d2mc_navigation");
L4D2MCBridge.ClearCollision <- function() {
    foreach (key, block in blocks) if (block.IsValid()) block.Kill();
    blocks.clear();
};
L4D2MCBridge.SyncCollision <- function() {
    local text = FileToString("l4d2mc_collision.txt");
    if (text == null || text.len() > 32768) return;
    local lines = split(text, "\n\r");
    if (lines.len() < 1 || lines.len() > 513) return;
    local header = split(lines[0], " ");
    if (header.len() != 2 || header[1] != Director.GetMapName() || header[0] == collisionSequence) return;
    local wanted = {};
    foreach (line in lines.slice(1)) {
        local fields = split(line, " ");
        if (fields.len() != 3) return;
        local values = [];
        foreach (f in fields) {
            // Reject any token other than a decimal integer, before conversion.
            for (local i=0; i<f.len(); ++i)
                if (!(f[i]>=48 && f[i]<=57) && !(i==0 && f[i]==45)) return;
            local n = f.tointeger();
            if (n < -1023 || n > 1023) return;
            values.append(n);
        }
        local key = format("%d %d %d", values[0],values[1],values[2]);
        // Minecraft cell (x,y,z) maps to Source cube centre (x,-z,y).
        wanted[key] <- Vector((values[0]+0.5)*32, -(values[2]+0.5)*32, (values[1]+0.5)*32);
    }
    collisionSequence = header[0];
    collisionChangedAt = Time();
    local remove = [];
    foreach (key, block in blocks)
        if (!(key in wanted)) { if (block.IsValid()) block.Kill(); remove.append(key); }
    foreach (key in remove) delete blocks[key];
    local count = 0, entity = null;
    while ((entity = Entities.Next(entity)) != null) ++count;
    foreach (key, at in wanted) {
        if (key in blocks) {
            if(blocks[key].IsValid())continue;
            delete blocks[key];
        }
        if(count >= 1400)continue;
        // Do not enclose a survivor or special infected in a new collision prop.
        local occupied = false;
        entity = null;
        while ((entity = Entities.FindByClassname(entity,"player")) != null) {
            if (entity.IsDead()) continue;
            local lo=entity.GetOrigin()+NetProps.GetPropVector(entity,"m_Collision.m_vecMins");
            local hi=entity.GetOrigin()+NetProps.GetPropVector(entity,"m_Collision.m_vecMaxs");
            if (at.x-16<hi.x && at.x+16>lo.x && at.y-16<hi.y && at.y+16>lo.y && at.z-16<hi.z && at.z+16>lo.z) occupied=true;
        }
        if (occupied) continue;
        local block=SpawnEntityFromTable("prop_dynamic_override", {
            model="models/l4d2mc/cube.mdl",origin=at,angles=Vector(0,0,0),solid=6,
            renderamt=0,rendermode=10,disableshadows=1,DisableBoneFollowers=1,
            targetname=UniqueString("l4d2mc_collision_")
        });
        if (block != null) { blocks[key] <- block; ++count; }
    }
};
L4D2MCBridge.anchor = SpawnEntityFromTable("info_target", { targetname = "l4d2mc_bridge" });
L4D2MCBridge.anchor.ValidateScriptScope();
L4D2MCBridge.anchor.GetScriptScope().BridgeThink <- function() {
    if (Time() - L4D2MCBridge.collisionChangedAt > 3.0)
        L4D2MCBridge.ClearCollision();
    local player = null;
    local entity = null;
    while ((entity = Entities.FindByClassname(entity, "player")) != null) {
        if (!IsPlayerABot(entity) && entity.IsSurvivor() && !entity.IsDead()) {
            player = entity; break;
        }
    }
    if (player == null) {L4D2MCBridge.RestoreAppearance();return 0.033;}
    if(!L4D2MCBridge.ReadGameplay(player))L4D2MCBridge.RestoreAppearance();
    local p = player.EyePosition();
    local feet = player.GetOrigin();
    local a = player.EyeAngles();
    local fov = 90;
    if (NetProps.HasProp(player, "m_iFOV")) {
        local value = NetProps.GetPropInt(player, "m_iFOV");
        if (value > 10 && value < 170) fov = value;
    }
    local forward = player.EyeAngles().Forward();
    local trace = {start=p, end=p+forward*160, ignore=player, mask=33570827}; // MASK_SOLID, excludes hitboxes
    TraceLine(trace);
    local surface = "null", normal = "null";
    if ("hit" in trace && trace.hit && !("startsolid" in trace && trace.startsolid)) {
        local own = false;
        if ("enthit" in trace && trace.enthit != null) {
            local name=trace.enthit.GetName();
            own = name.find("l4d2mc_collision_") != null;
            local cls=trace.enthit.GetClassname();
            if (cls=="player" || cls=="infected" || cls=="witch") own=true;
        }
        if (!own) {
            local n = Vector(0,0,0);
            if ("plane_normal" in trace) n=trace.plane_normal;
            else {
                // L4D2's older VScript does not expose trace planes. Probe the
                // six axes immediately outside the hit and use the closest face.
                local outside=trace.pos-forward*0.5, best=3.0;
                foreach (axis in [Vector(1,0,0),Vector(-1,0,0),Vector(0,1,0),Vector(0,-1,0),Vector(0,0,1),Vector(0,0,-1)]) {
                    local probe={start=outside,end=outside-axis*2,ignore=player,mask=33570827};
                    TraceLine(probe);
                    if ("hit" in probe && probe.hit && probe.fraction<best) {best=probe.fraction;n=axis;}
                }
            }
            if (n.Length()>0.5) {
                surface=format("[%.6f,%.6f,%.6f]",trace.pos.x,trace.pos.y,trace.pos.z);
                normal=format("[%.6f,%.6f,%.6f]",n.x,n.y,n.z);
            }
        }
    }
    local pinned=false;
    foreach(prop in ["m_pounceAttacker","m_jockeyAttacker","m_tongueOwner","m_carryAttacker","m_pummelAttacker"])
        if(NetProps.HasProp(player,prop) && NetProps.GetPropEntity(player,prop)!=null)pinned=true;
    local visible=true;
    if(NetProps.HasProp(player,"m_hViewEntity")) {
        local view=NetProps.GetPropEntity(player,"m_hViewEntity");
        if(view!=null && view!=player && !pinned)visible=false;
    }
    if((NetProps.GetPropInt(player,"m_fFlags")&32)!=0) {
        local id=player.GetEntityIndex();
        local own=id in L4D2MCBridge.gameplay.frozen && L4D2MCBridge.gameplay.frozen[id].entity==player && !L4D2MCBridge.gameplay.frozen[id].old;
        if(!own && !pinned)visible=false;
    }
    local burning=(NetProps.GetPropInt(player,"m_fFlags")&134217728)!=0;
    local flame=NetProps.HasProp(player,"m_hEffectEntity")?NetProps.GetPropEntity(player,"m_hEffectEntity"):null;
    if(flame!=null && flame.IsValid() && flame.GetClassname()=="entityflame")burning=true;
    local carried=player.GetActiveWeapon();
    local carrying=carried!=null && L4D2MCBridge.CarryItem(carried.GetClassname());
    L4D2MCBridge.frame++;
    local data = format("{\"v\":1,\"f\":%d,\"map\":\"%s\",\"p\":[%.6f,%.6f,%.6f],\"feet\":[%.6f,%.6f,%.6f],\"r\":[%.6f,%.6f,%.6f],\"hfov\":%d,\"hit\":%s,\"normal\":%s,\"buttons\":%d}",
        L4D2MCBridge.frame, Director.GetMapName(), p.x,p.y,p.z,feet.x,feet.y,feet.z,a.y,a.x,a.z,fov,surface,normal,player.GetButtonMask());
    data=data.slice(0,data.len()-1)+",\"burning\":"+(burning?"true":"false")+"}";
    data=data.slice(0,data.len()-1)+",\"carrying\":"+(carrying?"true":"false")+"}";
    data=data.slice(0,data.len()-1)+",\"pinned\":"+(pinned?"true":"false")+"}";
    data=data.slice(0,data.len()-1)+format(",\"epoch\":%d}",L4D2MCBridge.epoch);
    local maxHp=NetProps.HasProp(player,"m_iMaxHealth")?NetProps.GetPropInt(player,"m_iMaxHealth"):100;
    local temporary=NetProps.HasProp(player,"m_healthBuffer")?NetProps.GetPropFloat(player,"m_healthBuffer"):0.0;
    if(NetProps.HasProp(player,"m_healthBufferTime")) {
        local decay=Convars.GetFloat("pain_pills_decay_rate");if(decay!=null)temporary-=(Time()-NetProps.GetPropFloat(player,"m_healthBufferTime"))*decay;
        if(temporary<0)temporary=0;
    }
    data=data.slice(0,data.len()-1)+format(",\"health\":[%d,%.3f,%d,%s]}",player.GetHealth(),temporary,maxHp,player.IsIncapacitated() || player.GetHealth()<=0?"true":"false");
    data=data.slice(0,data.len()-1)+",\"visible\":"+(visible?"true":"false")+",\"nativeuse\":false"+",\"usable\":"+(L4D2MCBridge.Usable(player)?"true":"false")+",\"actors\":"+L4D2MCBridge.ActorJson(player)+",\"wheel\":"+L4D2MCBridge.gameplay.wheel+",\"replies\":[";
    local replyCount=0;foreach(id,reply in L4D2MCBridge.gameplay.replies)data+=(replyCount++==0?"":",")+reply;
    data+= "],\"physground\":[";
    for(local i=0;i<L4D2MCBridge.gameplay.ground.len();i++)data+=(i==0?"":",")+L4D2MCBridge.gameplay.ground[i];
    data+="]}";
    StringToFile("l4d2mc_pose.txt", data);
    if (Time() >= L4D2MCBridge.collisionAt) {
        L4D2MCBridge.collisionAt = Time() + 0.25;
        try { L4D2MCBridge.SyncCollision(); } catch (error) { printl("[L4D2MC COLLISION] " + error); }
    }
    return 0.033;
};
AddThinkToEnt(L4D2MCBridge.anchor, "BridgeThink");
printl("[L4D2MC BRIDGE] exporting local survivor camera");
