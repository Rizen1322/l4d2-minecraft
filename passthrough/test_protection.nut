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
print("Source protection arithmetic passed\n");
