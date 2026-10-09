// Runs only pure arithmetic using the standalone parser VM, no Source game.
function RandomInt(a,b){return a;}function printl(s){}
::L4D2MCBridge<-{};
dofile("passthrough/host/l4d2mc_survival.nut");
function near(actual,want){if(abs(actual-want)>0.00001)throw "Protection balance regression";}
local zero=[0,0,0,0,0];
near(L4D2MCBridge.ProtectionRatio(20,128,0,0,zero,0,false,true),1);
near(L4D2MCBridge.ProtectionRatio(20,128,15,0,zero,0,false,true),0.48);
near(L4D2MCBridge.ProtectionRatio(100,128,20,8,zero,0,false,true),0.4);
near(L4D2MCBridge.ProtectionRatio(100,128,20,12,zero,0,false,true),0.36);
near(L4D2MCBridge.ProtectionRatio(20,8,20,12,zero,0,false,false),1);
near(L4D2MCBridge.ProtectionRatio(20,8,20,12,[0,20,0,0,0],0,false,false),0.2);
near(L4D2MCBridge.ProtectionRatio(20,8,0,0,zero,0,true,false),0);
near(L4D2MCBridge.ProtectionRatio(20,32,20,12,[0,0,0,16,0],0,false,false),0.36);
near(L4D2MCBridge.ProtectionRatio(20,1048576,20,12,zero,2,false,false),0.6);
// Retail temporary HP stores a historical amount plus a decay timestamp.
// Healing must preserve the current amount, not revive or subtract past decay.
local now=20.0;function Time(){return now;}
::L4D2MCPreviousGameplay<-null;dofile("passthrough/host/l4d2mc_gameplay.nut");
::Convars<-{GetFloat=function(k){return 0.5;}};
class Patient {
    hp=50;maximum=100;buffer=50.0;bufferAt=0.0;
    function GetHealth(){return hp;}function SetHealth(value){hp=value;}
    function IsIncapacitated(){return false;}function IsHangingFromLedge(){return false;}
}
::NetProps<-{
    HasProp=function(p,k){return k=="m_healthBuffer" || k=="m_healthBufferTime" || k=="m_iMaxHealth";},
    GetPropFloat=function(p,k){return k=="m_healthBuffer"?p.buffer:p.bufferAt;},
    SetPropFloat=function(p,k,value){if(k=="m_healthBuffer")p.buffer=value;else p.bufferAt=value;},
    GetPropInt=function(p,k){return p.maximum;}
};
function effective(p){return p.buffer-(Time()-p.bufferAt)*0.5;}
local b=L4D2MCBridge,p=Patient();b.Heal(p,10);
near(p.hp,60);near(effective(p),40);
now=30;near(effective(p),35);now=20;
p.hp=50;p.buffer=50;p.bufferAt=0;
b.Event(["event","1","heal","10"],p);near(p.hp,60);near(effective(p),40);
p.hp=20;p.buffer=50;p.bufferAt=0;
b.Event(["event","2","meal","4","1"],p);near(effective(p),60);
p.hp=20;p.buffer=5;p.bufferAt=0;
b.Event(["event","3","meal","4","1"],p);near(effective(p),20);
p.maximum=200;p.hp=150;p.buffer=50;p.bufferAt=0;
b.Event(["event","4","meal","4","1"],p);near(effective(p),50);
p.maximum=100;p.hp=99;p.buffer=50;p.bufferAt=0;b.Heal(p,10);
near(p.hp,100);near(effective(p),0);
p.hp=0;p.buffer=0;p.bufferAt=20;
b.Event(["event","5","meal","4","1"],p);near(p.buffer,0);
print("Source protection arithmetic passed\n");
