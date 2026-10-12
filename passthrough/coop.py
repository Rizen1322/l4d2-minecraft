"""Opt-in authenticated LAN room. Each PC still runs its own local Minecraft.

Only the L4D2 listen host writes Source mailboxes. Remote clients receive their
own actor's Source state; no camera/input stream is shared between players.
"""
import asyncio
from collections import deque, OrderedDict
import hmac
import json
import math
from pathlib import Path
import re
import time
import uuid

MAX_PLAYERS=4
MAX_BLOCKS=20000
LEASE=1.0
NETWORK_LEASE=5.0
ROOM_REASONS={
    'token': 'Room invitation is invalid. Copy a new invitation from the host.',
    'source': 'Host has no fresh L4D2 player data. Host must enter the map with the bridge running.',
    'player': 'Player not found in host L4D2 roster. Join L4D2 and check the exact player name in Coop.bat.',
    'occupied': 'This L4D2 player already has a Minecraft bridge connected.',
    'full': 'Minecraft room is full.',
}

def load_config(path):
    if not path.exists():return None
    value=json.loads(path.read_text(encoding='utf-8-sig'))
    if value.get('mode') not in ('host','join'):raise ValueError('Co-op mode must be host or join')
    if not re.fullmatch(r'[A-Za-z0-9_-]{32,128}',value.get('token','')):raise ValueError('Co-op requires a private room token of at least32 characters')
    if value['mode']=='host':
        if type(value.get('port',25602)) is not int or not 1024<=value.get('port',25602)<=65535:raise ValueError('Invalid room port')
    else:
        if not re.fullmatch(r'ws://[A-Za-z0-9.\-]+:[0-9]{2,5}',value.get('server','')):raise ValueError('Use a LAN ws://host:port address')
        userid=value.get('userid');player=value.get('player')
        if player is not None:
            if not isinstance(player,str) or not 1<=len(player)<=128 or any(ord(c)<32 for c in player):raise ValueError('Invalid Source player name')
        elif type(userid) is not int or not 1<=userid<=65535:raise ValueError('Source player name or userid required')
    return value

def valid_rows(rows):
    if not isinstance(rows,list) or len(rows)>256:raise ValueError('Block batch limit')
    result=[]
    for row in rows:
        if not isinstance(row,list) or len(row)!=4 or any(type(v) is not int for v in row) or any(abs(v)>1023 for v in row[:3]) or not 0<=row[3]<=65535:raise ValueError('Invalid block state')
        result.append(row)
    return result

def atomic_text(path,text):
    path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_suffix(path.suffix+'.tmp');temp.write_text(text,encoding='ascii');temp.replace(path)

class RoomPath:
    def __init__(self,link,kind):self.link=link;self.kind=kind
    def write_text(self,text,encoding='ascii'):self.link.files[self.kind]=text
    def read_text(self,encoding='ascii'):return self.link.notices.get(self.kind,'')

class RoomSource:
    def __init__(self,link):self.link=link
    def read(self):
        now=time.monotonic()
        return self.link.sample if now-self.link.received<LEASE and now-self.link.pose_at<LEASE else None

class CoopLink:
    def __init__(self,config,ems,scene_token):
        self.config=config;self.ems=ems;self.scene_token=scene_token
        self.sample=None;self.received=-math.inf;self.peers=None;self.notices={};self.files={};self.outbound=deque()
        self.pose_at=-math.inf;self.pose_identity=None;self.guest_out=deque()
        self.session=uuid.uuid4().hex;self.event_sequence=0;self.event_sessions=OrderedDict()
        self.inboxes={};self.delivery_sequence=0;self.delivery_ack=0;self.delivery_seen=0;self.attack_sequence=0
        self.receipts={};self.receipt_sequence=0
        self.clients={};self.players={};self.local_id=0;self.scene=None;self.sequence=0;self.ledger={};self.collisions={};self.metadata={}
        self.entity_states={};self.peer_entities=None
        self.task=None;self.server=None;self.ready=False;self.error=None
        self.status=None
        self.snapshot_lane=False;self.snapshots={};self.snapshot_times={}
    def set_status(self,state,detail):
        value={'state':state,'detail':detail}
        if value==self.status:return
        self.status=value
        atomic_text(self.ems/'l4d2mc_room_status.txt',json.dumps(value,ensure_ascii=True))
        print('Co-op: '+detail,flush=True)
    def check_task(self):
        if self.task and self.task.done():
            if self.task.cancelled():raise RuntimeError('Co-op worker stopped')
            error=self.task.exception()
            raise RuntimeError('Co-op worker failed; check bridge-errors.log') from error
    @property
    def joining(self):return self.config['mode']=='join'
    def guest_event(self,event):
        if event.get('t') not in ('peerblocks','avatar','peerentitystate','peerattack'):return
        if self.joining:
            # Snapshots supersede unsent snapshots; edits must survive congestion.
            event=dict(event)
            if event['t'] in ('avatar','peerentitystate'):self.snapshot_times[event['t']]=time.monotonic()
            if self.snapshot_lane and event['t'] in ('avatar','peerentitystate'):
                self.snapshots[event['t']]=event;return
            if event['t']=='peerattack' and sum(e['t']=='peerattack' for e in self.guest_out)>=64:raise ValueError('Peer attack backlog limit')
            if event['t'] in ('avatar','peerentitystate'):
                self.guest_out=deque(e for e in self.guest_out if e.get('_id') or e['t']!=event['t'])
            self.guest_out.append(event)
            if len(self.guest_out)>=256:self.compact_pending()
        else:self.apply_guest(self.local_id,event)
    def compact_pending(self):
        retained=[];groups={}
        for event in self.guest_out:
            if event.get('_id') or event['t']!='peerblocks':retained.append(event);continue
            key=(event.get('scene'),bool(event.get('bootstrap',False)))
            rows=groups.setdefault(key,{})
            for row in valid_rows(event.get('rows')):rows[tuple(row[:3])]=row[3]
            if len(rows)>MAX_BLOCKS:raise ValueError('Room build limit')
        for (scene,bootstrap),values in groups.items():
            rows=[[*pos,state] for pos,state in values.items()]
            for start in range(0,len(rows),256):retained.append({'t':'peerblocks','scene':scene,'bootstrap':bootstrap,'rows':rows[start:start+256]})
        self.guest_out=deque(retained)
    def send_batch(self):
        # Never reorder assigned sequence IDs. Promote new combat ahead of unsent
        # build traffic before assigning IDs, keeping cumulative ACKs contiguous.
        assigned=[e for e in self.guest_out if e.get('_id')]
        unsent=[e for e in self.guest_out if not e.get('_id')]
        unsent.sort(key=lambda e:0 if e['t']=='peerattack' else 1)
        self.guest_out=deque(assigned+unsent)
        events=list(self.guest_out)[:8]
        for event in events:
            if '_id' not in event:self.event_sequence+=1;event['_id']=self.event_sequence
        return events
    def enqueue_blocks(self,queue,message):
        # A bounded full-room resync replaces an overflowing delta backlog.
        # One slow recipient must never disconnect the healthy sender.
        if len(queue)>=256:
            # Preserve discrete attacks and already transmitted events until ACK.
            retained=[e for e in queue if e.get('_delivery') or e.get('roomreceipt') or e.get('t')!='coopblocks']
            queue.clear();queue.extend(retained);rows=[[*pos,state] for pos,state in self.ledger.items()]
            for start in range(0,len(rows),256):queue.append({'t':'coopblocks','scene':self.scene,'rows':rows[start:start+256]})
        else:queue.append(message)
    def apply_guest(self,userid,event):
        if event.get('scene')!=self.scene:return
        if event['t']=='peerattack':
            owner=event.get('owner');ident=event.get('id');damage=event.get('d');now=time.monotonic()
            if type(owner) is not int or type(ident) is not int or type(damage) not in (int,float) or not math.isfinite(damage) or not 0<damage<=100:raise ValueError('Invalid peer attack')
            if owner==userid or not self.ready or now-self.pose_at>=LEASE:return
            active={self.local_id}|{uid for uid,c in self.clients.items() if now-c['at']<NETWORK_LEASE}
            rows,at=self.entity_states.get(owner,([], -math.inf))
            target=next((row for row in rows if row[0]==ident),None)
            if owner not in active or userid not in active or userid not in self.players or now-at>=LEASE or target is None:return
            feet=self.players[userid]['pose']['feet'];origin=[feet[0]/32,feet[2]/32,-feet[1]/32]
            if sum((origin[i]-target[i+2])**2 for i in range(3))>25:return
            queue=self.outbound if owner==self.local_id else self.inboxes.setdefault(owner,deque())
            if sum(e.get('t')=='peerattack' for e in queue)>=64:raise ValueError('Peer attack backlog limit')
            # Damage dedupe lives in the owner's Minecraft process, which can
            # outlive a room bridge restart in the same Source scene.
            # perf_counter uses the process-shared high-resolution QPC on Windows;
            # monotonic in Python 3.12 may tick only every 15 ms.
            self.attack_sequence=max(self.attack_sequence+1,time.perf_counter_ns())
            queue.append({'t':'peerattack','scene':self.scene,'owner':owner,'id':ident,'d':damage,
                'attacker':userid,'from':origin,'seq':self.attack_sequence})
            return
        if event['t']=='peerentitystate':
            rows=event.get('rows')
            if not isinstance(rows,list) or len(rows)>64:raise ValueError('Peer entity batch limit')
            seen=set()
            for row in rows:
                if not isinstance(row,list) or len(row)!=7 or type(row[0]) is not int or not 1<=row[0]<2**31 or row[0] in seen:raise ValueError('Invalid peer entity ID')
                seen.add(row[0])
                if not isinstance(row[1],str) or not re.fullmatch(r'[a-z0-9_.-]+:[a-z0-9_/.-]{1,96}',row[1]):raise ValueError('Invalid peer entity registry')
                if any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>(1023 if i<3 else 360) for i,v in enumerate(row[2:])):raise ValueError('Invalid peer entity pose')
            self.entity_states[userid]=(rows,time.monotonic());return
        if event['t']=='avatar':
            values={}
            for key in ('main','off','chest'):
                name=event.get(key,'minecraft:air')
                if not isinstance(name,str) or not re.fullmatch(r'[a-z0-9_.-]+:[a-z0-9_/.-]{1,96}',name):raise ValueError('Invalid equipment ID')
                values[key]=name
            swing=event.get('swing',0)
            if type(swing) is not int or not 0<=swing<2**31:raise ValueError('Invalid swing sequence')
            using=event.get('using',False)
            if type(using) is not bool:raise ValueError('Invalid use state')
            for key in ('swinghand','usehand'):
                hand=event.get(key,'main')
                if hand not in ('main','off'):raise ValueError('Invalid animation hand')
                values[key]=hand
            values.update(swing=swing,using=using)
            self.metadata[userid]=(values,time.monotonic());return
        rows=valid_rows(event.get('rows'));updated=dict(self.ledger);applied=[]
        for row in rows:
            key=tuple(row[:3])
            if event.get('bootstrap',False) and key in updated:continue
            updated[key]=row[3];applied.append(row)
        if len(updated)>MAX_BLOCKS:raise ValueError('Room build limit')
        self.ledger=updated
        message={'t':'coopblocks','scene':self.scene,'rows':applied}
        if userid!=self.local_id:self.enqueue_blocks(self.outbound,message)
        if event.get('bootstrap',False):
            correction={'t':'coopblocks','scene':self.scene,'rows':[[*r[:3],updated[tuple(r[:3])]] for r in rows]}
            if userid==self.local_id:self.enqueue_blocks(self.outbound,correction)
            elif userid in self.clients:self.enqueue_blocks(self.clients[userid]['events'],correction)
        for ident,state in self.clients.items():
            if ident!=userid:
                self.enqueue_blocks(state['events'],message)
    def pop_events(self):
        events=self.peek_events();self.commit_events(events);return events
    def peek_events(self,limit=8):
        result=[];now=time.monotonic()
        # Limit the application window independently of the room transport.
        for event in list(self.outbound)[:min(limit,8)]:
            if event.get('_completed'):continue
            ident=event.get('roomreceipt')
            record=self.receipts.get(ident)
            if record is None:
                self.receipt_sequence=max(self.receipt_sequence+1,time.perf_counter_ns())
                ident=self.receipt_sequence;event['roomreceipt']=ident
                record={'event':event,'sent':-math.inf};self.receipts[ident]=record
            if now-record['sent']>=.25:result.append(event)
        return result
    def mark_sent(self,event):
        record=self.receipts.get(event.get('roomreceipt'))
        if record and record['event'] is event:record['sent']=time.monotonic()
    def ack_event(self,ack):
        if not isinstance(ack,dict) or ack.get('t')!='roomack':return False
        ident=ack.get('id');scene=ack.get('scene')
        if type(ident) is not int or not 0<ident<2**63 or type(scene) is not int or scene!=self.scene:return False
        record=self.receipts.get(ident)
        if record is None or not math.isfinite(record['sent']):return False
        event=record['event']
        if event.get('scene')!=scene or event.get('_completed'):return False
        self.commit_events([event]);return True
    def commit_events(self,events):
        for event in events:
            if any(queued is event for queued in self.outbound):event['_completed']=True
        # Later application ACKs must never acknowledge an earlier pending hit.
        while self.outbound and self.outbound[0].get('_completed'):
            event=self.outbound.popleft();self.receipts.pop(event.get('roomreceipt'),None)
            if event.get('_transport')==getattr(self,'transport',None):self.delivery_ack=max(self.delivery_ack,event.get('_delivery',0))
    def roster(self,exclude):
        rows=[];now=time.monotonic()
        active={self.local_id}|{uid for uid,c in self.clients.items() if now-c['at']<NETWORK_LEASE}
        for uid,record in self.players.items():
            if uid==exclude or uid not in active:continue
            p=record['pose'];feet=p['feet'];angles=p['r'];meta,at=self.metadata.get(uid,({},-math.inf))
            if now-at>=LEASE:meta={}
            row={'id':uid,'x':feet[0]/32,'y':feet[2]/32,'z':-feet[1]/32,
                 'yaw':-float(angles[0])-90,'pitch':float(angles[1]),'hp':p.get('health',[100])[0],
                 'dead':bool(p.get('dead',False)),'incap':bool(p.get('incap',False)), 'pin':p.get('pin','none'),
                 'crouching':bool(p.get('buttons',0)&(4|131072)), 'flying':bool(p.get('flying',False)),
                 'burning':bool(p.get('burning',False)),
                 'main':'minecraft:air','off':'minecraft:air','chest':'minecraft:air',**meta}
            rows.append(row)
        return {'t':'peers','scene':self.scene,'players':rows[:MAX_PLAYERS]}
    def entities(self,exclude):
        now=time.monotonic();active={self.local_id}|{uid for uid,c in self.clients.items() if now-c['at']<NETWORK_LEASE}
        return {'t':'peerentities','scene':self.scene,'owners':[{'id':uid,'rows':rows} for uid,(rows,at) in self.entity_states.items()
            if uid!=exclude and uid in active and now-at<LEASE][:3]}
    async def start(self):
        self.set_status('starting','Connecting to host room.' if self.joining else 'Room listening; waiting for L4D2 teammate data.')
        if self.joining:self.task=asyncio.create_task(self.client_loop())
        else:
            import websockets
            self.server=await websockets.serve(self.handler,self.config.get('bind','127.0.0.1'),self.config.get('port',25602),max_size=131072,max_queue=4,ping_interval=10)
            self.task=asyncio.create_task(self.host_loop())
    async def close(self):
        if self.task:self.task.cancel();await asyncio.gather(self.task,return_exceptions=True)
        if self.server:self.server.close();await self.server.wait_closed()
    async def handler(self,socket,path=None):  # websockets>=13 passes only the connection
        from websockets.exceptions import ConnectionClosed
        uid=None
        try:
            hello=json.loads(await asyncio.wait_for(socket.recv(),5))
            if not isinstance(hello,dict):raise ValueError('Invalid room greeting')
            token=hello.get('token','');uid=hello.get('userid')
            session=hello.get('session')
            if session is not None and (not isinstance(session,str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}',session)):raise ValueError('Invalid room session')
            if isinstance(hello.get('player'),str):
                matches=[ident for ident,record in self.players.items() if record.get('name')==hello['player'] and ident!=self.local_id]
                uid=matches[0] if len(matches)==1 else None
            reason=None
            if not isinstance(token,str) or not hmac.compare_digest(token,self.config['token']):reason='token'
            elif not self.ready:reason='source'
            elif type(uid) is not int or uid not in self.players or uid==self.local_id:reason='player'
            elif uid in self.clients and not (session is not None and self.clients[uid].get('session')==session):reason='occupied'
            elif uid not in self.clients and len(self.clients)>=MAX_PLAYERS-1:reason='full'
            if reason:
                # Only disclose roster names after authenticating the private room token.
                names=[str(record.get('name',''))[:96] for ident,record in self.players.items() if ident!=self.local_id][:3] if reason=='player' else []
                await socket.send(json.dumps({'t':'rejected','reason':reason,'players':names},ensure_ascii=True))
                await socket.close(1008,'l4d2mc:'+reason);return
            session_key=(uid,session);reliable=session is not None
            if reliable:
                self.event_sessions.setdefault(session_key,0);self.event_sessions.move_to_end(session_key)
                while len(self.event_sessions)>32:self.event_sessions.popitem(last=False)
            previous=self.clients.get(uid)
            state={'at':time.monotonic(),'events':self.inboxes.setdefault(uid,deque()),'socket':socket,'session':session};self.clients[uid]=state
            if previous is not None:
                try:await asyncio.wait_for(previous['socket'].close(1000,'Same bridge session resumed'),1)
                except asyncio.TimeoutError:pass
            values=[[ *pos,value] for pos,value in self.ledger.items()]
            for index in range(0,len(values),256):self.enqueue_blocks(state['events'],{'t':'coopblocks','scene':self.scene,'rows':values[index:index+256]})
            await socket.send(json.dumps({'t':'joined','userid':uid,'reliable_events':True,'snapshot_lane':True,'transport':self.session}))
            async for raw in socket:
                if self.clients.get(uid) is not state:break
                request=json.loads(raw)
                if not isinstance(request,dict):raise ValueError('Invalid room message')
                if request.get('t')!='tick':raise ValueError('Invalid room message')
                live=time.monotonic()-self.received<LEASE and time.monotonic()-self.pose_at<LEASE
                if live and uid not in self.players:
                    await socket.close(1008,'Source actor disconnected; rejoin the room');break
                state['at']=time.monotonic()
                files=request.get('files',{})
                if not isinstance(files,dict) or len(files)>2:raise ValueError('Mailbox limit')
                events=request.get('events',[])
                if not isinstance(events,list) or len(events)>64:raise ValueError('Event batch limit')
                if request.get('scene')==self.scene:
                    for kind,text in files.items():self.accept_file(uid,kind,text)
                    snapshots=request.get('snapshots',[])
                    if not isinstance(snapshots,list) or len(snapshots)>2:raise ValueError('Snapshot batch limit')
                    seen=set()
                    for snapshot in snapshots:
                        if not isinstance(snapshot,dict) or snapshot.get('t') not in ('avatar','peerentitystate') or snapshot['t'] in seen:raise ValueError('Invalid room snapshot')
                        seen.add(snapshot['t']);self.apply_guest(uid,snapshot)
                for event in events:
                    if not isinstance(event,dict) or event.get('t') not in ('peerblocks','avatar','peerentitystate','peerattack'):raise ValueError('Invalid guest event')
                    ident=event.get('_id')
                    if reliable:
                        if type(ident) is not int or ident<1:raise ValueError('Invalid event sequence')
                        if ident<=self.event_sessions[session_key]:continue
                    if request.get('scene')==self.scene:self.apply_guest(uid,event)
                    if reliable:self.event_sessions[session_key]=ident
                notices={}
                for kind in ('pickups','rewards'):
                    file=self.ems/f'l4d2mc_coop_{uid}_{kind}.txt'
                    try:notices[kind]=file.read_text(encoding='ascii').rstrip('\x00')[:8192]
                    except OSError:notices[kind]=''
                ack=request.get('delivery_ack',0)
                if type(ack) is not int or ack<0 or ack>self.delivery_sequence:raise ValueError('Invalid delivery acknowledgement')
                if reliable:
                    while state['events'] and state['events'][0].get('_delivery',math.inf)<=ack:state['events'].popleft()
                    batch=list(state['events'])[:8]
                    for event in batch:
                        if '_delivery' not in event:
                            self.delivery_sequence+=1;event['_delivery']=self.delivery_sequence
                else:batch=[state['events'].popleft() for _ in range(min(8,len(state['events'])))]
                live=time.monotonic()-self.received<LEASE and time.monotonic()-self.pose_at<LEASE
                await socket.send(json.dumps({'t':'tick','sample':self.players.get(uid,{}).get('pose') if live else None,
                    'peers':self.roster(uid) if live else None,'entities':self.entities(uid) if live else None,'events':batch,'notices':notices,'scene':self.scene,
                    'event_ack':self.event_sessions.get(session_key,0)}))
        except ConnectionClosed:pass
        except (ValueError,KeyError,TypeError,asyncio.TimeoutError):await socket.close(1008,'Invalid room data')
        finally:
            if type(uid) is int and uid in self.clients and self.clients[uid]['socket']==socket:del self.clients[uid];self.collisions.pop(uid,None);self.metadata.pop(uid,None);self.entity_states.pop(uid,None)
    def accept_file(self,uid,kind,text):
        if kind not in ('gameplay','collision') or not isinstance(text,str) or len(text)>32768 or not text.isascii():raise ValueError('Invalid peer mailbox')
        lines=text.splitlines();head=lines[0].split() if lines else []
        if len(lines)<2 or not self.sample:return
        if kind=='gameplay':
            if len(head)!=9 or head[1]!=self.sample['map'] or head[8]!=str(self.sample['epoch']):raise ValueError('Wrong mailbox scene')
            if lines[-1]!=f'end {head[3]} {len(lines)-2}':raise ValueError('Partial gameplay file')
            atomic_text(self.ems/f'l4d2mc_coop_{uid}.txt',text)
        else:
            if len(head)!=3 or head[1]!=self.sample['map'] or head[2]!=str(self.sample['epoch']) or len(lines)>514:raise ValueError('Wrong collision scene')
            rows=[]
            for line in lines[1:-1]:
                values=[int(v) for v in line.split()]
                if len(values)!=3 or any(abs(v)>1023 for v in values):raise ValueError('Invalid collision cell')
                rows.append(tuple(values))
            if lines[-1]!=f'end {head[0]} {len(rows)}':raise ValueError('Partial collision file')
            self.collisions[uid]=(rows,time.monotonic())
    async def host_loop(self):
        while True:
            try:
                path=self.ems/'l4d2mc_coop_pose.txt'
                if time.time()-path.stat().st_mtime<=1:
                    raw=path.read_text(encoding='utf-8').rstrip('\x00')
                    if len(raw)>262144:raise ValueError('Room pose limit')
                    data=json.loads(raw);new_scene=self.scene_token(data['map'],data['epoch'])
                    if self.scene!=new_scene:
                        self.scene=new_scene;self.ledger.clear();self.collisions.clear();self.metadata.clear();self.outbound.clear();self.receipts.clear();self.entity_states.clear()
                        for inbox in self.inboxes.values():inbox.clear()
                    self.local_id=data['local_id'];self.players={r['userid']:r for r in data['players'][:MAX_PLAYERS]}
                    self.sample=self.players.get(self.local_id,{}).get('pose');self.received=time.monotonic();self.ready=True
                    identity=(self.scene,data['frame'])
                    if identity!=self.pose_identity:self.pose_identity=identity;self.pose_at=self.received
                    if time.monotonic()-self.pose_at<LEASE:self.peers=self.roster(self.local_id);self.peer_entities=self.entities(self.local_id)
                    else:self.ready=False;self.peers=None;self.peer_entities=None
                else:self.ready=False;self.peers=None;self.peer_entities=None
                now=time.monotonic();ids=[uid for uid,c in self.clients.items() if self.ready and now-c['at']<NETWORK_LEASE and uid in self.players]
                self.sequence+=1;epoch=self.sample.get('epoch',0) if self.sample else 0
                manifest=[f'{epoch} {self.sequence}',*[str(uid) for uid in ids],f'end {self.sequence} {len(ids)}']
                atomic_text(self.ems/'l4d2mc_coop_sessions.txt','\n'.join(manifest))
                if self.sample and self.ready:
                    text=self.files.get('collision')
                    if text:self.accept_file(self.local_id,'collision',text)
                    cells=set()
                    for rows,at in self.collisions.values():
                        if now-at<NETWORK_LEASE:cells.update(rows)
                    centres=[self.players[u]['pose']['feet'] for u in [self.local_id,*ids] if u in self.players]
                    def distance(c):return min(((c[0]+.5)*32-p[0])**2+(-(c[2]+.5)*32-p[1])**2+((c[1]+.5)*32-p[2])**2 for p in centres) if centres else 0
                    rows=sorted(cells,key=lambda c:(distance(c),c))[:512]
                    body=[f'{self.sequence} {self.sample["map"]} {epoch}',*['%d %d %d'%c for c in rows],f'end {self.sequence} {len(rows)}']
                    atomic_text(self.ems/'l4d2mc_collision.txt','\n'.join(body))
            except (OSError,ValueError,KeyError,TypeError,AttributeError):self.ready=False;self.peers=None;self.peer_entities=None
            await asyncio.sleep(.033)
    async def client_loop(self):
        import websockets
        while True:
            rejection_detail=None
            try:
                async with websockets.connect(self.config['server'],max_size=262144,max_queue=4,open_timeout=5) as socket:
                    await socket.send(json.dumps({'t':'join','token':self.config['token'],'userid':self.config.get('userid'),'player':self.config.get('player'),'session':self.session}))
                    answer=json.loads(await asyncio.wait_for(socket.recv(),5))
                    if not isinstance(answer,dict):raise ValueError('Invalid room answer')
                    if answer.get('t')=='rejected':
                        rejection_detail=ROOM_REASONS.get(answer.get('reason'),'Host refused the room connection.')
                        names=answer.get('players')
                        if answer.get('reason')=='player' and isinstance(names,list):
                            names=[name[:96] for name in names[:3] if isinstance(name,str)]
                            rejection_detail+=' Host L4D2 player names: '+json.dumps(names,ensure_ascii=True)
                        raise ValueError('Room join refused')
                    if answer.get('t')!='joined':raise ValueError('Room join refused')
                    reliable=answer.get('reliable_events',False)
                    transport=answer.get('transport')
                    if transport!=getattr(self,'transport',None):self.delivery_ack=0;self.delivery_seen=0;self.transport=transport
                    self.ready=True
                    self.snapshot_lane=answer.get('snapshot_lane') is True
                    if self.snapshot_lane:
                        kept=deque()
                        for event in self.guest_out:
                            if event['t'] in ('avatar','peerentitystate') and not event.get('_id'):self.snapshots[event['t']]=event
                            else:kept.append(event)
                        self.guest_out=kept
                    else:
                        for event in self.snapshots.values():self.guest_event(event)
                        self.snapshots.clear()
                    while True:
                        tick_at=time.monotonic()
                        events=self.send_batch()
                        snapshots=[event for kind,event in self.snapshots.items() if tick_at-self.snapshot_times.get(kind,-math.inf)<.75]
                        await socket.send(json.dumps({'t':'tick','scene':self.scene,'files':dict(self.files),'events':events,'snapshots':snapshots,'delivery_ack':self.delivery_ack}))
                        result=json.loads(await asyncio.wait_for(socket.recv(),NETWORK_LEASE))
                        if not isinstance(result,dict) or result.get('t')!='tick':raise ValueError('Invalid room tick')
                        ack=result.get('event_ack',0) if reliable else max([e['_id'] for e in events],default=0)
                        if type(ack) is not int or not 0<=ack<=self.event_sequence:raise ValueError('Invalid event acknowledgement')
                        while self.guest_out and self.guest_out[0].get('_id',math.inf)<=ack:self.guest_out.popleft()
                        if self.scene is not None and result.get('scene')!=self.scene:
                            self.files.clear();self.outbound.clear();self.receipts.clear();self.ledger.clear()
                            self.snapshots.clear()
                            self.snapshot_times.clear()
                            self.guest_out=deque(e for e in self.guest_out if e.get('scene')==result.get('scene'))
                        self.scene=result.get('scene');self.sample=result.get('sample');self.received=time.monotonic()
                        if self.sample:
                            identity=(self.scene,self.sample['f'])
                            if identity!=self.pose_identity:self.pose_identity=identity;self.pose_at=self.received
                            atomic_text(self.ems/'l4d2mc_pose.txt',json.dumps(self.sample,ensure_ascii=True))
                        fresh=self.sample is not None and time.monotonic()-self.pose_at<LEASE
                        self.set_status('ready' if fresh else 'waiting_source','Room connected; L4D2 camera received.' if fresh else ROOM_REASONS['source'])
                        self.peers=result.get('peers');self.notices=result.get('notices',{})
                        self.peer_entities=result.get('entities')
                        incoming=result.get('events',[])
                        if not isinstance(incoming,list) or len(incoming)>8:raise ValueError('Invalid room event batch')
                        for event in incoming:
                            if not isinstance(event,dict) or event.get('t') not in ('coopblocks','peerattack'):raise ValueError('Invalid room event')
                            ident=event.get('_delivery',0)
                            if type(ident) is not int or ident<0:raise ValueError('Invalid delivery sequence')
                            if ident and ident<=self.delivery_seen:continue
                            if event['t']=='coopblocks':
                                rows=valid_rows(event.get('rows'))
                                for row in rows:self.ledger[tuple(row[:3])]=row[3]
                                if len(self.ledger)>MAX_BLOCKS:raise ValueError('Room build limit')
                                self.enqueue_blocks(self.outbound,{**event,'_transport':transport})
                            else:self.outbound.append({**event,'_transport':transport})
                            if ident:self.delivery_seen=ident
                        await asyncio.sleep(max(0,.033-(time.monotonic()-tick_at)))
            except (OSError,ValueError,KeyError,TypeError,AttributeError,websockets.exceptions.ConnectionClosed,asyncio.TimeoutError) as error:
                self.ready=False;self.error=type(error).__name__;self.sample=None;self.peers=None;self.peer_entities=None
                # Mailbox commands may expire; unacknowledged block edits and accepted
                # deliveries remain queued for the same room/scene after reconnect.
                self.files.clear()
                reason=getattr(error,'reason','')
                key=reason.removeprefix('l4d2mc:') if reason.startswith('l4d2mc:') else ''
                detail=rejection_detail or ROOM_REASONS.get(key)
                if detail is None:
                    detail=('Host room connection timed out.' if isinstance(error,asyncio.TimeoutError) else
                            'Cannot reach host room. Check that host launcher is running and both PCs can reach TCP port 25602.' if isinstance(error,OSError) else
                            'Host room disconnected or returned invalid data.')
                self.set_status('retrying',detail)
                await asyncio.sleep(1)
