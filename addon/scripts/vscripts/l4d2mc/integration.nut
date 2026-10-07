// Explicit private oracle. Excluded from the VPK. No automatic player tests.
IncludeScript("l4d2mc/tests",getroottable());
::MCIntegration <- {
    function Assert(ok,message) {if(!ok) throw "ASSERT: "+message;},
    function Human() {
        local p=null;
        while((p=Entities.FindByClassname(p,"player"))!=null)
            if(!IsPlayerABot(p) && p.IsSurvivor()) return p;
        throw "No human survivor";
    },
    function Clear() {
        local keys=[];foreach(k,v in ::MCSandbox.Blocks) keys.append(k);
        foreach(k in keys) ::MCSandbox.Remove(k);
    },
    function Run() {
        Assert("MCSandbox" in getroottable(),"mutation must be loaded");
        Assert(Director.GetGameMode()=="mcblocks","real mcblocks mutation is active");
        Assert("UserConsoleCommand" in g_ModeScript,"player command callback is registered");
        local p=Human(),sandbox=::MCSandbox;
        Assert(!p.IsDead() && !p.IsIncapacitated(),"human must be alive");
        local origin=p.GetOrigin(),candidate=null;
        for(local x=-6;x<=6 && candidate==null;x++) for(local y=-6;y<=6 && candidate==null;y++) {
            if(fabs(x)<3 && fabs(y)<3) continue;
            local spot=origin+Vector(x*32,y*32,100);
            local trace=sandbox.WorldTrace(spot,spot-Vector(0,0,256),p);
            if(!trace.hit) continue;
            local row={x=::MCGrid.Cell(spot.x),y=::MCGrid.Cell(spot.y),z=ceil((trace.pos.z-0.01)/32).tointeger(),type="dirt"};
            try {sandbox.BoxFree(row);candidate=row;}catch(e){}
        }
        Assert(candidate!=null,"open test cell found");
        Clear();
        local key=sandbox.Add(candidate),r=sandbox.Blocks[key],center=::MCGrid.Center(r);
        local trace=sandbox.WorldTrace(center-Vector(64,0,0),center+Vector(64,0,0),p);
        Assert(trace.hit && trace.enthit==r.entity,"physical cube is hit by an engine trace");
        Assert(fabs(trace.pos.x-(center.x-16))<0.5,"collision matches the cube face");
        Assert(NetProps.GetPropInt(r.entity,"m_nSkin")==0,"dirt skin");
        local occupied=false;try {sandbox.Add(candidate);}catch(e){occupied=true;}
        Assert(occupied,"duplicate placement refuses");
        local stacked={x=r.x,y=r.y,z=r.z+1,type="stone"};
        local topkey=sandbox.Add(stacked);
        Assert(NetProps.GetPropInt(sandbox.Blocks[topkey].entity,"m_nSkin")==1,"stone skin");
        local upper={x=r.x,y=r.y,z=r.z+2,type="wood"};
        local upperkey=sandbox.Add(upper);
        Assert(NetProps.GetPropInt(sandbox.Blocks[upperkey].entity,"m_nSkin")==2,"wood skin");
        sandbox.Save(p);
        local saved=::MCGrid.Decode(FileToString("l4d2mc/"+Director.GetMapName()+".blocks"),Director.GetMapName());
        Assert(saved.len()==3,"all three materials saved");
        local count=sandbox.Blocks.len();sandbox.Command(p,["load"]);
        Assert(sandbox.Blocks.len()==count,"load cannot erase a nonempty build");
        sandbox.Remove(topkey);
        Assert(sandbox.Blocks.len()==2,"removal updates the state");
        Clear();
        // Engine removes killed entities at the next frame. Continue from a think.
        ::MCIntegrationState <- {player=p,row=candidate,stage=0,started=Time(),savedOrigin=origin};
        local controller=SpawnEntityFromTable("info_target",{targetname="l4d2mc_private_test"});
        controller.ValidateScriptScope();
        controller.GetScriptScope().MCIntegrationThink <- function() {
            return ::MCIntegration.Tick(self);
        };
        AddThinkToEnt(controller,"MCIntegrationThink");
        printl("[L4D2MC TEST] SPAWN COLLISION MATERIALS DELETE SAVE PASS base="+center);
    },
    function Tick(controller) {
        local s=::MCIntegrationState,p=s.player,box=::MCSandbox;
        try {
            if(s.stage==0) {
                box.Load(p);s.stage=1;
            } else if(s.stage==1) {
                box.Update();
                if(box.Pending==null) {
                    Assert(box.Blocks.len()==3,"load restores all cubes");
                    printl("[L4D2MC TEST] LOAD PASS");
                    local c=::MCGrid.Center(s.row);
                    p.SetOrigin(c+Vector(0,0,84));p.SetVelocity(Vector(0,0,0));
                    s.started=Time();s.stage=2;
                }
            } else if(s.stage==2 && Time()-s.started>1.5) {
                local feet=p.GetOrigin(),top=::MCGrid.Minimum(s.row).z+96;
                Assert(fabs(feet.z-top)<2.0,"player stands on the stacked cubes");
                printl("[L4D2MC TEST] STANDING PASS feet="+feet);
                p.SetOrigin(s.savedOrigin);p.SetVelocity(Vector(0,0,0));
                printl("[L4D2MC TEST] INTEGRATION PASS");controller.Kill();return 0.1;
            }
        }catch(e) {
            printl("[L4D2MC TEST] INTEGRATION FAIL: "+e);
            if(p!=null && p.IsValid()) p.SetOrigin(s.savedOrigin);
            controller.Kill();
        }
        return 0.1;
    }
};
try {::MCIntegration.Run();}catch(e){printl("[L4D2MC TEST] INTEGRATION FAIL: "+e);}
