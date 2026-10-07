::MCSandbox <- {
    Model = "models/l4d2mc/cube.mdl",
    Blocks = {},
    Selected = {},
    LastEdit = {},
    Pending = null,
    Range = 192.0,
    EntityCeiling = 1700,
    NextAnnouncement = 0.0,
    function Log(text) { printl("[L4D2MC] " + text); },
    function Reply(player,text) {
        if (player!=null && player.IsValid()) ClientPrint(player,3,"[Blocks] " + text);
        Log(text);
    },
    function ValidPlayer(player) {
        return player!=null && player.IsValid() && player.IsSurvivor() && !IsPlayerABot(player)
            && !player.IsDead() && !player.IsIncapacitated() && !player.IsHangingFromLedge();
    },
    function Material(player) {
        local id=player.GetPlayerUserId();
        return (id in Selected) ? Selected[id] : "dirt";
    },
    function Rows() {
        local rows=[];
        foreach(k,r in Blocks) rows.append({x=r.x,y=r.y,z=r.z,type=r.type});
        rows.sort(function(a,b) {
            if (a.x!=b.x) return a.x<b.x ? -1:1;
            if (a.y!=b.y) return a.y<b.y ? -1:1;
            if (a.z!=b.z) return a.z<b.z ? -1:1;
            return 0;
        });
        return rows;
    },
    function EntityCount() {
        local ent=null,count=0;
        while ((ent=Entities.Next(ent))!=null) {
            ++count;
            if (count>=EntityCeiling) break;
        }
        return count;
    },
    function WorldTrace(a,b,ignore=null) {
        local trace={start=a,end=b,mask=33636363,ignore=ignore};
        TraceLine(trace);
        return trace;
    },
    function BoxFree(row) {
        local lo=::MCGrid.Minimum(row),hi=lo+Vector(32,32,32);
        local ent=null;
        while ((ent=Entities.FindByClassname(ent,"player"))!=null) {
            if (ent.IsDead()) continue;
            local at=ent.GetOrigin();
            local mins=Vector(-16,-16,0),maxs=Vector(16,16,72);
            try {
                mins=NetProps.GetPropVector(ent,"m_Collision.m_vecMins");
                maxs=NetProps.GetPropVector(ent,"m_Collision.m_vecMaxs");
            } catch(e) {}
            mins=mins+at;maxs=maxs+at;
            if (lo.x<maxs.x && hi.x>mins.x && lo.y<maxs.y && hi.y>mins.y && lo.z<maxs.z && hi.z>mins.z)
                throw "A player occupies this cell";
        }
        // L4D2 has no TraceHull VScript API. Sample the volume along all three axes,
        // not just corners. Thin off-grid geometry can still fall between probes.
        foreach(a in [0.25,8.0,16.0,24.0,31.75]) foreach(b in [0.25,8.0,16.0,24.0,31.75]) {
            foreach(axis in ["x","y","z"]) {
                local start=lo+Vector(a,b,0.25),end=lo+Vector(a,b,31.75);
                if (axis=="x") {start=lo+Vector(0.25,a,b);end=lo+Vector(31.75,a,b);}
                if (axis=="y") {start=lo+Vector(a,0.25,b);end=lo+Vector(a,31.75,b);}
                local t=WorldTrace(start,end);
                if (t.hit || t.fraction<0.999) throw "Cell intersects map geometry or another object";
            }
        }
        // Avoid obstructing checkpoint doors, independently of the current aim target.
        ent=null;
        while ((ent=Entities.FindByClassname(ent,"prop_door_rotating_checkpoint"))!=null)
            if ((ent.GetOrigin()-::MCGrid.Center(row)).Length()<96) throw "Keep the saferoom doorway clear";
        return true;
    },
    function Add(row) {
        local key=::MCGrid.Key(row.x,row.y,row.z);
        if (key in Blocks) throw "Cell already occupied";
        if (Blocks.len()>=::MCGrid.Limit || EntityCount()>=EntityCeiling) throw "Block/entity limit reached";
        ::MCGrid.Integer(row.x.tostring());::MCGrid.Integer(row.y.tostring());::MCGrid.Integer(row.z.tostring());
        if (!(row.type in ::MCGrid.Types)) throw "Unknown material";
        BoxFree(row);
        local name=UniqueString("l4d2mc_");
        local ent=SpawnEntityFromTable("prop_dynamic_override", {
            model=Model,origin=::MCGrid.Center(row),angles=Vector(0,0,0),
            skin=::MCGrid.Types[row.type],solid=6,targetname=name,
            disableshadows=0,DisableBoneFollowers=1
        });
        if (ent==null || !ent.IsValid()) throw "Cube could not be created";
        // The registered handle + unique target name protect against entity index reuse.
        Blocks[key]<-{x=row.x,y=row.y,z=row.z,type=row.type,entity=ent,name=name};
        return key;
    },
    function Remove(key) {
        if (!(key in Blocks)) throw "Block no longer exists";
        local r=Blocks[key];
        if (r.entity!=null && r.entity.IsValid() && r.entity.GetName()==r.name) r.entity.Kill();
        delete Blocks[key];
    },
    function Aim(player) {
        local start=player.EyePosition(),dir=player.EyeAngles().Forward();
        local world=WorldTrace(start,start+dir*Range,player);
        local endDistance=world.hit ? (world.pos-start).Length()+0.5 : Range;
        local best=null;
        foreach(key,row in Blocks) {
            if (!row.entity.IsValid() || row.entity.GetName()!=row.name) continue;
            local hit=::MCGrid.RayBox(start,dir,::MCGrid.Minimum(row),Range);
            if (hit!=null && hit.distance<=endDistance && (best==null || hit.distance<best.distance)) {
                hit.key<-key;best=hit;
            }
        }
        return {world=world,block=best,start=start,dir=dir};
    },
    function Placement(player) {
        local aim=Aim(player);
        if (aim.block!=null) {
            local r=Blocks[aim.block.key],n=aim.block.normal;
            if (n.Length()<0.5) throw "Move outside the selected block";
            return {x=r.x+n.x.tointeger(),y=r.y+n.y.tointeger(),z=r.z+n.z.tointeger(),type=Material(player)};
        }
        if (!aim.world.hit) throw "Aim at a nearby floor or block";
        if (aim.world.enthit!=null && aim.world.enthit.GetClassname()!="worldspawn")
            throw "Aim at the map floor or a sandbox block";
        local pos=aim.world.pos;
        // Seed blocks on horizontal map floors; other faces are built from existing cubes.
        // Two lateral floor probes reject walls and steep slopes without a trace normal API.
        foreach(offset in [Vector(2,0,0),Vector(0,2,0)]) {
            local t=WorldTrace(pos+offset+Vector(0,0,4),pos+offset-Vector(0,0,4),player);
            if (!t.hit || fabs(t.pos.z-pos.z)>0.75) throw "Start your build on a flat floor";
        }
        return {x=::MCGrid.Cell(pos.x),y=::MCGrid.Cell(pos.y),z=ceil((pos.z-0.01)/32.0).tointeger(),type=Material(player)};
    },
    function Save(player) {
        if (Pending!=null) throw "Wait for loading to finish";
        local map=::MCGrid.MapName(Director.GetMapName()),file="l4d2mc/"+map+".blocks";
        local current=FileToString(file),next=::MCGrid.Encode(map,Rows());
        if (current!=null) {
            local valid=false;
            try {::MCGrid.Decode(current,map);valid=true;} catch(e) {}
            if (valid && (!StringToFile(file+".bak",current) || FileToString(file+".bak")!=current))
                throw "Backup write failed; save left unchanged";
        }
        if (!StringToFile(file,next) || FileToString(file)!=next) throw "Save write failed; previous backup remains";
        Reply(player,"Saved "+Blocks.len()+" blocks on "+map);
    },
    function Load(player,backup=false) {
        if (Pending!=null || Blocks.len()!=0) throw "Load requires an empty sandbox; restart the map first";
        local map=::MCGrid.MapName(Director.GetMapName());
        local file="l4d2mc/"+map+".blocks"+(backup ? ".bak" : "");
        local text=FileToString(file);
        if (text==null) throw "No save for this map";
        local rows=null;
        try { rows=::MCGrid.Decode(text,map); }
        catch(e) {throw "Invalid save: "+e+". Try !mc backup to load the previous copy";}
        // Validate data before changing any entities. Placement is validated during each Add.
        Pending={rows=rows,index=0,created=[],player=player};
        Reply(player,"Loading "+rows.len()+" blocks...");
    },
    function Update() {
        if (Pending==null) return;
        local job=Pending;
        try {
            for(local step=0;step<4 && job.index<job.rows.len();++step) {
                job.created.append(Add(job.rows[job.index]));++job.index;
            }
            if (job.index==job.rows.len()) {Pending=null;Reply(job.player,"Loaded "+job.created.len()+" blocks");}
        } catch(e) {
            foreach(key in job.created) Remove(key);
            Pending=null;Reply(job.player,"Load rolled back: "+e+". Move away from the saved build and retry");
        }
    },
    function Command(player,args) {
        if (!ValidPlayer(player)) {Reply(player,"Only active human survivors can build");return;}
        if (args.len()==0) args=["help"];
        local cmd=args[0].tolower();
        try {
            if (cmd=="help") {
                Reply(player,"!mc place | break | type dirt/stone/wood | save | load | status");
                Reply(player,"Console: scripted_user_func place. Optional keys: exec l4d2mc_keys");return;
            }
            if (cmd=="status") {Reply(player,Material(player)+" | "+Blocks.len()+"/128 blocks | "+Director.GetMapName());return;}
            if (cmd=="type") {
                if (args.len()!=2 || !(args[1].tolower() in ::MCGrid.Types)) throw "Use !mc type dirt, stone or wood";
                Selected[player.GetPlayerUserId()]<-args[1].tolower();Reply(player,"Selected "+Material(player));return;
            }
            if (cmd=="next") {
                local list=["dirt","stone","wood"],id=::MCGrid.Types[Material(player)];
                Selected[player.GetPlayerUserId()]<-list[(id+1)%3];Reply(player,"Selected "+Material(player));return;
            }
            if (cmd=="save") {Save(player);return;}
            if (cmd=="load" || cmd=="backup") {Load(player,cmd=="backup");return;}
            if (cmd!="place" && cmd!="break") throw "Unknown command. Type !mc help";
            if (Pending!=null) throw "Wait for loading to finish";
            local id=player.GetPlayerUserId(),now=Time();
            if (id in LastEdit && now-LastEdit[id]<0.15) return;
            LastEdit[id]<-now;
            if (cmd=="place") {Add(Placement(player));Reply(player,"Placed "+Material(player)+" ("+Blocks.len()+"/128)");}
            else {
                local aim=Aim(player);
                if (aim.block==null) throw "Aim at a sandbox block within reach";
                Remove(aim.block.key);Reply(player,"Block removed ("+Blocks.len()+"/128)");
            }
        } catch(e) {Reply(player,e.tostring());}
    },
    function Chat(message,player) {
        if (player==null) return true;
        local text=strip(message);
        local prefix=player.GetPlayerName()+": ",at=text.find(prefix);
        if (at!=null) text=strip(text.slice(at+prefix.len()));
        // Engine chat strings may include a trailing newline.
        local args=split(text," \t\r\n");
        if (args.len()==0 || args[0].tolower()!="!mc") return true;
        args.remove(0);Command(player,args);return false;
    },
    function Welcome() {
        PrecacheModel(Model);
        local p=null;
        while ((p=Entities.FindByClassname(p,"player"))!=null)
            if (!IsPlayerABot(p)) Reply(p,"Block Sandbox ready. Type !mc help. Build on a flat floor.");
    }
};
PrecacheModel(::MCSandbox.Model);
