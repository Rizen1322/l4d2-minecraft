// Private offline bridge. Mailbox values are parsed as DATA, never RunScriptCode.
L4D2MCBridge.gameplay <- L4D2MCPreviousGameplay!=null?L4D2MCPreviousGameplay:
    {content=null, at=-100.0, generation="", lastEvent=0, armed=false,
    hidden={}, frozen={}, movement={}, actors={}, actorSerial=RandomInt(1000,1000000000), projectiles={}, replies={},
    physics={},physIndex=0,ground=[],wheel=0};
L4D2MCPreviousGameplay=null;
if(!("forced" in L4D2MCBridge.gameplay))L4D2MCBridge.gameplay.forced<-{};
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
L4D2MCBridge.Hide <- function(e) {
    if(e==null || !e.IsValid() || !NetProps.HasProp(e,"m_fEffects"))return;
    local id=e.GetEntityIndex(),flags=NetProps.GetPropInt(e,"m_fEffects");
    if(!(id in gameplay.hidden) || gameplay.hidden[id].entity!=e)gameplay.hidden[id]<-{entity=e,old=(flags&32)!=0};
    NetProps.SetPropInt(e,"m_fEffects",flags|32);
};
L4D2MCBridge.RestoreAppearance <- function() {
    if("SurvivalCleanup" in this)SurvivalCleanup();
    foreach(id,v in gameplay.hidden)if(v.entity.IsValid() && !v.old)
        NetProps.SetPropInt(v.entity,"m_fEffects",NetProps.GetPropInt(v.entity,"m_fEffects")&(~32));
    gameplay.hidden.clear();
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
    // Walking, jumping, acceleration and aim belong to L4D2.
    if(id in gameplay.movement) {
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
    local out="[",n=0;
    foreach(kind in ["player","infected","witch"]) {
        local e=null;
        while((e=Entities.FindByClassname(e,kind))!=null && n<48) {
            if(e.GetHealth()<=0 || (e.GetOrigin()-player.GetOrigin()).Length()>1024)continue;
            local id=L4D2MCBridge.Actor(e),p=e.GetOrigin();
            local faction=(kind=="player" && e.IsSurvivor())?0:1;
            out+=format("%s[%d,%.4f,%.4f,%.4f,%d]",n++==0?"":",",id,p.x/32,p.z/32,-p.y/32,faction);
        }
    }
    local dead=[];foreach(index,v in gameplay.actors)if(!v.entity.IsValid() || Time()-v.seen>2)dead.append(index);
    foreach(index in dead)delete gameplay.actors[index];
    return out+"]";
};
L4D2MCBridge.IsCombatTarget <- function(e) {
    return e!=null && e.IsValid() && (e.GetClassname()=="infected" || e.GetClassname()=="witch" || e.GetClassname()=="player");
};
L4D2MCBridge.Raycast <- function(start,end,ignore) {
    local trace={start=start,end=end,ignore=ignore,mask=1174421507}; // MASK_SHOT, world + hitboxes.
    TraceLine(trace);return trace;
};
L4D2MCBridge.Usable <- function(player) {
    local p=player.EyePosition(),trace=Raycast(p,p+player.EyeAngles().Forward()*96,player);
    if(!("enthit" in trace) || trace.enthit==null)return false;
    local kind=trace.enthit.GetClassname();local name=trace.enthit.GetName();
    if(name!=null && (name.find("l4d2mc_collision_")==0 || name.find("l4d2mc_entity_")==0))return false;
    return kind.find("door")!=null || kind=="func_button" || kind.find("weapon_")==0 || kind.find("prop_physics")==0 || kind=="func_useableladder";
};
L4D2MCBridge.HeldActions <- function(player,attack,use,gui) {
    if(!NetProps.HasProp(player,"m_afButtonForced"))return;
    local id=player.GetEntityIndex(),flags=NetProps.GetPropInt(player,"m_afButtonForced");
    if(!(id in gameplay.forced) || gameplay.forced[id].entity!=player)gameplay.forced[id]<-{entity=player,old=flags&33};
    local wanted=0;
    local weapon=NetProps.GetPropEntity(player,"m_hActiveWeapon"),kind=weapon!=null?weapon.GetClassname():"";
    local carry=kind=="weapon_gascan" || kind=="weapon_cola_bottles" || kind=="weapon_gnome" || kind=="weapon_fireworkcrate" || kind.find("weapon_upgradepack_")==0;
    local directUse=false;
    if(use) {
        local p=player.EyePosition(),t=Raycast(p,p+player.EyeAngles().Forward()*96,player);
        if("enthit" in t && t.enthit!=null) {
            local cls=t.enthit.GetClassname();directUse=cls.find("door")!=null || cls=="func_button";
        }
    }
    if(!gui && use && !directUse && (Usable(player) || carry))wanted=wanted|32; // IN_USE, normal Source use/hold processing.
    if(!gui && attack && carry)wanted=wanted|1; // IN_ATTACK only for map carry/use items, never hidden guns.
    NetProps.SetPropInt(player,"m_afButtonForced",(flags&(~33))|gameplay.forced[id].old|wanted);
};
L4D2MCBridge.TeleportPlayer <- function(player,requested,random=false) {
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
    } else if(kind=="link" && fields.len()==6) {
        Link(fields,player);
    } else if(kind=="meal" && fields.len()==5) {
        local amount=Number(fields[3],100),gold=Integer(fields[4]);if(amount<=0 || gold>1)throw "invalid meal";
        survival.meal+=amount;if(survival.meal>100)survival.meal=100;
        if(gold==1 && !player.IsIncapacitated() && NetProps.HasProp(player,"m_healthBuffer")) {
            local buffer=NetProps.GetPropFloat(player,"m_healthBuffer")+20,room=100-player.GetHealth();
            NetProps.SetPropFloat(player,"m_healthBuffer",buffer<room?buffer:room);
            if(NetProps.HasProp(player,"m_healthBufferTime"))NetProps.SetPropFloat(player,"m_healthBufferTime",Time());
        }
    } else if(kind=="heal" && fields.len()==4) {
        local amount=Number(fields[3],100);
        if(amount<=0)throw "invalid food heal";
        if(player.GetHealth()>0 && !player.IsIncapacitated() && !player.IsHangingFromLedge()) {
            local maximum=NetProps.HasProp(player,"m_iMaxHealth")?NetProps.GetPropInt(player,"m_iMaxHealth"):100;
            if(maximum<=0)maximum=100;
            local healed=player.GetHealth()+amount.tointeger();if(healed>maximum)healed=maximum;
            player.SetHealth(healed);
            if(NetProps.HasProp(player,"m_healthBuffer")) {
                local buffer=NetProps.GetPropFloat(player,"m_healthBuffer"),room=(maximum-healed).tofloat();
                NetProps.SetPropFloat(player,"m_healthBuffer",buffer<room?buffer:room);
            }
            printl("[L4D2MC FOOD] health="+healed);
        }
    } else if(kind=="ignite" && fields.len()==6) {
        IgniteGround(fields,player);
    } else if(kind=="melee" && (fields.len()>=5 && fields.len()<=7)) {
        if(fields.len()>=6 && Integer(fields[5])==1)CutTongue(player);
        local damage=Number(fields[3],1500),range=Number(fields[4],256);
        if(damage<0 || range<=0)throw "invalid melee";
        local p=player.EyePosition(),trace=Raycast(p,p+player.EyeAngles().Forward()*range,player);
        if("enthit" in trace && IsCombatTarget(trace.enthit)) {
            local tier=fields.len()==7?Integer(fields[6]):0;if(tier>2)throw "invalid sword tier";
            if(tier>0) {
                if("swordAt" in survival && Time()-survival.swordAt<0.35)return;
                survival.swordAt<-Time();damage=tier==2?220.0:180.0;
                if(trace.enthit.GetClassname()=="infected")damage=trace.enthit.GetHealth()+1.0;
            }
            trace.enthit.TakeDamage(damage,128,player); // DMG_CLUB, Source attribution retained.
            printl("[L4D2MC COMBAT] melee damage="+damage);
        }
    } else if(kind=="mobhit" && fields.len()==9) {
        local id=Integer(fields[3]),damage=Number(fields[4],500);
        local from=Vector(Number(fields[5]),Number(fields[6]),Number(fields[7]));
        local target=FindActor(id);
        if(target!=null && damage>=0 && (target.GetOrigin()-from).Length()<512) {
            local attacker=Integer(fields[8]),ignore=attacker in gameplay.physics?gameplay.physics[attacker].proxy:null;
            local trace=Raycast(from+Vector(0,0,24),target.GetOrigin()+Vector(0,0,32),ignore);
            if(!("hit" in trace) || !trace.hit || ("enthit" in trace && trace.enthit==target)) {
                target.TakeDamage(damage,128,null);
                printl("[L4D2MC COMBAT] mobhit actor="+id+" damage="+damage);
            }
        }
    } else if(kind=="replyack" && fields.len()==4) {
        local id=Integer(fields[3]);
        if(id in gameplay.replies)delete gameplay.replies[id];
    } else if(kind=="interact" && fields.len()==3) {
        local p=player.EyePosition(),trace=Raycast(p,p+player.EyeAngles().Forward()*96,player);
        if("enthit" in trace && trace.enthit!=null) {
            local kind=trace.enthit.GetClassname();
            if(kind.find("door")!=null || kind=="func_button") {
                local name=trace.enthit.GetName();
                if(name==null || name.len()==0){name=UniqueString("l4d2mc_use_");trace.enthit.__KeyValueFromString("targetname",name);}
                EntFire(name,kind.find("door")!=null?"Toggle":"Press","",0,player);
            }
        }
    } else throw "invalid event";
};
L4D2MCBridge.Projectile <- function(fields,player) {
    if(fields.len()!=6 && fields.len()!=7)throw "invalid projectile";
    local id=Integer(fields[1]);
    local p=Vector(Number(fields[3]),Number(fields[4]),Number(fields[5]));
    if(id in gameplay.projectiles) {
        local before=gameplay.projectiles[id];
        if(Time()-before.at<0.5 && (p-before.pos).Length()<512) {
            local trace=Raycast(before.pos,p,player);
            if("hit" in trace && trace.hit) {
                local own="enthit" in trace && trace.enthit!=null &&
                    (trace.enthit.GetName().find("l4d2mc_collision_")==0 || trace.enthit.GetName().find("l4d2mc_entity_")==0);
                if(!own && !before.hit) {
                    if(fields[2]=="ender_pearl") {
                        local back=before.pos-p;
                        if(back.Length()>0.01)back=back*(24.0/back.Length());
                        if(TeleportPlayer(player,trace.pos+back))player.TakeDamage(5,0,null);
                    } else if("enthit" in trace && IsCombatTarget(trace.enthit)) {
                        local damage=fields.len()==7?Number(fields[6],1500):(fields[2]=="firework"?80:60);
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
    // Bound wider body probes to six entities per think.
    try { for(local i=0;i<6 && i<list.len();i++) {
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
        local xmin=-4096.0,xmax=4096.0,zmin=-4096.0,zmax=4096.0;
        // Probe the body's width and three heights, far enough ahead for
        // round-robin/network delay. A midpoint-only ray misses doors/corners.
        local radius=v.width/2,side=radius>1?radius-1:0,distance=radius+96;
        local low=v.height>64?24:v.height/4;
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
            local normal="normal" in top?top.normal:("plane_normal" in top?top.plane_normal:null);
            if(normal==null || normal.z<0.7 || top.pos.z<=p.z+2 || top.pos.z>p.z+32)continue;
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
    gameplay.physIndex=(gameplay.physIndex+6)%list.len();
};
L4D2MCBridge.GameplayLease <- function() { return gameplay.armed && Time()-gameplay.at<=0.5; };
L4D2MCBridge.ReadGameplay <- function(player) {
    local text=FileToString("l4d2mc_gameplay.txt");
    if(text==null || text.len()>18000)return GameplayLease();
    local lines=split(text,"\r\n");if(lines.len()<1 || lines.len()>256)return GameplayLease();
    local header=split(lines[0]," ");
    if(header.len()!=6 && header.len()!=8)return GameplayLease();
    if(header[1]!=Director.GetMapName() || header[2]!="1")return false;
    if(header[0]!=gameplay.generation) {
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
    for(local i=1;i<lines.len();i++) {
        local f=split(lines[i]," ");
        if(f.len()>0 && f[0]=="event")try{Event(f,player);}catch(error){printl("[L4D2MC EVENT] "+error);}
        else if(f.len()>0 && f[0]=="golem")try{GolemTarget(f,player);}catch(error){printl("[L4D2MC GOLEM] "+error);}
        else if(f.len()>0 && f[0]=="nav")try{NavRequest(f,player);}catch(error){printl("[L4D2MC NAV] "+error);}
        else if(f.len()>0 && f[0]=="projectile")try{Projectile(f,player);}catch(error){printl("[L4D2MC PROJECTILE] "+error);}
        else if(f.len()>0 && f[0]=="signal")try{Signal(f,player);}catch(error){printl("[L4D2MC SIGNAL] "+error);}
        else if(f.len()>0 && f[0]=="equipment")try{Equipment(f,player);}catch(error){printl("[L4D2MC EQUIPMENT] "+error);}
        else if(f.len()>0 && f[0]=="physics")try{Physics(f,player);}catch(error){printl("[L4D2MC PHYSICS] "+error);}
    }
    HeldActions(player,header.len()==8 && header[6]=="1",header.len()==8 && header[7]=="1",header[4]=="1");
    Hide(player);
    Movement(player,header[4]=="1",header[5]=="1");
    GroundPhysics();
    SurvivalTick(player);
    try{NavTick();}catch(error){printl("[L4D2MC NAV] "+error);navigation.jobs.clear();}
    if(NetProps.HasProp(player,"m_hActiveWeapon"))Hide(NetProps.GetPropEntity(player,"m_hActiveWeapon"));
    if(NetProps.HasProp(player,"m_hViewModel")) {
        for(local i=0;i<NetProps.GetPropArraySize(player,"m_hViewModel");i++)Hide(NetProps.GetPropEntityArray(player,"m_hViewModel",i));
    }
    local stale=[];foreach(id,v in gameplay.projectiles)if(Time()-v.at>1)stale.append(id);
    foreach(id in stale)delete gameplay.projectiles[id];
    return true;
};
