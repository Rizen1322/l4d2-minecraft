if("MCSandbox" in getroottable()) foreach(key,r in ::MCSandbox.Blocks) {
    printl("[L4D2MC COLLISION] key="+key+" entity="+r.entity+" origin="+r.entity.GetOrigin());
    foreach(name in ["m_Collision.m_nSolidType","m_Collision.m_usSolidFlags","m_nModelIndex","m_nSkin"])
        try {printl("[L4D2MC COLLISION] "+name+"="+NetProps.GetPropInt(r.entity,name));}catch(e){printl(e);}
    foreach(name in ["m_Collision.m_vecMins","m_Collision.m_vecMaxs"])
        try {printl("[L4D2MC COLLISION] "+name+"="+NetProps.GetPropVector(r.entity,name));}catch(e){printl(e);}
    local center=::MCGrid.Center(r);
    foreach(extent in [17,64]) foreach(mask in [33636363,1174421507]) {
        local t={start=center-Vector(extent,0,0),end=center+Vector(extent,0,0),mask=mask};
        TraceLine(t); printl("[L4D2MC COLLISION] extent="+extent+" mask="+mask);
        foreach(k,v in t) printl("[L4D2MC COLLISION] "+k+"="+v);
    }
}
