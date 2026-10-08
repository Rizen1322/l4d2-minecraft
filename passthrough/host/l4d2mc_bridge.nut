// Local, listen-server prototype. No movement ownership changes.
if ("L4D2MCBridge" in getroottable()) {
    if (L4D2MCBridge.anchor != null && L4D2MCBridge.anchor.IsValid())
        L4D2MCBridge.anchor.Kill();
    if ("blocks" in L4D2MCBridge)
        foreach (key, block in L4D2MCBridge.blocks)
            if (block.IsValid()) block.Kill();
}
PrecacheModel("models/l4d2mc/cube.mdl");
::L4D2MCBridge <- { frame = 0, anchor = null, blocks = {}, collisionSequence = "", collisionAt = 0, collisionChangedAt = -100 };
L4D2MCBridge.ClearCollision <- function() {
    foreach (key, block in blocks) if (block.IsValid()) block.Kill();
    blocks.clear();
};
L4D2MCBridge.SyncCollision <- function() {
    local text = FileToString("l4d2mc_collision.txt");
    if (text == null || text.len() > 8192) return;
    local lines = split(text, "\n\r");
    if (lines.len() < 1 || lines.len() > 129) return;
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
        if (key in blocks || count >= 1700) continue;
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
    if (Time() - L4D2MCBridge.collisionChangedAt > 0.75)
        L4D2MCBridge.ClearCollision();
    local player = null;
    local entity = null;
    while ((entity = Entities.FindByClassname(entity, "player")) != null) {
        if (!IsPlayerABot(entity) && entity.IsSurvivor() && !entity.IsDead()) {
            player = entity; break;
        }
    }
    if (player == null) return 0.033;
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
    L4D2MCBridge.frame++;
    local data = format("{\"v\":1,\"f\":%d,\"map\":\"%s\",\"p\":[%.6f,%.6f,%.6f],\"feet\":[%.6f,%.6f,%.6f],\"r\":[%.6f,%.6f,%.6f],\"hfov\":%d,\"hit\":%s,\"normal\":%s,\"buttons\":%d}",
        L4D2MCBridge.frame, Director.GetMapName(), p.x,p.y,p.z,feet.x,feet.y,feet.z,a.y,a.x,a.z,fov,surface,normal,player.GetButtonMask());
    StringToFile("l4d2mc_pose.txt", data);
    if (Time() >= L4D2MCBridge.collisionAt) {
        L4D2MCBridge.collisionAt = Time() + 0.25;
        try { L4D2MCBridge.SyncCollision(); } catch (error) { printl("[L4D2MC COLLISION] " + error); }
    }
    return 0.033;
};
AddThinkToEnt(L4D2MCBridge.anchor, "BridgeThink");
printl("[L4D2MC BRIDGE] exporting local survivor camera");
