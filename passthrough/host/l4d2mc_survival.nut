// Own bridge extension, no replacement of map/director scripts.
if(!("survival" in L4D2MCBridge))L4D2MCBridge.survival<-{
    equipmentAt=-100.0,armor=0.0,toughness=0.0,blocking=false,player=null,
    meal=0.0,nextMeal=0.0,nextPressure=0.0,pressureIndex=0,replySerial=RandomInt(1000000000,1500000000),hook=false,hookLiveAt=-100.0,links={},shieldHits={},fires=[],nextShield=0.0,nextIgnite=0.0,golems={},nextAggro=0.0,aggroHits={}};
L4D2MCBridge.Reply <- function(body) {
    local count=0;foreach(id,value in gameplay.replies)count++;
    if(count>=64)return;
    survival.replySerial++;
    local id=survival.replySerial;
    gameplay.replies[id]<-format("{\"rid\":%d,%s}",id,body);
};
L4D2MCBridge.Equipment <- function(fields,player) {
    if(fields.len()!=4)return;
    local armor=Number(fields[1],20),toughness=Number(fields[2],20),blocking=Integer(fields[3]);
    if(armor<0 || toughness<0 || blocking>1)return;
    survival.player=player;survival.armor=armor;survival.toughness=toughness;
    survival.blocking=blocking==1;survival.equipmentAt=Time();
};
L4D2MCBridge.Heal <- function(player,amount) {
    if(player.GetHealth()<=0 || player.IsIncapacitated() || player.IsHangingFromLedge())return;
    local maximum=NetProps.HasProp(player,"m_iMaxHealth")?NetProps.GetPropInt(player,"m_iMaxHealth"):100;
    if(maximum<=0)maximum=100;
    local h=player.GetHealth()+amount.tointeger();if(h>maximum)h=maximum;player.SetHealth(h);
    if(NetProps.HasProp(player,"m_healthBuffer")) {
        local b=NetProps.GetPropFloat(player,"m_healthBuffer"),room=(maximum-h).tofloat();
        NetProps.SetPropFloat(player,"m_healthBuffer",b<room?b:room);
    }
};
L4D2MCBridge.Protection <- function(victim,attacker,amount,type=0) {
    if(!GameplayLease() || victim!=survival.player || Time()-survival.equipmentAt>0.75 || attacker==null || !attacker.IsValid())return 1.0;
    if(type!=0 && (type&(2|4|128|4096))==0)return 1.0; // No armour/shield against fire, acid or falls.
    local cls=attacker.GetClassname();
    if(cls!="infected" && cls!="witch" && !(cls=="player" && !attacker.IsSurvivor()))return 1.0;
    local tank=cls=="player" && attacker.GetZombieType()==8;
    if(survival.blocking && !tank) {
        local delta=attacker.GetOrigin()-victim.GetOrigin();delta.z=0;
        local forward=victim.EyeAngles().Forward();forward.z=0;
        if(delta.Length()>0.001 && forward.Length()>0.001 && (delta.x*forward.x+delta.y*forward.y)/(delta.Length()*forward.Length())>=0.5) {
            Reply(format("\"t\":\"equipmenthit\",\"d\":%d,\"shield\":true",amount.tointeger()>0?amount.tointeger():1));
            return 0.1;
        }
    }
    local effective=survival.armor-(amount/5.0)/(2+survival.toughness/4);
    if(effective<survival.armor*0.2)effective=survival.armor*0.2;
    if(effective>20)effective=20;
    if(survival.armor>0)Reply(format("\"t\":\"equipmenthit\",\"d\":%d,\"shield\":false",amount.tointeger()>0?amount.tointeger():1));
    return 1-effective/25;
};
L4D2MCBridge.InstallProtection <- function() {
    // Scripted mutations expose a pre-damage callback. Preserve their existing
    // rule; ordinary coop uses the nonlethal player_hurt fallback below.
    if(survival.hook || !("g_ModeScript" in getroottable()) || g_ModeScript==null)return;
    local scope=g_ModeScript;
    if("l4d2mcDamageHook" in scope){survival.hook=true;return;}
    local previous="AllowTakeDamage" in scope?scope.AllowTakeDamage:null;
    scope.AllowTakeDamage<-function(info) {
        if(previous!=null && previous.call(scope,info)==false)return false;
        if("L4D2MCBridge" in getroottable() && "Victim" in info && "Attacker" in info && "DamageDone" in info && info.DamageDone>0) {
            L4D2MCBridge.survival.hookLiveAt=Time();
            info.DamageDone*=L4D2MCBridge.Protection(info.Victim,info.Attacker,info.DamageDone,"DamageType" in info?info.DamageType:0);
        }
        return true;
    };
    scope.l4d2mcDamageHook<-true;survival.hook=true;
};
L4D2MCBridge.ShieldFacing <- function(player,enemy) {
    if(!GameplayLease() || player!=survival.player || !survival.blocking || Time()-survival.equipmentAt>0.5)return false;
    if(enemy==null || !enemy.IsValid() || player.GetHealth()<=0 || player.IsIncapacitated())return false;
    local delta=enemy.GetOrigin()-player.GetOrigin(),f=player.EyeAngles().Forward();delta.z=0;f.z=0;
    return delta.Length()>0.01 && f.Length()>0.01 && (delta.x*f.x+delta.y*f.y)/(delta.Length()*f.Length())>=0.5;
};
L4D2MCBridge.ShieldRepel <- function(player,e) {
    local id=e.GetEntityIndex();
    if(id in survival.shieldHits && survival.shieldHits[id].entity==e && Time()-survival.shieldHits[id].at<1.2)return;
    local t=Raycast(player.EyePosition(),e.GetOrigin()+Vector(0,0,32),player);
    if("hit" in t && t.hit && (!("enthit" in t) || t.enthit!=e))return;
    if(e.GetClassname()=="player")e.Stagger(player.GetOrigin());
    else e.TakeDamage(1,33554432,player); // Source DMG_STUMBLE, normal infected shove.
    survival.shieldHits[id]<-{entity=e,at=Time()};
    Reply("\"t\":\"equipmenthit\",\"d\":1,\"shield\":true");
};
L4D2MCBridge.CutTongue <- function(player) {
    if(!NetProps.HasProp(player,"m_tongueOwner"))return;
    local smoker=NetProps.GetPropEntity(player,"m_tongueOwner");
    if(smoker!=null && smoker.IsValid() && smoker.GetClassname()=="player" && smoker.GetZombieType()==1)smoker.Stagger(player.GetOrigin());
};
L4D2MCBridge.ShieldTick <- function(player) {
    if(Time()<survival.nextShield)return;survival.nextShield=Time()+0.05;
    local stale=[];foreach(id,v in survival.shieldHits)if(!v.entity.IsValid() || Time()-v.at>3)stale.append(id);
    foreach(id in stale)delete survival.shieldHits[id];
    if(!survival.blocking || Time()-survival.equipmentAt>0.5)return;
    foreach(cls in ["infected","player"]) {
        local e=null,count=0;
        while((e=Entities.FindByClassnameWithin(e,cls,player.GetOrigin(),128))!=null && count++<32) {
            if(e.GetHealth()<=0 || !ShieldFacing(player,e))continue;
            if(cls=="player") {
                if(e.IsSurvivor())continue;
                local k=e.GetZombieType();if(k!=3 && k!=5)continue; // Hunter/Jockey airborne approach only.
                local d=player.GetOrigin()-e.GetOrigin(),v=e.GetVelocity();
                if((NetProps.GetPropInt(e,"m_fFlags")&1)!=0 || d.Length()>112 || d.x*v.x+d.y*v.y<=0)continue;
                if(abs(d.z)>96)continue;
            } else if((e.GetOrigin()-player.GetOrigin()).Length()>72)continue;
            ShieldRepel(player,e);
        }
    }
};
L4D2MCBridge.IgniteGround <- function(f,player) {
    if(Time()<survival.nextIgnite || survival.fires.len()>=6 || !("DropFire" in getroottable()))return;
    local p=Vector(Number(f[3]),Number(f[4]),Number(f[5]));
    if((p-player.EyePosition()).Length()>160)return;
    local t=Raycast(player.EyePosition(),p-Vector(0,0,2),player);
    if(!("hit" in t && t.hit) || (t.pos-p).Length()>12)return;
    local floor={start=p+Vector(0,0,4),end=p-Vector(0,0,12),ignore=player,mask=16395};TraceLine(floor);
    if(!("hit" in floor && floor.hit) || ("startsolid" in floor && floor.startsolid))return;
    local n="normal" in floor?floor.normal:("plane_normal" in floor?floor.plane_normal:null);
    if(n==null || n.z<0.7)return;
    local count=0,e=null,before={};while((e=Entities.Next(e))!=null){count++;if(e.GetClassname()=="inferno")before[e.GetEntityIndex()]<-true;}
    if(count>=1400)return;
    foreach(v in survival.fires)if(v.entity.IsValid() && (v.pos-p).Length()<64)return;
    survival.nextIgnite=Time()+0.5;DropFire(floor.pos+Vector(0,0,2));
    e=null;while((e=Entities.FindByClassname(e,"inferno"))!=null)
        if(!(e.GetEntityIndex() in before) && (e.GetOrigin()-p).Length()<256)survival.fires.append({entity=e,pos=p,until=Time()+12});
};
L4D2MCBridge.SurvivalCleanup <- function() {
    foreach(v in survival.fires)if(v.entity.IsValid())v.entity.Kill();survival.fires.clear();
    foreach(id,v in survival.golems)if(v.entity.IsValid())v.entity.Kill();survival.golems.clear();
    survival.blocking=false;survival.shieldHits.clear();survival.aggroHits.clear();
};
// Eight non-solid invisible targets, not collision stand-ins. Native infected navigation pursues them.
L4D2MCBridge.GolemTarget <- function(f,player) {
    if(f.len()!=6 || (f[2]!="iron_golem" && f[2]!="snow_golem"))return;
    local id=Integer(f[1]),p=Vector(Number(f[3]),Number(f[4]),Number(f[5]));
    if((p-player.GetOrigin()).Length()>1536)return;
    if(!(id in survival.golems)) {
        if(survival.golems.len()>=8)return;
        local count=0,e=null;while((e=Entities.Next(e))!=null)count++;if(count>=1400)return;
        local e=SpawnEntityFromTable("info_target",{targetname=UniqueString("l4d2mc_golem_"),origin=p});
        if(e==null)return;e.SetHealth(100);
        survival.golems[id]<-{entity=e,pos=p,at=Time()};
    }
    local v=survival.golems[id];if(!v.entity.IsValid()){delete survival.golems[id];return;}
    v.entity.SetOrigin(p);v.pos=p;v.at=Time();
};
L4D2MCBridge.GolemAggroTick <- function(player) {
    local stale=[];foreach(id,v in survival.golems)if(!v.entity.IsValid() || Time()-v.at>1)stale.append(id);
    foreach(id in stale){if(survival.golems[id].entity.IsValid())survival.golems[id].entity.Kill();delete survival.golems[id];}
    stale=[];foreach(id,v in survival.aggroHits)if(!v.entity.IsValid() || Time()-v.at>3)stale.append(id);
    foreach(id in stale)delete survival.aggroHits[id];
    if(Time()<survival.nextAggro || survival.golems.len()==0 || !("CommandABot" in getroottable()))return;
    survival.nextAggro=Time()+0.25;local count=0;
    local bots=[];foreach(cls in ["infected","player"]) {
        local e=null;while((e=Entities.FindByClassnameWithin(e,cls,player.GetOrigin(),1536))!=null && bots.len()<64)
            if(e.GetHealth()>0 && (cls=="infected" || (!e.IsSurvivor() && e.IsBot())))bots.append(e);
    }
    foreach(e in bots) {
        local best=null,bestId=0,dist=384.0;
        foreach(id,v in survival.golems) {
            local d=(v.pos-e.GetOrigin()).Length();if(d>=dist || abs(v.pos.z-e.GetOrigin().z)>128)continue;
            local t=Raycast(e.GetOrigin()+Vector(0,0,32),v.pos+Vector(0,0,32),e);
            if("hit" in t && t.hit && (!("enthit" in t) || t.enthit!=v.entity))continue;
            best=v;bestId=id;dist=d;
        }
        if(best==null)continue;
        if(count++>=16)break;
        // Do not redirect a special that is already pinning a survivor.
        local pin=false;foreach(prop in ["m_pounceVictim","m_jockeyVictim","m_tongueVictim","m_carryVictim"])
            if(NetProps.HasProp(e,prop) && NetProps.GetPropEntity(e,prop)!=null)pin=true;
        if(pin)continue;
        CommandABot({bot=e,target=best.entity,cmd=0});
        local ix=e.GetEntityIndex();
        if(dist<72 && (!(ix in survival.aggroHits) || survival.aggroHits[ix].entity!=e || Time()-survival.aggroHits[ix].at>=1)) {
            // No solid proxy can trap survivors. Damage is sent to the real Minecraft mob.
            Reply(format("\"t\":\"mobdmg\",\"id\":%d,\"d\":%.2f",bestId,e.GetClassname()=="player" && e.GetZombieType()==8?15.0:3.0));
            survival.aggroHits[ix]<-{entity=e,at=Time()};
        }
    }
};
L4D2MCBridge.SurvivalTick <- function(player) {
    ShieldTick(player);
    for(local i=survival.fires.len()-1;i>=0;i--)if(!survival.fires[i].entity.IsValid() || Time()>survival.fires[i].until){if(survival.fires[i].entity.IsValid())survival.fires[i].entity.Kill();survival.fires.remove(i);}
    GolemAggroTick(player);
    InstallProtection();
    if(Time()>=survival.nextMeal && survival.meal>0) {
        local amount=survival.meal<2?survival.meal:2;
        Heal(player,amount);survival.meal-=amount;survival.nextMeal=Time()+0.25;
    }
    if(Time()<survival.nextPressure || blocks.len()==0)return;
    survival.nextPressure=Time()+0.5;
    local keys=[];foreach(key,block in blocks)if(block.IsValid())keys.append(key);
    if(keys.len()==0)return;
    for(local i=0;i<6 && i<keys.len();i++) {
        local key=keys[(survival.pressureIndex+i)%keys.len()],block=blocks[key],at=block.GetOrigin();
        local strength=0,e=null;
        foreach(cls in ["infected","player"]) {
            e=null;
            while((e=Entities.FindByClassname(e,cls))!=null) {
                if(e.GetHealth()<=0 || (cls=="player" && e.IsSurvivor()) || (e.GetOrigin()-at).Length()>80)continue;
                local trace=Raycast(e.GetOrigin()+Vector(0,0,24),at,e);
                if(!("enthit" in trace) || trace.enthit!=block)continue;
                local hit=cls=="player" && e.GetZombieType()==8?80:8;
                if(hit>strength)strength=hit;
            }
        }
        if(strength>0) {
            local xyz=split(key," ");
            Reply(format("\"t\":\"breakblock\",\"pos\":[%s,%s,%s],\"d\":%d",xyz[0],xyz[1],xyz[2],strength));
        }
    }
    survival.pressureIndex=(survival.pressureIndex+6)%keys.len();
};
// Register once. Callbacks look up the current bridge after script reconnects.
if(!("L4D2MCSurvivalEvents" in getroottable())) {
    ::L4D2MCSurvivalEvents <- {
        OnGameEvent_round_start=function(event) {
            if("L4D2MCBridge" in getroottable()){L4D2MCBridge.epoch=RandomInt(1,2000000000);L4D2MCBridge.SurvivalCleanup();}
        },
        OnGameEvent_tongue_grab=function(event) {
            if(!("L4D2MCBridge" in getroottable()) || !("victim" in event) || !("userid" in event))return;
            local b=L4D2MCBridge,p=GetPlayerFromUserID(event.victim),s=GetPlayerFromUserID(event.userid);
            if(p!=null && s!=null && b.ShieldFacing(p,s))b.ShieldRepel(p,s);
        },
        OnGameEvent_player_hurt=function(event) {
            if(!("L4D2MCBridge" in getroottable()))return;
            local b=L4D2MCBridge;if(Time()-b.survival.hookLiveAt<0.1 || !b.GameplayLease())return;
            local p=GetPlayerFromUserID(event.userid);if(p==null || p!=b.survival.player || p.IsIncapacitated() || p.GetHealth()<=0)return;
            local from=null;
            if("attackerentid" in event && event.attackerentid>0)from=EntIndexToHScript(event.attackerentid);
            if(from==null && "attacker" in event && event.attacker>0)from=GetPlayerFromUserID(event.attacker);
            local amount="dmg_health" in event?event.dmg_health:0;
            if(amount>0) {
                local ratio=b.Protection(p,from,amount,"type" in event?event.type:0);
                if(ratio<1)b.Heal(p,(amount*(1-ratio)).tointeger());
            }
        },
        OnGameEvent_infected_death=function(event) {
            if(!("L4D2MCBridge" in getroottable()))return;
            local b=L4D2MCBridge;
            if(!b.GameplayLease() || RandomInt(0,5)!=0 || !("infected_id" in event))return;
            local e=EntIndexToHScript(event.infected_id);
            if(e==null || !e.IsValid())return;
            local p=e.GetOrigin();
            b.Reply(format("\"t\":\"supply\",\"pos\":[%.4f,%.4f,%.4f],\"kind\":%d",p.x/32,p.z/32,-p.y/32,RandomInt(0,3)));
        }
    };
    if("__CollectEventCallbacks" in getroottable() && "RegisterScriptGameEventListener" in getroottable())
        __CollectEventCallbacks(L4D2MCSurvivalEvents,"OnGameEvent_","GameEventCallbacks",RegisterScriptGameEventListener);
    else printl("[L4D2MC] Survival event callbacks unavailable; director pre-damage hook only.");
}

L4D2MCBridge.Link <- function(fields,player) {
    if(fields.len()!=6 || survival.links.len()>=32)return;
    local key=fields[3]+" "+fields[4]+" "+fields[5];
    foreach(f in fields.slice(3))Number(f,1023);
    local p=player.EyePosition(),t=Raycast(p,p+player.EyeAngles().Forward()*160,player);
    if(!("enthit" in t) || t.enthit==null)return;
    local e=t.enthit,cls=e.GetClassname();if(cls.find("door")==null && cls!="func_button")return;
    local name=e.GetName();if(name==null || name.len()==0){name=UniqueString("l4d2mc_link_");e.__KeyValueFromString("targetname",name);}
    survival.links[key]<-{entity=e,name=name,door=cls.find("door")!=null,on=null};
};
L4D2MCBridge.Signal <- function(fields,player) {
    if(fields.len()!=5)return;
    local key=fields[1]+" "+fields[2]+" "+fields[3],on=Integer(fields[4]);if(on>1 || !(key in survival.links))return;
    local link=survival.links[key];if(!link.entity.IsValid()){delete survival.links[key];return;}
    if(link.on!=on) {
        if(link.door)EntFire(link.name,on==1?"Open":"Close","",0,player);
        else if(on==1)EntFire(link.name,"Press","",0,player);
        link.on=on;
    }
};
