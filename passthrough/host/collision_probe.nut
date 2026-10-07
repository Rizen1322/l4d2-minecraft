local key = "20 90 -176";
if (!(key in L4D2MCBridge.blocks)) throw "test collider absent";
local block = L4D2MCBridge.blocks[key];
local at = block.GetOrigin();
local t = { start=at+Vector(-24,0,0),end=at+Vector(24,0,0),mask=33636363 };
TraceLine(t);
if (!("enthit" in t) || t.enthit != block) throw "trace did not hit Minecraft collider";
if (fabs(t.pos.x-(at.x-16.25)) > 0.5) throw "wrong collider face";
printl("[L4D2MC COLLISION TEST] PASS real Minecraft block has a Source collision prop, face="+t.pos.x);
