// Own bridge extension, no replacement of map/director scripts.
if(!("survival" in L4D2MCBridge))L4D2MCBridge.survival<-{
    equipmentAt=-100.0,armor=0.0,toughness=0.0,blocking=false,player=null,
    protectionAt=-100.0,epf=[0,0,0,0,0],resistance=0,fireproof=false,meal=0.0,nextMeal=0.0,nextPressure=0.0,pressureIndex=0,replySerial=RandomInt(1000000000,1500000000),hook=false,hookLiveAt=-100.0,links={},shieldHits={},fires=[],nextShield=0.0,nextIgnite=0.0,golems={},nextAggro=0.0,aggroHits={}};
if(!("speed" in L4D2MCBridge.survival)) {
    L4D2MCBridge.survival.speed<-1.0;L4D2MCBridge.survival.effectsAt<- -100.0;
    L4D2MCBridge.survival.guestBurn<-false;L4D2MCBridge.survival.nextBurn<-0.0;
}
if(!("shieldCharge" in L4D2MCBridge.survival)) {
    L4D2MCBridge.survival.shieldCharge<-6;L4D2MCBridge.survival.shieldCooldown<-0.0;
    L4D2MCBridge.survival.shieldHitAt<-{};
}
if(!("fireZones" in L4D2MCBridge.survival)) {
    L4D2MCBridge.survival.fireZones<-[];L4D2MCBridge.survival.fireActors<-{};L4D2MCBridge.survival.nextFire<-0.0;
}
if(!("totemPending" in L4D2MCBridge.survival)) {
    L4D2MCBridge.survival.totemPending<-null;L4D2MCBridge.survival.totemHeld<-false;L4D2MCBridge.survival.totemAt<- -100.0;
}
L4D2MCBridge.TotemPendingFor <- function(player) {
    local v=survival.totemPending;
    return v!=null && v.entity==player && player.IsValid() && Time()-v.at<30;
};
L4D2MCBridge.TotemHeld <- function(f) {
    if(f.len()!=2)return;local held=Integer(f[1]);if(held>1)return;
    survival.totemHeld=held==1;survival.totemAt=Time();
};
L4D2MCBridge.TotemRequest <- function(player) {
    if(player==null || !player.IsValid() || player!=survival.player || !GameplayLease()
        || !survival.totemHeld || Time()-survival.totemAt>0.75 || TotemPendingFor(player))return;
    if(!player.IsDead() && player.GetHealth()>0 && !player.IsIncapacitated())return;
    if(!player.IsDead() && player.IsHangingFromLedge())return;
    survival.replySerial++;
    survival.totemPending={entity=player,key=format("totem_%d_%d_%d",epoch,player.GetEntityIndex(),survival.replySerial),at=Time(),next=0.0};
    TotemTick(player);
};
L4D2MCBridge.TotemTick <- function(player) {
    if(!TotemPendingFor(player)) {if(survival.totemPending!=null && Time()-survival.totemPending.at>=30)survival.totemPending=null;return;}
    local v=survival.totemPending;if(Time()<v.next)return;v.next=Time()+0.5;
    Reply("\"t\":\"totemrequest\",\"key\":\""+v.key+"\"");
};
L4D2MCBridge.TotemResult <- function(f,player) {
    if(f.len()!=5 || !TotemPendingFor(player) || f[3]!=survival.totemPending.key)return;
    local used=Integer(f[4]);if(used>1)return;
    if(used==0){survival.totemPending=null;survival.totemHeld=false;return;}
    // Native CTerrorPlayer no-argument bindings, not a generic entity respawn.
    if(player.IsDead())player.ReviveByDefib();
    else if(player.IsIncapacitated())player.ReviveFromIncap();
    if(player.IsDead() || player.IsIncapacitated())return;
    player.SetHealth(100);
    if(NetProps.HasProp(player,"m_healthBuffer"))NetProps.SetPropFloat(player,"m_healthBuffer",0.0);
    if(player.GetHealth()!=100)return;
    local key=survival.totemPending.key;survival.totemPending=null;survival.totemHeld=false;
    Reply("\"t\":\"totemapplied\",\"key\":\""+key+"\"");
};
L4D2MCBridge.ShieldAvailable <- function(){return Time()>=survival.shieldCooldown && survival.shieldCharge>0;};
L4D2MCBridge.ShieldSpend <- function(e) {
    if(!ShieldAvailable())return false;
    local id=e.GetEntityIndex();
    if(id in survival.shieldHitAt && survival.shieldHitAt[id].entity==e && Time()-survival.shieldHitAt[id].at<1.2)return true;
    survival.shieldHitAt[id]<-{entity=e,at=Time()};
    survival.shieldCharge-=e.GetClassname()=="player"?2:1;
    if(survival.shieldCharge<=0){survival.shieldCharge=0;survival.shieldCooldown=Time()+5;Reply("\"t\":\"shieldcooldown\",\"ticks\":100");}
    return true;
};
L4D2MCBridge.Effects <- function(f) {
    if(f.len()!=3)return;
    local speed=Number(f[1],2),burn=Integer(f[2]);if(speed<0.25 || burn>1)return;
    survival.speed=speed;survival.guestBurn=burn==1;survival.effectsAt=Time();
};
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
L4D2MCBridge.ProtectionEquipment <- function(f) {
    if(f.len()!=8)return;
    local values=[];for(local i=1;i<=5;i++){local v=Number(f[i],20);if(v<0)return;values.append(v);}
    local resist=Integer(f[6]),fire=Integer(f[7]);if(resist>4 || fire>1)return;
    survival.epf=values;survival.resistance=resist;survival.fireproof=fire==1;survival.protectionAt=Time();
};
// Pure damage arithmetic, shared by pre-damage and ordinary-coop refund paths.
L4D2MCBridge.ProtectionRatio <- function(amount,type,armor,toughness,epf,resistance,fireproof,enemy) {
    local burn=(type&8)!=0,fall=(type&32)!=0,blast=(type&64)!=0,bullet=(type&(2|536870912))!=0;
    local physical=bullet || blast || (type&(4|128|4096|2097152))!=0 || (type==0 && enemy);
    if(burn && fireproof)return 0.0;
    local ratio=1.0;
    if(physical && !fall && !burn) {
        local effective=armor-(amount/5.0)/(2+toughness/4);
        if(effective<armor*0.2)effective=armor*0.2;if(effective>20)effective=20;
        ratio*=1-effective/25;
    }
    local protection=epf[fall?3:burn?1:blast?2:bullet?4:0];
    ratio*=1-protection/25;
    // Resistance never makes the wearer invulnerable; Fire Resistance is explicit immunity to burn.
    ratio*=1-resistance*0.2;
    return ratio;
};
L4D2MCBridge.Protection <- function(victim,attacker,amount,type=0) {
    if(!GameplayLease() || victim!=survival.player || Time()-survival.equipmentAt>0.75)return 1.0;
    local enemy=false,tank=false;
    if(attacker!=null && attacker.IsValid()) {
        local cls=attacker.GetClassname();
        enemy=cls=="infected" || cls=="witch" || (cls=="player" && !attacker.IsSurvivor());
        tank=cls=="player" && !attacker.IsSurvivor() && attacker.GetZombieType()==8;
    }
    local physical=(type&(2|4|128|4096|2097152|536870912))!=0 || (type==0 && enemy);
    if(physical && enemy && survival.blocking && !tank && ShieldFacing(victim,attacker)) {
        if(!ShieldSpend(attacker))return 1.0;
        Reply(format("\"t\":\"equipmenthit\",\"d\":%d,\"shield\":true",amount.tointeger()>0?amount.tointeger():1));
        return 0.1;
    }
    local epf=[0,0,0,0,0],resist=0,fire=false;
    if(Time()-survival.protectionAt<=0.75){epf=survival.epf;resist=survival.resistance;fire=survival.fireproof;}
    if((physical || (type&64)!=0) && survival.armor>0)
        Reply(format("\"t\":\"equipmenthit\",\"d\":%d,\"shield\":false",amount.tointeger()>0?amount.tointeger():1));
    return ProtectionRatio(amount,type,survival.armor,survival.toughness,epf,resist,fire,enemy);
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
    if(!ShieldAvailable() || !GameplayLease() || player!=survival.player || !survival.blocking || Time()-survival.equipmentAt>0.5)return false;
    if(enemy==null || !enemy.IsValid() || player.GetHealth()<=0 || player.IsIncapacitated())return false;
    local delta=enemy.GetOrigin()-player.GetOrigin(),f=player.EyeAngles().Forward();delta.z=0;f.z=0;
    return delta.Length()>0.01 && f.Length()>0.01 && (delta.x*f.x+delta.y*f.y)/(delta.Length()*f.Length())>=0.5;
};
L4D2MCBridge.ShieldRepel <- function(player,e) {
    local id=e.GetEntityIndex();
    if(id in survival.shieldHits && survival.shieldHits[id].entity==e && Time()-survival.shieldHits[id].at<1.2)return;
    local t=Raycast(player.EyePosition(),e.GetOrigin()+Vector(0,0,32),player);
    if("hit" in t && t.hit && (!("enthit" in t) || t.enthit!=e))return;
    if(!ShieldSpend(e))return;
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
    if(survival.shieldCharge<=0 && Time()>=survival.shieldCooldown){survival.shieldCharge=6;survival.shieldHitAt.clear();}
    local oldHits=[];foreach(id,v in survival.shieldHitAt)if(!v.entity.IsValid() || Time()-v.at>5)oldHits.append(id);
    foreach(id in oldHits)delete survival.shieldHitAt[id];
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
                local k=e.GetZombieType();if(k!=3 && k!=5 && k!=6)continue; // Hunter/Jockey/Charger approaches.
                local d=player.GetOrigin()-e.GetOrigin(),v=e.GetVelocity();
                if((k!=6 && (NetProps.GetPropInt(e,"m_fFlags")&1)!=0) || d.Length()>112 || d.x*v.x+d.y*v.y<=0)continue;
                if(abs(d.z)>96)continue;
            } else if((e.GetOrigin()-player.GetOrigin()).Length()>72)continue;
            ShieldRepel(player,e);
        }
    }
};
L4D2MCBridge.IgniteGround <- function(f,player) {
    // Legacy one-shot events are deliberately inert. Actual Minecraft FIRE
    // heartbeat below owns contact; never spawn a native inferno on the floor.
};
L4D2MCBridge.FireZone <- function(f,player) {
    if(f.len()!=4 || survival.fireZones.len()>=32)return;
    local p=Vector(Number(f[1]),Number(f[2]),Number(f[3]));
    if((p-player.GetOrigin()).Length()>1600)return;
    survival.fireZones.append(p);
};
L4D2MCBridge.FireOverlap <- function(p,lo,hi) {
    return hi.x>p.x && lo.x<p.x+32 && hi.y>p.y-32 && lo.y<p.y
        && hi.z>p.z-2 && lo.z<p.z+32;
};
L4D2MCBridge.FireTick <- function(player) {
    if(Time()<survival.nextFire)return;survival.nextFire=Time()+0.2;
    local stale=[];foreach(id,v in survival.fireActors)if(!v.entity.IsValid() || v.entity.GetHealth()<=0 || Time()>v.until)stale.append(id);
    foreach(id in stale)delete survival.fireActors[id];
    if(survival.fireZones.len()>0)foreach(cls in ["player","infected","witch"]) {
        local e=null,count=0;
        while((e=Entities.FindByClassnameWithin(e,cls,player.GetOrigin(),1600))!=null && count++<64) {
            // Local Steve has Minecraft's burning flag + authoritative Source
            // guestBurn damage path; do not add a duplicate native body flame.
            if(e==player || e.GetHealth()<=0)continue;
            local p=e.GetOrigin(),lo=p-Vector(16,16,0),hi=p+Vector(16,16,72);
            if(NetProps.HasProp(e,"m_Collision.m_vecMins") && NetProps.HasProp(e,"m_Collision.m_vecMaxs")) {
                lo=p+NetProps.GetPropVector(e,"m_Collision.m_vecMins");hi=p+NetProps.GetPropVector(e,"m_Collision.m_vecMaxs");
            }
            if(NetProps.HasProp(e,"m_nWaterLevel") && NetProps.GetPropInt(e,"m_nWaterLevel")>0)continue;
            foreach(zone in survival.fireZones)if(FireOverlap(zone,lo,hi)) {
                local t=Raycast(p+Vector(0,0,16),zone+Vector(16,-16,12),e);
                if("hit" in t && t.hit)continue;
                local id=e.GetEntityIndex();
                if(!(id in survival.fireActors) || survival.fireActors[id].entity!=e) {
                    if(survival.fireActors.len()>=64)break;
                    survival.fireActors[id]<-{entity=e,until=Time()+4,nextIgnite=0.0,nextHit=Time()+0.25};
                }
                survival.fireActors[id].until=Time()+4;break;
            }
        }
    }
    local entities=0,scan=null;if(survival.fireActors.len()>0)while((scan=Entities.Next(scan))!=null)entities++;
    foreach(id,v in survival.fireActors) {
        local e=v.entity;
        if(NetProps.HasProp(e,"m_nWaterLevel") && NetProps.GetPropInt(e,"m_nWaterLevel")>0)continue;
        local flame=NetProps.HasProp(e,"m_hEffectEntity")?NetProps.GetPropEntity(e,"m_hEffectEntity"):null;
        if(Time()>=v.nextIgnite) {
            if((flame!=null && flame.IsValid()) || entities<1400) {
                local name=e.GetName();if(name==null || name.len()==0){name=UniqueString("l4d2mc_burning_");e.__KeyValueFromString("targetname",name);}
                EntFire(name,"IgniteLifetime",(v.until-Time()).tostring(),0,player);
                if(flame==null || !flame.IsValid())entities++;
            }
            v.nextIgnite=Time()+1;
        }
        // Native entityflame supplies the game's normal burn damage. Some map
        // actors reject IgniteLifetime; supply only their otherwise missing DOT.
        if((flame==null || !flame.IsValid() || flame.GetClassname()!="entityflame") && Time()>=v.nextHit) {
            e.TakeDamage(e.GetClassname()=="player" && e.IsSurvivor()?2:10,8,player);v.nextHit=Time()+0.5;
        }
    }
};
L4D2MCBridge.SurvivalCleanup <- function() {
    foreach(v in survival.fires)if(v.entity.IsValid())v.entity.Kill();survival.fires.clear();
    foreach(id,v in survival.golems)if(v.entity.IsValid())v.entity.Kill();survival.golems.clear();
    survival.shieldCharge=6;survival.shieldCooldown=0;survival.shieldHitAt.clear();survival.guestBurn=false;survival.effectsAt=-100.0;
    survival.blocking=false;survival.protectionAt=-100.0;survival.shieldHits.clear();survival.aggroHits.clear();
    survival.meal=0.0;survival.nextMeal=0.0;survival.nextBurn=0.0;
    survival.nextShield=0.0;survival.nextIgnite=0.0;survival.nextAggro=0.0;
    survival.nextPressure=0.0;survival.pressureIndex=0;
    survival.fireZones.clear();survival.fireActors.clear();survival.nextFire=0.0;
    if("swordAt" in survival)delete survival.swordAt;
    if("dropLatch" in survival)survival.dropLatch=false;
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
// Durable outbox survives chapter VM recreation and guest reconnects.
L4D2MCBridge.QueuePickup <- function(key,kind) {
    local text=FileToString("l4d2mc_pickups.txt");if(text==null)text="";
    local rows=split(text,"\r\n");if(rows.len()>=64)return false;
    foreach(row in rows){local f=split(row," ");if(f.len()==2 && f[0]==key)return true;}
    StringToFile("l4d2mc_pickups.txt",text+key+" "+kind+"\n");
    local saved=FileToString("l4d2mc_pickups.txt");return saved!=null && saved.find(key+" "+kind)!=null;
};
L4D2MCBridge.PickupAck <- function(key) {
    local text=FileToString("l4d2mc_pickups.txt");if(text==null)return;
    local out="";foreach(row in split(text,"\r\n")){local f=split(row," ");if(f.len()==2 && f[0]!=key)out+=row+"\n";}
    StringToFile("l4d2mc_pickups.txt",out);
};
// Consume only real items owned by this local survivor; map spawns and carry objectives stay intact.
L4D2MCBridge.ConvertPickups <- function(player) {
    if(!("converted" in survival))survival.converted<-{};
    if(!NetProps.HasProp(player,"m_hMyWeapons"))return;
    local stale=[];foreach(id,v in survival.converted)if(!v.IsValid())stale.append(id);
    foreach(id in stale)delete survival.converted[id];
    for(local i=0;i<NetProps.GetPropArraySize(player,"m_hMyWeapons");i++) {
        local item=NetProps.GetPropEntityArray(player,"m_hMyWeapons",i);
        if(item==null || !item.IsValid())continue;
        local id=item.GetEntityIndex(),cls=item.GetClassname();
        if(id in survival.converted && survival.converted[id]==item)continue;
        local kind=null;
        switch(cls) {
            case "weapon_first_aid_kit":kind="golden_apple";break;
            case "weapon_pain_pills":kind="cookie";break;
            case "weapon_adrenaline":kind="speed_potion";break;
            case "weapon_molotov":kind="flint_and_steel";break;
            case "weapon_pipe_bomb":kind="tnt";break;
            case "weapon_vomitjar":kind="slowness_potion";break;
            case "weapon_pistol":kind="wooden_sword";break;
            case "weapon_pistol_magnum":kind="stone_sword";break;
            case "weapon_smg":case "weapon_smg_silenced":case "weapon_smg_mp5":
            case "weapon_pumpshotgun":case "weapon_shotgun_chrome":kind="iron_sword";break;
            case "weapon_rifle":case "weapon_rifle_ak47":case "weapon_rifle_desert":case "weapon_rifle_sg552":
            case "weapon_autoshotgun":case "weapon_shotgun_spas":case "weapon_melee":kind="diamond_sword";break;
            case "weapon_rifle_m60":case "weapon_chainsaw":kind="netherite_sword";break;
            case "weapon_hunting_rifle":case "weapon_sniper_military":case "weapon_sniper_awp":case "weapon_sniper_scout":kind="bow";break;
            case "weapon_grenade_launcher":kind="crossbow";break;
            case "weapon_defibrillator":kind="totem_of_undying";break;
        }
        if(kind==null || gameplay.replies.len()>=60)continue;
        local key=format("pickup_%d_%d",epoch,Actor(item));
        if(!QueuePickup(key,kind))continue;
        survival.converted[id]<-item;
        // Keep the hidden sidearm: Source requires a fallback active weapon for native carry/use.
        if(cls!="weapon_pistol" && cls!="weapon_pistol_magnum" && cls!="weapon_melee")item.Kill();
    }
};
L4D2MCBridge.SurvivalTick <- function(player) {
    ConvertPickups(player);
    TotemRequest(player);TotemTick(player);
    FireTick(player);
    if(survival.guestBurn && Time()-survival.effectsAt<0.75 && Time()>=survival.nextBurn) {
        survival.nextBurn=Time()+0.5;
        local nativeFlame=NetProps.HasProp(player,"m_hEffectEntity")?NetProps.GetPropEntity(player,"m_hEffectEntity"):null;
        local submerged=NetProps.HasProp(player,"m_nWaterLevel") && NetProps.GetPropInt(player,"m_nWaterLevel")>0;
        // Native flames already cause native damage; guest fire supplies only the missing path.
        if(!submerged && (nativeFlame==null || !nativeFlame.IsValid()) && !player.IsDead())player.TakeDamage(2,8,null);
    }
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
        OnGameEvent_map_transition=function(event) {
            if("L4D2MCBridge" in getroottable())L4D2MCBridge.ChapterReward(false);
        },
        OnGameEvent_finale_win=function(event) {
            if("L4D2MCBridge" in getroottable())L4D2MCBridge.ChapterReward(true);
        },
        OnGameEvent_round_start=function(event) {
            if("L4D2MCBridge" in getroottable()) {
                local b=L4D2MCBridge;b.epoch=RandomInt(1,2000000000);b.SurvivalCleanup();
                b.survival.totemPending=null;b.survival.totemHeld=false;b.survival.totemAt=-100.0;
                b.survival.links.clear();
                b.ClearCollision();b.collisionSequence="";
                b.gameplay.content=null;b.gameplay.armed=false;b.gameplay.replies.clear();
            }
        },
        OnGameEvent_tongue_grab=function(event) {
            if(!("L4D2MCBridge" in getroottable()) || !("victim" in event) || !("userid" in event))return;
            local b=L4D2MCBridge,p=GetPlayerFromUserID(event.victim),s=GetPlayerFromUserID(event.userid);
            if(p!=null && s!=null && b.ShieldFacing(p,s))b.ShieldRepel(p,s);
        },
        OnGameEvent_player_incapacitated=function(event) {
            if("L4D2MCBridge" in getroottable() && "userid" in event)L4D2MCBridge.TotemRequest(GetPlayerFromUserID(event.userid));
        },
        OnGameEvent_player_death=function(event) {
            if("L4D2MCBridge" in getroottable() && "userid" in event)L4D2MCBridge.TotemRequest(GetPlayerFromUserID(event.userid));
        },
        OnGameEvent_player_hurt=function(event) {
            if(!("L4D2MCBridge" in getroottable()))return;
            local b=L4D2MCBridge;if(Time()-b.survival.hookLiveAt<0.1 || !b.GameplayLease())return;
            local p=GetPlayerFromUserID(event.userid);b.TotemRequest(p);if(p==null || p!=b.survival.player || p.IsIncapacitated() || p.GetHealth()<=0)return;
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


// Outbox survives the Source VM being recreated at chapter load.
L4D2MCBridge.AtChapterExit <- function(player) {
    local found=false;
    foreach(cls in ["info_changelevel","trigger_changelevel"]) {
        local e=null;
        while((e=Entities.FindByClassname(e,cls))!=null) {
            if(!NetProps.HasProp(e,"m_Collision.m_vecMins") || !NetProps.HasProp(e,"m_Collision.m_vecMaxs"))continue;
            found=true;local p=player.GetOrigin()+Vector(0,0,24),origin=e.GetOrigin();
            local lo=origin+NetProps.GetPropVector(e,"m_Collision.m_vecMins"),hi=origin+NetProps.GetPropVector(e,"m_Collision.m_vecMaxs");
            if(p.x>=lo.x-32 && p.x<=hi.x+32 && p.y>=lo.y-32 && p.y<=hi.y+32 && p.z>=lo.z-32 && p.z<=hi.z+32)return true;
        }
    }
    // Custom maps without a standard changelevel volume rely on the successful transition event.
    return !found;
};
L4D2MCBridge.ChapterReward <- function(finale) {
    local player=survival.player;
    if(player==null || !player.IsValid() || player.GetHealth()<=0 || player.IsIncapacitated() || !gameplay.armed)return;
    if(!finale && !AtChapterExit(player))return;
    local map=Director.GetMapName(),key=map+"_"+epoch;
    local text=FileToString("l4d2mc_rewards.txt"),rows=text!=null?split(text,"\r\n"):[];
    local out=[],found=false;
    foreach(row in rows) {
        local f=split(row," ");if(f.len()!=4)continue;
        if(f[0]==key){found=true;if(finale)row=key+" "+map+" 1 "+f[3];}
        out.append(row);
    }
    if(!found) {
        if(out.len()>=32){printl("[L4D2MC] Reward outbox full; pending entries retained");return;}
        local difficulty=Convars.GetStr("z_difficulty"),bonus=difficulty=="Impossible"?2:difficulty=="Hard"?1:0;
        out.append(key+" "+map+" "+(finale?"1":"0")+" "+bonus);
    }
    local data="";foreach(row in out)data+=row+"\n";StringToFile("l4d2mc_rewards.txt",data);
};
L4D2MCBridge.RewardAck <- function(key) {
    local text=FileToString("l4d2mc_rewards.txt");if(text==null)return;
    local data="";foreach(row in split(text,"\r\n")) {local f=split(row," ");if(f.len()==4 && f[0]!=key)data+=row+"\n";}
    StringToFile("l4d2mc_rewards.txt",data);
};
