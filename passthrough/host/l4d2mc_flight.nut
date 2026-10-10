// Source owns position, aiming, WALK movement and native collision. Only velocity changes.
L4D2MCBridge.flight <- {players={}};
L4D2MCBridge.FlightCleanup <- function(player=null) {
    local remove=[];
    foreach(id,v in flight.players)if(player==null || v.entity==player) {
        if(v.active && v.entity.IsValid())v.entity.SetGravity(v.gravity);
        remove.append(id);
    }
    foreach(id in remove)delete flight.players[id];
};
L4D2MCBridge.Flight <- function(f,player) {
    if(f.len()!=5 || player==null || !player.IsValid())return;
    local on=Integer(f[1]),elytra=Integer(f[2]),seq=Integer(f[3]),boosting=Integer(f[4]);
    if(on<0 || on>1 || elytra<0 || elytra>1 || seq<0 || boosting<0 || boosting>1)return;
    local id=player.GetEntityIndex();
    if(id in flight.players && flight.players[id].entity!=player)FlightCleanup(flight.players[id].entity);
    if(!(id in flight.players)) {
        if(flight.players.len()>=8)return;
        flight.players[id]<-{entity=player,on=false,elytra=false,boosting=false,seq=0,at=Time(),active=false,gravity=0.0,stepAt=Time()};
    }
    local v=flight.players[id];v.at=Time();v.on=on==1;v.elytra=elytra==1;
    if(seq>=v.seq){v.seq=seq;v.boosting=boosting==1 && seq>0;}
    if(!v.on || !v.elytra)v.boosting=false;
};
L4D2MCBridge.FlightBlocked <- function(player) {
    if(!GameplayLease() || player.IsDead() || player.IsIncapacitated() || player.IsHangingFromLedge())return true;
    if(!NetProps.HasProp(player,"m_fFlags") || !NetProps.HasProp(player,"m_flGravity"))return true;
    // Ground, GUI freeze, water and native infected pins retain normal Source movement.
    if((NetProps.GetPropInt(player,"m_fFlags")&(1|32))!=0)return true;
    if(NetProps.HasProp(player,"m_nWaterLevel") && NetProps.GetPropInt(player,"m_nWaterLevel")>1)return true;
    if(NetProps.HasProp(player,"m_MoveType") && NetProps.GetPropInt(player,"m_MoveType")!=2)return true;
    foreach(prop in ["m_tongueOwner","m_pounceAttacker","m_jockeyAttacker","m_carryAttacker","m_pummelAttacker"])
        if(NetProps.HasProp(player,prop) && NetProps.GetPropEntity(player,prop)!=null)return true;
    return false;
};
L4D2MCBridge.FlightStep <- function(velocity,look,pitch,boosting) {
    // Mapped Minecraft26.3 constants, in Source axes. 32 units/block, 20 ticks/s.
    local x=velocity.x/640,y=velocity.y/640,z=velocity.z/640;
    local horizontal=sqrt(look.x*look.x+look.y*look.y),speed=sqrt(x*x+y*y);
    local radians=pitch*0.0174532925199433,lift=cos(radians);lift*=lift;
    z+=0.08*(-1+lift*0.75);
    if(z<0 && horizontal>0.00001) {
        local dive=-z*0.1*lift;x+=look.x*dive/horizontal;y+=look.y*dive/horizontal;z+=dive;
    }
    if(pitch<0 && horizontal>0.00001) {
        local climb=speed*(-sin(radians))*0.04;
        x-=look.x*climb/horizontal;y-=look.y*climb/horizontal;z+=climb*3.2;
    }
    if(horizontal>0.00001) {
        x+=(look.x/horizontal*speed-x)*0.1;y+=(look.y/horizontal*speed-y)*0.1;
    }
    x*=0.99;y*=0.99;z*=0.98;
    if(boosting){x+=look.x*0.1+(look.x*1.5-x)*0.5;y+=look.y*0.1+(look.y*1.5-y)*0.5;z+=look.z*0.1+(look.z*1.5-z)*0.5;}
    local v=Vector(x*640,y*640,z*640),length=v.Length();
    return length>1600?v*(1600/length):v;
};
L4D2MCBridge.FlightTick <- function(player) {
    if(player==null || !player.IsValid())return;
    local id=player.GetEntityIndex();if(!(id in flight.players))return;
    local v=flight.players[id];
    if(v.entity!=player || !v.on || !v.elytra || Time()-v.at>0.5 || FlightBlocked(player)){FlightCleanup(v.entity);return;}
    if(!v.active) {
        v.gravity=NetProps.GetPropFloat(player,"m_flGravity");v.active=true;v.stepAt=Time();
        // In Source gravity0 means default1. Tiny positive avoids double gravity.
        player.SetGravity(0.001);
    }
    local elapsed=Time()-v.stepAt;if(elapsed<0.05)return;
    local steps=(elapsed/0.05).tointeger();if(steps>4)steps=4;
    v.stepAt=Time()-(elapsed%0.05);
    // Re-read native collision-clipped velocity, never integrate/correct position.
    local velocity=player.GetVelocity(),angles=player.EyeAngles(),look=angles.Forward();
    for(local i=0;i<steps;i++)velocity=FlightStep(velocity,look,angles.x,v.boosting);
    player.SetVelocity(velocity);
};
L4D2MCBridge.FlightActive <- function(player) {
    if(player==null || !player.IsValid())return false;
    local id=player.GetEntityIndex();
    return id in flight.players && flight.players[id].entity==player && flight.players[id].active
        && Time()-flight.players[id].at<=0.5 && !FlightBlocked(player);
};
