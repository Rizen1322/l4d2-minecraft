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
        self.epoch=0;self.serial=0;self.events=deque(maxlen=32);self.mobs=[];self.projectiles=[];self.physics=[]
        self.reply_acks=deque(maxlen=64)
        self.map=None;self.changed=0;self.equipment=None;self.equipment_at=0;self.signals=[];self.signals_at=0;self.navigation={};self.protection=None;self.protection_at=0;self.effects=None;self.effects_at=0
        self.fires=[];self.fires_at=0
        self.totem_held=None;self.totem_at=0
        self.mobs_at=self.projectiles_at=self.physics_at=-math.inf
        self.flight=None;self.flight_at=-math.inf;self.consuming=None;self.consume_at=-math.inf

    def apply(self,message):
        kind=message.get('t')
        event=None
        if kind=='flight':
            values=[message.get(k) for k in ('on','elytra','boosting')];boost=message.get('boost')
            if any(type(v) is not bool for v in values) or type(boost) is not int or not 0<=boost<2**31:raise ValueError('Invalid Elytra state')
            self.flight=(int(values[0]),int(values[1]),boost,int(values[2]));self.flight_at=time.monotonic()
        elif kind=='consume':
            value=message.get('using')
            if type(value) is not bool:raise ValueError('Invalid consumable state')
            self.consuming=value;self.consume_at=time.monotonic()
        elif kind=='explosion':
            p=source_position(message['pos']);r=float(message['r'])
            if not math.isfinite(r) or not 0<r<=32:raise ValueError('invalid blast radius')
            event=('explosion',*p,r*32)
        elif kind=='melee':
            d=float(message.get('d',1));r=float(message.get('r',3))
            if not math.isfinite(d+r) or not 0<=d<=100 or not 0<r<=8:raise ValueError('invalid melee')
            cut=message.get('cut',False)
            if type(cut) is not bool:raise ValueError('invalid blade flag')
            tier=message.get('tier',0)
            if type(tier) is not int or not 0<=tier<=2:raise ValueError('invalid sword tier')
            event=('melee',d*15,r*32,int(cut),tier)
        elif kind=='pteleport':event=('teleport',*source_position(message['pos']))
        elif kind=='chorus':event=('chorus',)
        elif kind=='ignite':event=('ignite',*source_position(message['pos']))
        elif kind=='fire':
            values=message.get('p')
            if not isinstance(values,list) or len(values)>32:raise ValueError('invalid fire snapshot')
            rows=[source_position(row) for row in values]
            self.fires=rows;self.fires_at=time.monotonic()
        elif kind=='totemheld':
            held=message.get('held')
            if type(held) is not bool:raise ValueError('invalid held totem')
            self.totem_held=int(held);self.totem_at=time.monotonic()
        elif kind=='totemresult':
            key=message.get('key');consumed=message.get('consumed')
            if not isinstance(key,str) or not key.startswith('totem_') or not 7<=len(key)<=118 or not all(c.isascii() and (c.isalnum() or c=='_') for c in key) or type(consumed) is not bool:raise ValueError('invalid totem result')
            event=('totemresult',key,int(consumed))
        elif kind=='nav':
            ident=message.get('id');query=message.get('q');w=message.get('w');h=message.get('h')
            if type(ident) is not int or type(query) is not int or not 0<ident<2**31 or not 0<query<2**31:raise ValueError('invalid navigation identity')
            if type(w) not in (int,float) or type(h) not in (int,float) or not math.isfinite(w+h) or not 0<w<=16 or not 0<h<=16:raise ValueError('invalid navigation body')
            row=(ident,query,*source_position(message['from']),*source_position(message['goal']),w*32,h*32)
            if ident not in self.navigation and len(self.navigation)>=12:
                del self.navigation[min(self.navigation,key=lambda k:self.navigation[k][1])]
            self.navigation[ident]=(row,time.monotonic())
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
        elif kind=='protection':
            e=message.get('e');r=message.get('resistance');f=message.get('fireproof')
            if not isinstance(e,list) or len(e)!=5 or any(type(v) not in (int,float) or not math.isfinite(v) or not 0<=v<=20 for v in e):raise ValueError('invalid enchantments')
            if type(r) is not int or not 0<=r<=4 or type(f) is not bool:raise ValueError('invalid status effects')
            self.protection=(*e,r,int(f));self.protection_at=time.monotonic()
        elif kind=='effects':
            speed=message.get('speed');burn=message.get('burn')
            if type(speed) not in (int,float) or not math.isfinite(speed) or not .25<=speed<=2 or type(burn) is not bool:raise ValueError('invalid environmental effects')
            self.effects=(speed,int(burn));self.effects_at=time.monotonic()
        elif kind in ('rewardack','pickupack'):
            key=message.get('key')
            if not isinstance(key,str) or not 1<=len(key)<=128 or not all(c.isascii() and (c.isalnum() or c=='_') for c in key):raise ValueError('invalid reward receipt')
            event=(kind,key)
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
            # Receipts are idempotent state, not discrete actions. A reply burst
            # must never evict an attack before Source reads the next mailbox.
            if message['id'] not in self.reply_acks:self.reply_acks.append(message['id'])
        elif kind=='mobhit':
            handle=message['h'];d=float(message['d']);p=source_position(message['from'])
            if type(handle) is not int or not 0<handle<2**31 or not math.isfinite(d) or not 0<=d<=100:raise ValueError('invalid mob hit')
            attacker=message.get('id',0)
            if type(attacker) is not int or not 0<=attacker<2**31:raise ValueError('invalid attacker')
            kind_name=message.get('k','')
            if not isinstance(kind_name,str) or len(kind_name)>48 or not all(c.isascii() and (c.isalnum() or c=='_') for c in kind_name):raise ValueError('invalid attacker kind')
            event=('mobhit',handle,d*5,*p,attacker,*([kind_name] if kind_name else []))
        elif kind in ('mobs','proj'):
            source=message['m' if kind=='mobs' else 'p'];rows=[]
            if len(source)>256:raise ValueError('too many entities')
            for row in source[:64]:
                if len(row) not in ((5,6,9) if kind=='proj' else (5,)) or type(row[0]) is not int or not 0<row[0]<2**31:raise ValueError('invalid entity')
                name=row[1]
                if not isinstance(name,str) or len(name)>48 or not all(c.isascii() and (c.isalnum() or c=='_') for c in name):raise ValueError('invalid kind')
                position=source_position(row[2:5])
                if kind=='proj':
                    damage=60.0 if name=='arrow' else 80.0
                    if len(row) in (6,9):
                        if type(row[5]) not in (int,float) or not math.isfinite(row[5]) or not 0<=row[5]<=100:raise ValueError('invalid projectile damage')
                        damage=float(row[5])*15
                    origin=source_position(row[6:9]) if len(row)==9 else ()
                    rows.append((row[0],name,*position,damage,*origin))
                else:rows.append((row[0],name,*position))
            if kind=='mobs':self.mobs=rows;self.mobs_at=time.monotonic()
            else:self.projectiles=rows;self.projectiles_at=time.monotonic()
        elif kind=='phys':
            rows=[]
            if len(message['p'])>64:raise ValueError('too many physics entities')
            for row in message['p']:
                if len(row)!=7 or type(row[0]) is not int or not 0<row[0]<2**31:raise ValueError('invalid physics entity')
                p=source_position(row[1:4]);w,h=map(float,row[4:6])
                if not math.isfinite(w+h) or not 0<w<=16 or not 0<h<=16 or row[6] not in (0,1):raise ValueError('invalid dimensions')
                rows.append((row[0],*p,w*32,h*32,row[6]))
            self.physics=rows
            self.physics_at=time.monotonic()
        if event:
            self.serial+=1;self.events.append((self.serial,*event))

    def publish(self,map_name,*,active=True,gui=False,sprint=False,attack=False,use=False):
        if not map_name or not all(c.isascii() and (c.isalnum() or c=='_') for c in map_name):raise ValueError('invalid map')
        if self.map is not None and self.map!=map_name:
            self.reply_acks.clear()
            self.events.clear();self.mobs.clear();self.projectiles.clear();self.physics.clear();self.equipment=None;self.signals=[];self.navigation.clear();self.protection=None;self.effects=None
            self.fires=[];self.fires_at=0
            self.totem_held=None;self.totem_at=0
            self.flight=None;self.consuming=None
        self.map=map_name
        records=[f'{self.generation} {map_name} {int(active)} {time.monotonic_ns()} {int(gui)} {int(sprint)} {int(attack and not gui)} {int(use and not gui)} {self.epoch}']
        if active:
            if self.flight is not None and time.monotonic()-self.flight_at<.75 and not gui:
                records.append(' '.join(map(str,('flight',*self.flight))))
            if self.consuming is not None and time.monotonic()-self.consume_at<.75 and not gui:
                records.append(f'consume {int(self.consuming)}')
            if time.monotonic()-self.mobs_at<0.75:
                records+=[' '.join(map(str,('golem',*row))) for row in self.mobs][:16]
            records+=[' '.join(map(str,('nav',*row))) for row,at in self.navigation.values() if time.monotonic()-at<1.5]
            if time.monotonic()-self.signals_at<0.75:
                records+=[' '.join(map(str,('signal',*e))) for e in self.signals]
            if self.effects is not None and time.monotonic()-self.effects_at<0.75:
                records.append(' '.join(map(str,('effects',*self.effects))))
            if time.monotonic()-self.fires_at<0.75:
                records+=[' '.join(map(str,('fire',*row))) for row in self.fires]
            if self.totem_held is not None and time.monotonic()-self.totem_at<0.75:
                records.append(f'totemheld {self.totem_held}')
            if self.protection is not None and time.monotonic()-self.protection_at<0.75:
                records.append(' '.join(map(str,('protection',*self.protection))))
            if self.equipment is not None and time.monotonic()-self.equipment_at<0.75:
                records.append(' '.join(map(str,('equipment',*self.equipment))))
            records+=[' '.join(map(str,('event',*e))) for e in self.events]
            if time.monotonic()-self.projectiles_at<0.75:records+=[' '.join(map(str,('projectile',*e))) for e in self.projectiles]
            if time.monotonic()-self.physics_at<0.75:records+=[' '.join(map(str,('physics',*e))) for e in self.physics]
        else:
            # A corpse/spectator has no controls, but a previously requested
            # durable totem result and its reply acknowledgements must arrive.
            records+=[' '.join(map(str,('event',*e))) for e in self.events if e[1] in ('totemresult','replyack')]
        records += [f'replyack {ident}' for ident in self.reply_acks]
        records.append(f'end {records[0].split()[3]} {len(records)-1}')
        text='\n'.join(records)
        if len(text)>32768:raise ValueError('mailbox too large')
        self.path.write_text(text,encoding='ascii')
