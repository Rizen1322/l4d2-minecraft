"""Bounded data-only guest -> Source gameplay mailbox (never executable code)."""
from collections import deque
import math
import time
import uuid


def source_position(values):
    if len(values)!=3 or not all(isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v) and abs(v)<=1023 for v in values):
        raise ValueError('invalid guest position')
    x,y,z=values
    return x*32,-z*32,y*32


class GameplayMailbox:
    def __init__(self,path):
        self.path=path;self.generation=uuid.uuid4().hex[:12]
        self.serial=0;self.events=deque(maxlen=32);self.mobs=[];self.projectiles=[];self.physics=[]
        self.map=None;self.changed=0;self.equipment=None;self.equipment_at=0;self.signals=[];self.signals_at=0

    def apply(self,message):
        kind=message.get('t')
        event=None
        if kind=='explosion':
            p=source_position(message['pos']);r=float(message['r'])
            if not math.isfinite(r) or not 0<r<=32:raise ValueError('invalid blast radius')
            event=('explosion',*p,r*32)
        elif kind=='melee':
            d=float(message.get('d',1));r=float(message.get('r',3))
            if not math.isfinite(d+r) or not 0<=d<=100 or not 0<r<=8:raise ValueError('invalid melee')
            event=('melee',d*15,r*32)
        elif kind=='pteleport':event=('teleport',*source_position(message['pos']))
        elif kind=='chorus':event=('chorus',)
        elif kind in ('link','signals'):
            rows=[[*message['pos'],False]] if kind=='link' else message['s']
            if len(rows)>32:raise ValueError('too many redstone links')
            checked=[]
            for row in rows:
                if len(row)!=4 or any(type(v) is not int or abs(v)>1023 for v in row[:3]) or type(row[3]) is not bool:raise ValueError('invalid redstone position/signal')
                checked.append((*row[:3],int(row[3])))
            if kind=='link':event=('link',*checked[0][:3])
            else:self.signals=checked;self.signals_at=time.monotonic()
        elif kind=='equipment':
            a=message.get('armor');t=message.get('toughness');b=message.get('blocking')
            if type(a) not in (int,float) or type(t) not in (int,float) or type(b) is not bool or not math.isfinite(a+t) or not 0<=a<=20 or not 0<=t<=20:
                raise ValueError('invalid equipment')
            self.equipment=(float(a),float(t),int(b));self.equipment_at=time.monotonic()
        elif kind=='meal':
            h=message.get('h');g=message.get('golden',False)
            if type(h) not in (int,float) or not math.isfinite(h) or not 0<h<=100 or type(g) is not bool:raise ValueError('invalid meal')
            event=('meal',float(h),int(g))
        elif kind=='heal':
            h=message['h']
            if isinstance(h,bool) or not isinstance(h,(int,float)) or not math.isfinite(h) or not 0<h<=100:raise ValueError('invalid food heal')
            event=('heal',float(h))
        elif kind=='interact':event=('interact',)
        elif kind=='replyack':
            if type(message['id']) is not int or not 0<message['id']<2**31:raise ValueError('invalid ack')
            event=('replyack',message['id'])
        elif kind=='mobhit':
            handle=message['h'];d=float(message['d']);p=source_position(message['from'])
            if type(handle) is not int or not 0<handle<2**31 or not math.isfinite(d) or not 0<=d<=100:raise ValueError('invalid mob hit')
            attacker=message.get('id',0)
            if type(attacker) is not int or not 0<=attacker<2**31:raise ValueError('invalid attacker')
            event=('mobhit',handle,d*5,*p,attacker)
        elif kind in ('mobs','proj'):
            source=message['m' if kind=='mobs' else 'p'];rows=[]
            if len(source)>256:raise ValueError('too many entities')
            for row in source[:64]:
                if len(row) not in ((5,6) if kind=='proj' else (5,)) or type(row[0]) is not int or not 0<row[0]<2**31:raise ValueError('invalid entity')
                name=row[1]
                if not isinstance(name,str) or len(name)>48 or not all(c.isascii() and (c.isalnum() or c=='_') for c in name):raise ValueError('invalid kind')
                position=source_position(row[2:5])
                if kind=='proj':
                    damage=60.0 if name=='arrow' else 80.0
                    if len(row)==6:
                        if type(row[5]) not in (int,float) or not math.isfinite(row[5]) or not 0<=row[5]<=100:raise ValueError('invalid projectile damage')
                        damage=float(row[5])*15
                    rows.append((row[0],name,*position,damage))
                else:rows.append((row[0],name,*position))
            if kind=='mobs':self.mobs=rows
            else:self.projectiles=rows
        elif kind=='phys':
            rows=[]
            if len(message['p'])>64:raise ValueError('too many physics entities')
            for row in message['p']:
                if len(row)!=7 or type(row[0]) is not int or not 0<row[0]<2**31:raise ValueError('invalid physics entity')
                p=source_position(row[1:4]);w,h=map(float,row[4:6])
                if not math.isfinite(w+h) or not 0<w<=16 or not 0<h<=16 or row[6] not in (0,1):raise ValueError('invalid dimensions')
                rows.append((row[0],*p,w*32,h*32,row[6]))
            self.physics=rows
        if event:
            self.serial+=1;self.events.append((self.serial,*event))

    def publish(self,map_name,*,active=True,gui=False,sprint=False,attack=False,use=False):
        if not map_name or not all(c.isascii() and (c.isalnum() or c=='_') for c in map_name):raise ValueError('invalid map')
        if self.map is not None and self.map!=map_name:
            self.events.clear();self.mobs.clear();self.projectiles.clear();self.physics.clear();self.equipment=None;self.signals=[]
        self.map=map_name
        records=[f'{self.generation} {map_name} {int(active)} {time.monotonic_ns()} {int(gui)} {int(sprint)} {int(attack and not gui)} {int(use and not gui)}']
        if active:
            if time.monotonic()-self.signals_at<0.75:
                records+=[' '.join(map(str,('signal',*e))) for e in self.signals]
            if self.equipment is not None and time.monotonic()-self.equipment_at<0.75:
                records.append(' '.join(map(str,('equipment',*self.equipment))))
            records+=[' '.join(map(str,('event',*e))) for e in self.events]
            records+=[' '.join(map(str,('projectile',*e))) for e in self.projectiles]
            records+=[' '.join(map(str,('physics',*e))) for e in self.physics]
        text='\n'.join(records)
        if len(text)>18000:raise ValueError('mailbox too large')
        self.path.write_text(text,encoding='ascii')
