// Own bridge extension, no replacement of map/director scripts.
if(!("survival" in L4D2MCBridge))L4D2MCBridge.survival<-{
    equipmentAt=-100.0,armor=0.0,toughness=0.0,blocking=false,player=null,
    meal=0.0,nextMeal=0.0,nextPressure=0.0,pressureIndex=0,replySerial=RandomInt(1000000000,1500000000),hook=false,hookLiveAt=-100.0,links={}};
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
L4D2MCBridge.SurvivalTick <- function(player) {
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
