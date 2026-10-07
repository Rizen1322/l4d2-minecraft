// Pure grid, ray and save logic. Uses no entities or game-side effects.
::MCGrid <- {
    Size = 32.0,
    Limit = 128,
    Types = { dirt = 0, stone = 1, wood = 2 },
    function Cell(n) { return floor(n / Size).tointeger(); },
    function Key(x,y,z) { return format("%d,%d,%d",x,y,z); },
    function Minimum(row) { return Vector(row.x*Size,row.y*Size,row.z*Size); },
    function Center(row) { return Minimum(row) + Vector(16,16,16); },
    function Integer(s) {
        if (!regexp("^-?[0-9]+$").match(s) || s.len()>5) throw "Invalid coordinate";
        local n=s.tointeger();
        if (n < -512 || n > 511) throw "Coordinate outside map bounds";
        return n;
    },
    function MapName(s) {
        if (s.len()==0 || s.len()>96 || !regexp("^[a-zA-Z0-9_]+$").match(s))
            throw "Unsupported map name";
        return s;
    },
    function Encode(map,rows) {
        MapName(map);
        if (rows.len()>Limit) throw "Block limit";
        local text="L4D2MC 1\n"+map+"\n32\n";
        foreach (r in rows) text+=format("%d %d %d %s\n",r.x,r.y,r.z,r.type);
        // Validate even data produced by a caller before persisting it.
        Decode(text,map);
        return text;
    },
    function Decode(text,map) {
        MapName(map);
        if (typeof text!="string" || text.len()>10000) throw "Invalid save size";
        local lines=split(text,"\n");
        if (lines.len()<3 || strip(lines[0])!="L4D2MC 1" || strip(lines[1])!=map || strip(lines[2])!="32")
            throw "Save version, map or grid does not match";
        local rows=[], seen={};
        for (local i=3;i<lines.len();++i) {
            local line=strip(lines[i]);
            if (line.len()==0) continue;
            local a=split(line," \t\r");
            if (a.len()!=4 || !(a[3] in Types)) throw "Invalid block record";
            local r={x=Integer(a[0]),y=Integer(a[1]),z=Integer(a[2]),type=a[3]};
            local k=Key(r.x,r.y,r.z);
            if (k in seen) throw "Duplicate cell";
            seen[k]<-true; rows.append(r);
            if (rows.len()>Limit) throw "Too many blocks";
        }
        return rows;
    },
    function RayBox(start,dir,lo,range) {
        local near=0.0, far=range, normal=Vector(0,0,0);
        foreach (axis in ["x","y","z"]) {
            if (fabs(dir[axis])<0.000001) {
                if (start[axis]<lo[axis] || start[axis]>lo[axis]+Size) return null;
                continue;
            }
            local t1=(lo[axis]-start[axis])/dir[axis];
            local t2=(lo[axis]+Size-start[axis])/dir[axis];
            local sign=-1;
            if (t1>t2) {local tmp=t1;t1=t2;t2=tmp;sign=1;}
            if (t1>near) {near=t1;normal=Vector(0,0,0);normal[axis]=sign;}
            if (t2<far) far=t2;
            if (near>far) return null;
        }
        if (far<0 || near>range) return null;
        return {distance=near,normal=normal,pos=start+dir*near};
    }
};
