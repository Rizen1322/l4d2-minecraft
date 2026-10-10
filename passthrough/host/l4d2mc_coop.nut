// Server-side context routing. Only this listen server runs gameplay scripts.
L4D2MCBridge.CoopClone <- function(value) {
    if(typeof value=="table"){local out={};foreach(k,v in value)out[k]<-CoopClone(v);return out;}
    if(typeof value=="array"){local out=[];foreach(v in value)out.append(CoopClone(v));return out;}
    return value;
};
L4D2MCBridge.CoopListenHost <- function() {
    return "GetListenServerHost" in getroottable()?GetListenServerHost():null;
};
L4D2MCBridge.CoopUserId <- function(player) {
    if(player==null || !player.IsValid())return 0;
    try{local id=player.GetPlayerUserId();return id>=1 && id<=65535?id:0;}catch(error){return 0;}
};
L4D2MCBridge.CoopContext <- function(player,localPlayer=false) {
    local id=CoopUserId(player);if(id==0)return null;
    if(localPlayer){coop.localContext.player=player;coop.localContext.userid=id;return coop.localContext;}
    if(id in coop.contexts && coop.contexts[id].player!=player){
        CoopWith(coop.contexts[id],function(){RestoreAppearance();});delete coop.contexts[id];
    }
    if(!(id in coop.contexts)) {
        if(coop.contexts.len()>=4)return null;
        local g=CoopClone(coop.gameplayTemplate),s=CoopClone(coop.survivalTemplate);
        foreach(k in ["hidden","frozen","movement","forced","actors","projectiles","replies","physics"])if(k in g)g[k].clear();
        g.content=null;g.armed=false;g.at=-100.0;g.generation="";g.lastEvent=0;g.wheel=0;g.nativeUseDown=false;
        g.consuming<-false;g.consumeAt<--100.0;
        if("ground" in g)g.ground.clear();
        s.player=player;
        coop.contexts[id]<-{userid=id,player=player,gameplay=g,survival=s,navigation={jobs={},index=0},active=false};
    }
    return coop.contexts[id];
};
L4D2MCBridge.CoopWith <- function(context,work) {
    if(context==null || coop.current==context)return work.bindenv(this)();
    local b=this,g=gameplay,s=survival,n=navigation,previous=coop.current,result=null;
    gameplay=context.gameplay;survival=context.survival;navigation=context.navigation;coop.current=context;
    local restore=function(){
        context.gameplay=b.gameplay;context.survival=b.survival;context.navigation=b.navigation;
        b.gameplay=g;b.survival=s;b.navigation=n;b.coop.current=previous;
    };
    try{result=work.bindenv(this)();}catch(error){restore();throw error;}
    restore();return result;
};
L4D2MCBridge.CoopForPlayer <- function(player) {
    if(player==null || !("coop" in this))return null;
    if(player==CoopListenHost())return CoopContext(player,true);
    local id=CoopUserId(player);
    return id in coop.contexts && coop.contexts[id].player==player?coop.contexts[id]:null;
};
L4D2MCBridge.CoopReadSessions <- function() {
    local text=FileToString("l4d2mc_coop_sessions.txt"),valid=false,wanted={};
    if(text!=null && text.len()<=1024)try {
        local lines=split(text,"\r\n");
        if(lines.len()>=2 && lines.len()<=6) {
            local header=split(lines[0]," ");
            if(header.len()==2 && header[0]==epoch.tostring() && header[1].len()>0 && header[1].len()<=32 && CompleteMailbox(lines,header[1])) {
                valid=true;
                foreach(ch in header[1])if(ch<48 || ch>57)valid=false;
                for(local i=1;i<lines.len()-1;i++) {
                    local id=Integer(lines[i]);
                    if(id<1 || id>65535 || id in wanted){valid=false;break;}
                    wanted[id]<-true;
                }
            }
        }
    }catch(error){valid=false;}
    if(valid && text!=coop.manifest){coop.manifest=text;coop.lease=Time();coop.allowed=wanted;}
    if(Time()-coop.lease>0.75)coop.allowed.clear();
};
L4D2MCBridge.CoopCleanupAll <- function() {
    if(!("coop" in this))return;
    if("FlightCleanup" in this)FlightCleanup(null);
    foreach(id,ctx in coop.contexts)CoopWith(ctx,function(){RestoreAppearance();gameplay.armed=false;gameplay.content=null;});
    coop.contexts.clear();coop.allowed.clear();coop.manifest=null;coop.lease=-100.0;
};
L4D2MCBridge.CoopTick <- function(host) {
    CoopReadSessions();
    local present={},e=null;
    while((e=Entities.FindByClassname(e,"player"))!=null) {
        if(e==host || IsPlayerABot(e) || !e.IsSurvivor())continue;
        local ctx=CoopContext(e);if(ctx==null)continue;present[ctx.userid]<-true;
        local allowed=ctx.userid in coop.allowed;
        if(allowed) {
            ctx.active=true;
            CoopWith(ctx,function(){
                if(!ReadGameplay(ctx.player,format("l4d2mc_coop_%d.txt",ctx.userid)))RestoreAppearance();
            });
        } else if(ctx.active) {
            CoopWith(ctx,function(){RestoreAppearance();gameplay.armed=false;gameplay.content=null;});ctx.active=false;
        }
    }
    local gone=[];foreach(id,ctx in coop.contexts)if(!(id in present))gone.append(id);
    foreach(id in gone){CoopWith(coop.contexts[id],function(){RestoreAppearance();});delete coop.contexts[id];}
};
L4D2MCBridge.CoopExport <- function(host) {
    local localId=CoopUserId(host),rows=[],e=null;
    // Solo sessions have no room reader: skip the second full pose build and file write.
    local remote=false;
    while((e=Entities.FindByClassname(e,"player"))!=null)
        if(e!=host && e.IsSurvivor() && !IsPlayerABot(e)){remote=true;break;}
    if(!remote)return;
    if(host!=null && host.IsValid() && host.IsSurvivor() && !IsPlayerABot(host))rows.append(CoopContext(host,true));
    foreach(id,ctx in coop.contexts)if(ctx.player.IsValid() && ctx.player.IsSurvivor() && !IsPlayerABot(ctx.player) && rows.len()<4)rows.append(ctx);
    local out=format("{\"map\":%s,\"epoch\":%d,\"frame\":%d,\"local_id\":%d,\"players\":[",HudJsonString(Director.GetMapName()),epoch,frame,localId),n=0;
    foreach(ctx in rows) {
        local name="player";try{name=ctx.player.GetPlayerName();}catch(error){}
        if(name.len()>96)name=name.slice(0,96);
        // The host pose was already built this tick for l4d2mc_pose.txt.
        local pose=("hostPose" in this && hostPose!=null && hostPoseFrame==frame && ctx.player==host)?hostPose:
            CoopWith(ctx,function(){return ActorPoseJson(ctx.player);});
        if(pose.len()>32768)continue;
        local active=CoopWith(ctx,function(){return GameplayLease();});
        out+=(n++==0?"":",")+format("{\"userid\":%d,\"idEnt\":%d,\"name\":%s,\"active\":%s,\"pose\":%s}",ctx.userid,ctx.player.GetEntityIndex(),HudJsonString(name),active?"true":"false",pose);
    }
    out+="]}";if(out.len()<=131072)StringToFile("l4d2mc_coop_pose.txt",out);
};
L4D2MCBridge.CoopWrapEvents <- function(scope) {
    foreach(name,callback in scope) {
        if(typeof callback!="function" || name.find("OnGameEvent_")!=0)continue;
        local original=callback,eventName=name,eventScope=scope;
        scope[name]=function(event){
            if(!("L4D2MCBridge" in getroottable()))return;
            local b=L4D2MCBridge;if(!("coop" in b)){original.call(eventScope,event);return;}
            if(eventName=="OnGameEvent_round_start") {
                b.CoopWith(b.coop.localContext,function(){original.call(eventScope,event);});b.CoopCleanupAll();return;
            }
            if(eventName=="OnGameEvent_map_transition" || eventName=="OnGameEvent_finale_win") {
                b.CoopWith(b.coop.localContext,function(){original.call(eventScope,event);});
                foreach(id,ctx in b.coop.contexts)if(ctx.active)b.CoopWith(ctx,function(){original.call(eventScope,event);});return;
            }
            local id=0;if("victim" in event)id=event.victim;else if("userid" in event)id=event.userid;else if("attacker" in event)id=event.attacker;
            local p=id>0?GetPlayerFromUserID(id):null,ctx=b.CoopForPlayer(p);
            if(ctx!=null)b.CoopWith(ctx,function(){original.call(eventScope,event);});
            else b.CoopWith(b.coop.localContext,function(){original.call(eventScope,event);});
        };
    }
};
L4D2MCBridge.CoopOutbox <- function(kind) {
    if(coop.current==null || coop.current==coop.localContext)return "l4d2mc_"+kind+".txt";
    return format("l4d2mc_coop_%d_%s.txt",coop.current.userid,kind);
};
L4D2MCBridge.CoopInstallOutboxes <- function() {
    QueuePickup=function(key,kind){
        local path=CoopOutbox("pickups"),text=FileToString(path);if(text==null)text="";
        local rows=split(text,"\r\n");if(rows.len()>=64)return false;
        foreach(row in rows){local f=split(row," ");if(f.len()==2 && f[0]==key)return true;}
        StringToFile(path,text+key+" "+kind+"\n");
        local saved=FileToString(path);return saved!=null && saved.find(key+" "+kind)!=null;
    };
    PickupAck=function(key){
        local path=CoopOutbox("pickups"),text=FileToString(path);if(text==null)return;
        local out="";foreach(row in split(text,"\r\n")){local f=split(row," ");if(f.len()==2 && f[0]!=key)out+=row+"\n";}StringToFile(path,out);
    };
    ChapterReward=function(finale){
        local player=survival.player;
        if(player==null || !player.IsValid() || player.GetHealth()<=0 || player.IsIncapacitated() || !gameplay.armed || (!finale && !AtChapterExit(player)))return;
        local path=CoopOutbox("rewards"),map=Director.GetMapName(),key=map+"_"+epoch;
        local text=FileToString(path);
        local rows=[];
        if(text!=null)rows=split(text,"\r\n");
        local out=[];
        local found=false;
        foreach(row in rows){
            local f=split(row," ");
            if(f.len()!=4)continue;
            local value=row;
            if(f[0]==key){
                found=true;
                if(finale)value=key+" "+map+" 1 "+f[3];
            }
            out.append(value);
        }
        if(!found){
            if(out.len()>=32)return;
            local d=Convars.GetStr("z_difficulty");
            local difficulty=0;
            if(d=="Impossible")difficulty=2;
            else if(d=="Hard")difficulty=1;
            local finaleFlag="0";
            if(finale)finaleFlag="1";
            out.append(key+" "+map+" "+finaleFlag+" "+difficulty);
        }
        local data="";foreach(row in out)data+=row+"\n";StringToFile(path,data);
    };
    RewardAck=function(key){
        local path=CoopOutbox("rewards"),text=FileToString(path);if(text==null)return;
        local out="";foreach(row in split(text,"\r\n")){local f=split(row," ");if(f.len()==4 && f[0]!=key)out+=row+"\n";}StringToFile(path,out);
    };
};
L4D2MCBridge.CoopInit <- function() {
    coop<-{current=null,contexts={},allowed={},manifest=null,lease=-100.0,
        gameplayTemplate=CoopClone(gameplay),survivalTemplate=CoopClone(survival),
        localContext={userid=0,player=null,gameplay=gameplay,survival=survival,navigation=navigation,active=true}};
    local originalUse=NativeUse;
    NativeUse=function(pressed){
        if(coop.current==null || coop.current==coop.localContext){originalUse.call(this,pressed);return;}
        // Remote Python drives that player's own Source client +use command.
        // Never send a peer's use to the listen host's console.
        gameplay.nativeUseDown=pressed;
    };
    if("Protection" in this){local original=Protection;Protection=function(p,a,d,t){
        local ctx=CoopForPlayer(p);if(ctx==null || coop.current==ctx)return original.call(this,p,a,d,t);
        return CoopWith(ctx,function(){survival.hookLiveAt=Time();return original.call(this,p,a,d,t);});
    };}
    if("QueuePickup" in this)CoopInstallOutboxes();
};
