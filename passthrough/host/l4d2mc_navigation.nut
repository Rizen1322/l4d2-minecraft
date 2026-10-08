// Bounded read-only search over Source walk connections. Never spawns NPCs.
L4D2MCBridge.navigation <- {jobs={},index=0};
L4D2MCBridge.NavMin <- function(a,b){return a<b?a:b;};
L4D2MCBridge.NavMax <- function(a,b){return a>b?a:b;};
L4D2MCBridge.NavPortal <- function(a,b,dir,width,height) {
    local an=a.GetCorner(0),as=a.GetCorner(2),bn=b.GetCorner(0),bs=b.GetCorner(2);
    local radius=width/2+1,pa=null,pb=null,lo=0.0,hi=0.0,gap=0.0;
    if(dir==0 || dir==2) {
        lo=NavMax(an.x,bn.x);hi=NavMin(as.x,bs.x);
        if(hi-lo<width+2)return null;
        local x=(lo+hi)/2,ma=NavMin(radius,(as.y-an.y)/2),mb=NavMin(radius,(bs.y-bn.y)/2);
        if(dir==0){gap=an.y-bs.y;pa=Vector(x,an.y+ma,0);pb=Vector(x,bs.y-mb,0);}
        else{gap=bn.y-as.y;pa=Vector(x,as.y-ma,0);pb=Vector(x,bn.y+mb,0);}
    } else {
        lo=NavMax(an.y,bn.y);hi=NavMin(as.y,bs.y);
        if(hi-lo<width+2)return null;
        local y=(lo+hi)/2,ma=NavMin(radius,(as.x-an.x)/2),mb=NavMin(radius,(bs.x-bn.x)/2);
        if(dir==1){gap=bn.x-as.x;pa=Vector(as.x-ma,y,0);pb=Vector(bn.x+mb,y,0);}
        else{gap=an.x-bs.x;pa=Vector(an.x+ma,y,0);pb=Vector(bs.x-mb,y,0);}
    }
    // Ground walking only: no ladders, large jumps or one-way cliff drops.
    if(gap>16 || gap < -16)return null;
    pa.z=a.GetZ(pa);pb.z=b.GetZ(pb);
    // Nav stairs may be a sloping approximation of discrete treads. Resolve
    // actual floor locally before testing headroom, rather than start in a tread.
    foreach(p in [pa,pb]) {
        local floor={start=p+Vector(0,0,32),end=p-Vector(0,0,32),ignore=null,mask=16395};TraceLine(floor);
        if(("startsolid" in floor && floor.startsolid) || !("hit" in floor && floor.hit))return null;
        if("enthit" in floor && floor.enthit!=null && floor.enthit.GetName().find("l4d2mc_collision_")==0)return null;
        p.z=floor.pos.z;
    }
    if(pb.z-pa.z>48 || pa.z-pb.z>48)return null;
    foreach(p in [pa,pb]) {
        local t={start=p+Vector(0,0,4),end=p+Vector(0,0,height+2),ignore=null,mask=16395};TraceLine(t);
        if(("startsolid" in t && t.startsolid) || ("hit" in t && t.hit))return null;
    }
    return [pa,pb];
};
L4D2MCBridge.NavRequest <- function(f,player) {
    if(f.len()!=11)return;
    local id=Integer(f[1]),q=Integer(f[2]);
    local p=Vector(Number(f[3]),Number(f[4]),Number(f[5]));
    local goal=Vector(Number(f[6]),Number(f[7]),Number(f[8]));
    local width=Number(f[9],512),height=Number(f[10],512);
    if(width<=0 || height<=0 || (p-player.GetOrigin()).Length()>2048 || (goal-p).Length()>4096)return;
    if(id in navigation.jobs && navigation.jobs[id].q==q){navigation.jobs[id].heard=Time();return;}
    if(!(id in navigation.jobs) && navigation.jobs.len()>=12)return;
    local job={q=q,heard=Time(),from=p,goal=goal,width=width,height=height,done=false,queue=[],head=0,
        parent={},area={},portal={},start=-1,target=-1,current=null,dir=0,adj=0,started=Time()};
    navigation.jobs[id]<-job;
    if(!("NavMesh" in getroottable())){job.done=true;NavAnswer(id,job,[],false);return;}
    local start=NavMesh.GetNavArea(p+Vector(0,0,16),48),end=NavMesh.GetNavArea(goal+Vector(0,0,16),48);
    if(start==null || end==null){job.done=true;NavAnswer(id,job,[],false);return;}
    job.start=start.GetID();job.target=end.GetID();job.queue.append(start);job.area[job.start]<-start;
    job.parent[job.start]<- -1;
};
L4D2MCBridge.NavAnswer <- function(id,job,points,ok) {
    local los=false;
    if(ok) {
        local t=Raycast(job.from+Vector(0,0,job.height/2),job.goal+Vector(0,0,32),null);
        los=!("hit" in t && t.hit) || ("enthit" in t && IsCombatTarget(t.enthit));
    }
    local text=format("\"t\":\"navpath\",\"id\":%d,\"q\":%d,\"los\":%s,\"origin\":[%.4f,%.4f,%.4f],\"goal\":[%.4f,%.4f,%.4f],\"p\":[",id,job.q,los?"true":"false",
        job.from.x/32,job.from.z/32,-job.from.y/32,job.goal.x/32,job.goal.z/32,-job.goal.y/32);
    for(local i=0;i<points.len() && i<32;i++) {
        local p=points[i];text+=format("%s[%.4f,%.4f,%.4f]",i==0?"":",",p.x/32,p.z/32,-p.y/32);
    }
    Reply(text+"]");
};
L4D2MCBridge.NavTick <- function() {
    local stale=[],ids=[];
    foreach(id,job in navigation.jobs) {
        if(Time()-job.heard>2)stale.append(id);
        else if(!job.done)ids.append(id);
    }
    foreach(id in stale)delete navigation.jobs[id];
    if(ids.len()==0)return;
    // One job/think, at most 16 area expansions and 64 neighbours (up to 256 local traces). No global
    // nav mutation or helper bots; target jobs rotate fairly between mobs.
    local id=ids[navigation.index%ids.len()],job=navigation.jobs[id];navigation.index++;
    if(Time()-job.started>20){job.done=true;NavAnswer(id,job,[],false);return;}
    local expanded=0,checks=0;
    while(expanded<16 && checks<64 && !job.done) {
        if(job.current==null) {
            if(job.head>=job.queue.len()){job.done=true;NavAnswer(id,job,[],false);break;}
            job.current=job.queue[job.head++];job.dir=0;job.adj=0;
        }
        local area=job.current,aid=area.GetID();
        if(aid==job.target) {
            local chain=[],cursor=aid;
            while(cursor!=job.start && cursor in job.parent && chain.len()<512){chain.append(cursor);cursor=job.parent[cursor];}
            if(cursor!=job.start){job.done=true;NavAnswer(id,job,[],false);break;}
            chain.reverse();local points=[];
            foreach(child in chain){foreach(p in job.portal[child]){if(points.len()<32)points.append(p);}}
            if(points.len()<32)points.append(job.goal);
            job.done=true;NavAnswer(id,job,points,true);break;
        }
        if(job.dir>=4){job.current=null;expanded++;continue;}
        local count=area.GetAdjacentCount(job.dir);if(count>512)count=512;
        if(job.adj>=count){job.dir++;job.adj=0;continue;}
        local dir=job.dir,n=job.adj++;checks++;
        local next=area.GetAdjacentArea(dir,n);if(next==null)continue;
        local key=next.GetID();
        if(key in job.parent || job.queue.len()>=512 || next.IsBlocked(2) || next.IsDamaging())continue;
        local portal=NavPortal(area,next,dir,job.width,job.height);if(portal==null)continue;
        job.parent[key]<-aid;job.area[key]<-next;job.portal[key]<-portal;job.queue.append(next);
    }
};
