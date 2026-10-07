// Run explicitly with script_execute l4d2mc/tests. Never loaded by normal play.
function MCAssert(ok, message) {
    if (!ok) throw "ASSERT: " + message;
}
function MCRunCoreTests() {
    MCAssert("MCGrid" in getroottable(), "block core is not implemented");
    local c = ::MCGrid;
    MCAssert(c.Cell(-0.1) == -1, "negative coordinates must floor");
    MCAssert(c.Cell(-32.0) == -1, "negative boundary");
    MCAssert(c.Cell(31.9) == 0 && c.Cell(32.0) == 1, "positive boundary");
    MCAssert(c.Key(-1, 0, 2) == "-1,0,2", "stable cell identity");
    local rows = [{x=-1,y=2,z=3,type="wood"}, {x=0,y=0,z=4,type="stone"}];
    local text = c.Encode("c1m1_hotel", rows);
    local decoded = c.Decode(text, "c1m1_hotel");
    MCAssert(decoded.len() == 2 && decoded[0].x == -1 && decoded[0].type == "wood", "save round trip");
    foreach (bad in [
        "L4D2MC 1\nc1m1_hotel\n32\n1 2 3 dirt\n1 2 3 wood\n",
        "L4D2MC 1\nc1m1_hotel\n32\n1 2 3 lava\n",
        "L4D2MC 1\nc1m1_hotel\n32\n1x 2 3 dirt\n",
        "L4D2MC 1\nc1m1_hotel\n32\n999999 2 3 dirt\n",
        "L4D2MC 2\nc1m1_hotel\n32\n",
        "L4D2MC 1\nc2m1_highway\n32\n",
        "L4D2MC 1\nc1m1_hotel\n64\n",
        "return { code = system(\"evil\") };"
    ]) {
        local refused = false;
        try { c.Decode(bad, "c1m1_hotel"); } catch (e) { refused = true; }
        MCAssert(refused, "invalid save must be rejected");
    }
    local tooMany = "L4D2MC 1\nc1m1_hotel\n32\n";
    for (local i=0; i<129; ++i) tooMany += i + " 0 0 dirt\n";
    local refused = false;
    try { c.Decode(tooMany, "c1m1_hotel"); } catch (e) { refused = true; }
    MCAssert(refused, "save block limit");
    local a = c.RayBox(Vector(-10,16,16), Vector(1,0,0), Vector(0,0,0), 192.0);
    MCAssert(a != null && fabs(a.distance-10.0)<0.001 && a.normal.x == -1, "ray entry face");
    MCAssert(c.RayBox(Vector(-10,40,16),Vector(1,0,0),Vector(0,0,0),192.0)==null, "parallel ray misses");
    MCAssert(c.RayBox(Vector(-200,16,16),Vector(1,0,0),Vector(0,0,0),192.0)==null, "range cap");
    printl("[L4D2MC TEST] CORE PASS");
}
try {
    if ("MCGrid" in getroottable()) MCRunCoreTests();
    else {
        try { IncludeScript("l4d2mc/core", getroottable()); } catch (e) {}
        MCRunCoreTests();
    }
} catch (e) { printl("[L4D2MC TEST] CORE FAIL: " + e); }
