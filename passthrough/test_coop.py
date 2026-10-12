"""Real loopback room tests. Only temporary files and private WS sockets; no games."""
import asyncio
import json
from pathlib import Path
import tempfile
import time
import unittest

import websockets
from coop import CoopLink, RoomSource, LEASE

TOKEN='private_test_room_token_'+'x'*40
def scene_token(name,epoch):return epoch*10000+sum(map(ord,name))

def pose(uid,frame,epoch=1):
    return {'v':1,'f':frame,'map':'c1m1_hotel','epoch':epoch,
        'p':[uid*320,0,96],'feet':[uid*320,0,32],'r':[0,0,0],'hfov':90,
        'health':[100,100,0],'visible':True,'pin':'none','buttons':0}

async def until(condition,timeout=3):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        if condition():return
        await asyncio.sleep(.02)
    raise AssertionError('Timed out waiting for room state')

class CoopLoopbackTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp=tempfile.TemporaryDirectory()
        root=Path(self.temp.name);self.ems=root/'host';self.ems.mkdir()
        self.frame=1;self.epoch=1;self.peer_uid=2;self.frozen=False;self.writer=None;self.remote=None
        self.write_pose()
        self.host=CoopLink({'mode':'host','bind':'127.0.0.1','port':0,'token':TOKEN},self.ems,scene_token)
        await self.host.start()
        self.port=self.host.server.sockets[0].getsockname()[1]
        self.writer=asyncio.create_task(self.export_source())
        await until(lambda:self.host.scene is not None and self.host.local_id==1)

    def write_pose(self):
        data={'map':'c1m1_hotel','epoch':self.epoch,'local_id':1,'frame':self.frame,
            'players':[{'userid':uid,'name':'Remote Survivor' if uid==self.peer_uid else f'Survivor {uid}',
                       'pose':pose(uid,self.frame,self.epoch)} for uid in (1,self.peer_uid,3)]}
        path=self.ems/'l4d2mc_coop_pose.txt';tmp=path.with_suffix('.tmp')
        tmp.write_text(json.dumps(data),encoding='utf-8');tmp.replace(path)

    async def export_source(self):
        while True:
            if not self.frozen:self.frame+=1
            self.write_pose();await asyncio.sleep(.04)

    async def join(self,uid=2,player=None):
        config={'mode':'join','server':f'ws://127.0.0.1:{self.port}','token':TOKEN}
        config.update({'player':player} if player else {'userid':uid})
        link=CoopLink(config,Path(self.temp.name)/str(uid),scene_token)
        self.remote=link;await link.start()
        await until(lambda:link.scene==self.host.scene and RoomSource(link).read() is not None)
        return link

    async def asyncTearDown(self):
        if self.writer:self.writer.cancel();await asyncio.gather(self.writer,return_exceptions=True)
        if self.remote:await self.remote.close()
        await self.host.close();self.temp.cleanup()

    async def test_brief_roster_gap_keeps_same_transport(self):
        remote=await self.join();owner=self.host.clients[2]['socket']
        self.peer_uid=3
        await until(lambda:2 not in self.host.players)
        await asyncio.sleep(.35)
        self.assertIs(self.host.clients[2]['socket'],owner)
        self.assertIsNone(RoomSource(remote).read(),'Missing actor must not receive stale controls')
        self.peer_uid=2
        await until(lambda:RoomSource(remote).read() is not None)
        self.assertIs(self.host.clients[2]['socket'],owner)

    async def test_source_stall_preserves_membership_not_controls(self):
        remote=await self.join();owner=self.host.clients[2]['socket']
        self.frozen=True
        await asyncio.sleep(LEASE+.2)
        self.assertIsNone(RoomSource(remote).read())
        rows=(self.ems/'l4d2mc_coop_sessions.txt').read_text().splitlines()
        self.assertIn('2',rows[1:-1])
        self.assertIs(self.host.clients[2]['socket'],owner)
        self.frozen=False
        await until(lambda:RoomSource(remote).read() is not None)

    async def test_reviver_faces_target_in_peer_roster(self):
        self.host.players[1]['pose'].update(reviving=True,reviveyaw=30)
        row=next(row for row in self.host.roster(2)['players'] if row['id']==1)
        self.assertTrue(row['reviving']);self.assertEqual(row['yaw'],-120)

    async def test_auth_rejection_and_duplicate_userid_preserve_owner(self):
        for token,uid in [('incorrect',2),(TOKEN,1),(TOKEN,99)]:
            async with websockets.connect(f'ws://127.0.0.1:{self.port}') as socket:
                await socket.send(json.dumps({'t':'join','token':token,'userid':uid}))
                self.assertEqual(json.loads(await socket.recv())['t'],'rejected')
                with self.assertRaises(websockets.exceptions.ConnectionClosed) as rejected:await socket.recv()
                self.assertEqual(rejected.exception.code,1008)
        remote=await self.join()
        original=self.host.clients[2]['socket']
        async with websockets.connect(f'ws://127.0.0.1:{self.port}') as duplicate:
            await duplicate.send(json.dumps({'t':'join','token':TOKEN,'userid':2}))
            self.assertEqual(json.loads(await duplicate.recv())['t'],'rejected')
            with self.assertRaises(websockets.exceptions.ConnectionClosed):await duplicate.recv()
        self.assertIs(self.host.clients[2]['socket'],original)
        self.assertIsNotNone(RoomSource(remote).read())

    async def test_pending_blocks_survive_disconnect_before_host_acceptance(self):
        dropped=[];accepted=[]
        async def flaky(socket,path=None):
            await socket.recv()
            await socket.send(json.dumps({'t':'joined','userid':2,'reliable_events':True}))
            async for raw in socket:
                tick=json.loads(raw);events=tick.get('events',[])
                if events and not dropped:
                    dropped.extend(events);await socket.close();return
                accepted.extend(events)
                try:
                    await socket.send(json.dumps({'t':'tick','scene':self.host.scene,'sample':pose(2,self.frame),
                        'events':[],'event_ack':max([event.get('_id',0) for event in events],default=0)}))
                except websockets.exceptions.ConnectionClosed:return
        server=await websockets.serve(flaky,'127.0.0.1',0)
        try:
            config={'mode':'join','server':f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}','token':TOKEN,'userid':2}
            self.remote=CoopLink(config,Path(self.temp.name)/'flaky',scene_token)
            await self.remote.start();await until(lambda:self.remote.scene==self.host.scene)
            self.remote.guest_event({'t':'peerblocks','scene':self.host.scene,'rows':[[21,2,3,17]]})
            await until(lambda:bool(accepted),timeout=4)
            self.assertEqual(accepted[0]['rows'],[[21,2,3,17]])
            self.assertEqual(accepted[0]['_id'],dropped[0]['_id'])
            await until(lambda:not self.remote.guest_out)
        finally:
            await self.remote.close();server.close();await server.wait_closed()

    async def test_burst_preserves_all_pending_block_cells(self):
        link=CoopLink({'mode':'join'},Path(self.temp.name)/'queued',scene_token)
        for index in range(700):
            link.guest_event({'t':'peerblocks','scene':self.host.scene,'rows':[[index,1,1,17]]})
        rows=[row for event in link.guest_out for row in event.get('rows',[])]
        self.assertEqual({row[0] for row in rows},set(range(700)))
        self.assertLessEqual(len(link.guest_out),256)

    async def test_replayed_acknowledged_event_does_not_overwrite_newer_edit(self):
        async def send(events):
            async with websockets.connect(f'ws://127.0.0.1:{self.port}') as socket:
                await socket.send(json.dumps({'t':'join','token':TOKEN,'userid':2,'session':'regression-session'}))
                await socket.recv()
                await socket.send(json.dumps({'t':'tick','scene':self.host.scene,'events':events}))
                answer=json.loads(await socket.recv())
                self.assertEqual(answer.get('event_ack'),1)
            await until(lambda:2 not in self.host.clients)
        event={'t':'peerblocks','scene':self.host.scene,'_id':1,'rows':[[21,1,1,17]]}
        await send([event])
        self.host.guest_event({'t':'peerblocks','scene':self.host.scene,'rows':[[21,1,1,55]]})
        await send([event])
        self.assertEqual(self.host.ledger[(21,1,1)],55)

    async def test_network_pause_does_not_expire_live_source_participant(self):
        async with websockets.connect(f'ws://127.0.0.1:{self.port}') as socket:
            await socket.send(json.dumps({'t':'join','token':TOKEN,'userid':2}))
            await socket.recv()
            await asyncio.sleep(LEASE+.2)
            self.assertIn(2,[row['id'] for row in self.host.roster(1)['players']])

    async def test_same_session_reconnect_replaces_socket_without_losing_edits(self):
        old=await websockets.connect(f'ws://127.0.0.1:{self.port}')
        try:
            hello={'t':'join','token':TOKEN,'userid':2,'session':'v2-resume'}
            await old.send(json.dumps(hello));await old.recv()
            self.host.guest_event({'t':'peerblocks','scene':self.host.scene,'rows':[[8,1,1,17]]})
            async with websockets.connect(f'ws://127.0.0.1:{self.port}') as fresh:
                await fresh.send(json.dumps(hello));answer=json.loads(await fresh.recv())
                self.assertEqual(answer['t'],'joined')
                await fresh.send(json.dumps({'t':'tick','scene':self.host.scene,'events':[]}))
                answer=json.loads(await fresh.recv())
                self.assertTrue(any([8,1,1,17] in e.get('rows',[]) for e in answer['events']))
                self.assertIn(2,self.host.clients)
        finally:await old.close()

    async def test_snapshot_lane_remains_fresh_while_build_queue_is_unacknowledged(self):
        remote=await self.join();self.assertTrue(remote.snapshot_lane)
        for i in range(100):remote.guest_event({'t':'peerblocks','scene':remote.scene,'rows':[[i,1,1,17]]})
        remote.guest_event({'t':'peerentitystate','scene':remote.scene,'rows':[[7,'minecraft:pig',20,1,0,0,0]]})
        await until(lambda:2 in self.host.entity_states)
        for i in range(20):remote.guest_event({'t':'peerentitystate','scene':remote.scene,'rows':[[7,'minecraft:pig',21+i,1,0,0,0]]})
        await until(lambda:self.host.entity_states[2][0][0][2]==40)
        self.assertEqual(len(remote.snapshots),1)
        self.assertFalse(any(e['t']=='peerentitystate' for e in remote.guest_out))

    async def test_combat_priority_preserves_assigned_event_sequence_order(self):
        remote=CoopLink({'mode':'join'},Path(self.temp.name)/'priority',scene_token)
        for i in range(20):remote.guest_event({'t':'peerblocks','scene':self.host.scene,'rows':[[i,1,1,17]]})
        first=remote.send_batch()
        remote.guest_event({'t':'peerattack','scene':self.host.scene,'owner':1,'id':7,'d':4})
        self.assertEqual(remote.send_batch(),first,'In-flight events were reordered')
        for _ in range(8):remote.guest_out.popleft()
        next_batch=remote.send_batch();self.assertEqual(next_batch[0]['t'],'peerattack')
        self.assertEqual([e['_id'] for e in next_batch],list(range(9,17)))

    async def test_peer_attack_routes_only_to_live_nearby_entity_owner(self):
        remote=await self.join()
        self.host.guest_event({'t':'peerentitystate','scene':self.host.scene,'rows':[[7,'minecraft:pig',20,1,0,0,0]]})
        remote.guest_event({'t':'peerattack','scene':remote.scene,'owner':1,'id':7,'d':4})
        await until(lambda:any(e.get('t')=='peerattack' for e in self.host.outbound))
        attack=next(e for e in self.host.pop_events() if e.get('t')=='peerattack')
        self.assertEqual(attack['attacker'],2);self.assertEqual(attack['from'],[20,1,0]);self.assertGreater(attack['seq'],0)
        for change in ({'owner':2},{'id':99},{'scene':-1}):
            self.host.apply_guest(2,{'t':'peerattack','scene':self.host.scene,'owner':1,'id':7,'d':4,**change})
        self.assertFalse(self.host.outbound)
        for damage in (-1,float('nan'),101):
            with self.assertRaises(ValueError):self.host.apply_guest(2,{'t':'peerattack','scene':self.host.scene,'owner':1,'id':7,'d':damage})
        self.host.entity_states[1]=([[7,'minecraft:pig',100,1,0,0,0]],time.monotonic())
        self.host.apply_guest(2,{'t':'peerattack','scene':self.host.scene,'owner':1,'id':7,'d':4})
        self.assertFalse(self.host.outbound)

    async def test_local_delivery_waits_for_commit_after_send(self):
        event={'t':'peerattack','scene':self.host.scene,'seq':1}
        self.host.outbound.append(event)
        batch=self.host.peek_events();self.assertEqual(self.host.peek_events(),batch)
        self.host.commit_events(batch);self.assertFalse(self.host.outbound)

    async def test_local_application_ack_retries_same_receipt_after_socket_send(self):
        self.assertTrue(hasattr(self.host,'mark_sent'),'Application delivery tracking is required')
        received=asyncio.Queue();release=asyncio.Event()
        async def minecraft(socket,path=None):
            count=0
            async for raw in socket:
                count+=1;event=json.loads(raw);await received.put(event)
                if count>1:
                    await release.wait()
                    await socket.send(json.dumps({'t':'roomack','id':event['roomreceipt'],'scene':event['scene']}))
        server=await websockets.serve(minecraft,'127.0.0.1',0)
        try:
            async with websockets.connect(f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}') as socket:
                self.host.outbound.append({'t':'coopblocks','scene':self.host.scene,'rows':[[1,1,1,17]]})
                event=self.host.peek_events()[0]
                await socket.send(json.dumps(event));self.host.mark_sent(event)
                first=await asyncio.wait_for(received.get(),1)
                self.assertFalse(self.host.peek_events(),'WS send alone must not complete application delivery')
                self.assertEqual(len(self.host.outbound),1)
                await asyncio.sleep(.27)
                resend=self.host.peek_events()[0];self.assertEqual(resend['roomreceipt'],first['roomreceipt'])
                await socket.send(json.dumps(resend));self.host.mark_sent(resend)
                await asyncio.wait_for(received.get(),1)
                release.set()
                ack=json.loads(await asyncio.wait_for(socket.recv(),1))
                self.assertTrue(self.host.ack_event(ack));self.assertFalse(self.host.outbound)
                self.assertFalse(self.host.ack_event(ack),'Duplicate ACK must not complete another event')
        finally:
            release.set();server.close();await server.wait_closed()

    async def test_application_ack_out_of_order_keeps_earlier_lan_delivery(self):
        self.assertTrue(hasattr(self.host,'ack_event'),'Application ACK validation is required')
        remote=await self.join()
        for index in range(2):self.host.guest_event({'t':'peerblocks','scene':self.host.scene,'rows':[[index,1,1,17]]})
        await until(lambda:len(remote.outbound)==2)
        first,second=remote.peek_events()
        remote.mark_sent(first);remote.mark_sent(second)
        self.assertFalse(remote.ack_event({'t':'roomack','id':first['roomreceipt'],'scene':-1}))
        self.assertTrue(remote.ack_event({'t':'roomack','id':second['roomreceipt'],'scene':remote.scene}))
        self.assertEqual(remote.delivery_ack,0);self.assertEqual(len(remote.outbound),2)
        self.assertFalse(remote.ack_event({'t':'roomack','id':second['roomreceipt'],'scene':remote.scene}))
        self.assertEqual(len(remote.outbound),2,'Duplicate later ACK must not drop the pending earlier delivery')
        self.assertTrue(remote.ack_event({'t':'roomack','id':first['roomreceipt'],'scene':remote.scene}))
        self.assertEqual(remote.delivery_ack,second['_delivery']);self.assertFalse(remote.outbound)
        self.assertFalse(remote.ack_event({'t':'roomack','id':second['roomreceipt'],'scene':remote.scene}))

    async def test_scene_reset_invalidates_pending_application_receipt(self):
        self.assertTrue(hasattr(self.host,'ack_event'),'Application ACK validation is required')
        self.host.outbound.append({'t':'coopblocks','scene':self.host.scene,'rows':[[1,1,1,17]]})
        pending=self.host.peek_events()[0];self.host.mark_sent(pending)
        old=self.host.scene;self.epoch=2
        await until(lambda:self.host.scene!=old)
        self.host.outbound.append({'t':'coopblocks','scene':self.host.scene,'rows':[[2,1,1,17]]})
        current=self.host.peek_events()[0]
        self.assertFalse(self.host.ack_event({'t':'roomack','id':pending['roomreceipt'],'scene':old}))
        self.assertEqual(self.host.peek_events()[0]['roomreceipt'],current['roomreceipt'])

    async def test_damage_sequence_survives_room_process_restart(self):
        await self.join()
        self.host.apply_guest(2,{'t':'peerentitystate','scene':self.host.scene,'rows':[[7,'minecraft:pig',10,1,0,0,0]]})
        event={'t':'peerattack','scene':self.host.scene,'owner':2,'id':7,'d':4}
        self.host.guest_event(event);first=self.host.inboxes[2][-1]['seq']
        self.host.attack_sequence=0
        self.host.guest_event(event);second=self.host.inboxes[2][-1]['seq']
        self.assertGreater(second,first);self.assertLess(second,2**63)

    async def test_owner_attack_inbox_replays_until_delivery_ack(self):
        async def connect():
            socket=await websockets.connect(f'ws://127.0.0.1:{self.port}')
            await socket.send(json.dumps({'t':'join','token':TOKEN,'userid':2,'session':'owner-session'}))
            await socket.recv();return socket
        socket=await connect()
        try:
            self.host.apply_guest(2,{'t':'peerentitystate','scene':self.host.scene,'rows':[[7,'minecraft:pig',10,1,0,0,0]]})
            self.host.guest_event({'t':'peerattack','scene':self.host.scene,'owner':2,'id':7,'d':4})
            await socket.send(json.dumps({'t':'tick','scene':self.host.scene}))
            first=json.loads(await socket.recv())['events'][0]
            self.assertEqual(first['t'],'peerattack')
        finally:await socket.close()
        await until(lambda:2 not in self.host.clients)
        socket=await connect()
        try:
            await socket.send(json.dumps({'t':'tick','scene':self.host.scene}))
            replay=json.loads(await socket.recv())['events'][0]
            self.assertEqual(replay,first)
            await socket.send(json.dumps({'t':'tick','scene':self.host.scene,'delivery_ack':replay['_delivery']}))
            self.assertFalse(json.loads(await socket.recv())['events'])
        finally:await socket.close()

    async def test_room_delivery_applies_backpressure_until_local_commit(self):
        remote=await self.join()
        for index in range(20):
            self.host.guest_event({'t':'peerblocks','scene':self.host.scene,'rows':[[index,1,1,17]]})
        await until(lambda:len(remote.outbound)==8)
        await asyncio.sleep(.15)
        self.assertEqual(len(remote.outbound),8)
        self.assertEqual(remote.delivery_ack,0)
        self.assertIsNotNone(RoomSource(remote).read(),'Congested events must not stop camera samples')
        first=remote.peek_events();remote.commit_events(first)
        self.assertGreater(remote.delivery_ack,0)
        await until(lambda:len(remote.outbound)==8)
        next_rows=[row[0] for event in remote.peek_events() for row in event['rows']]
        self.assertEqual(next_rows,list(range(8,16)))

    async def test_malformed_greeting_closes_cleanly_without_poisoning_room(self):
        for greeting in ([],{'userid':{},'token':TOKEN}):
            async with websockets.connect(f'ws://127.0.0.1:{self.port}') as socket:
                await socket.send(json.dumps(greeting))
                try:await socket.recv()
                except websockets.exceptions.ConnectionClosed as closed:self.assertEqual(closed.code,1008)
        remote=await self.join();self.assertIsNotNone(RoomSource(remote).read())

    async def test_malformed_host_sample_retries_instead_of_killing_worker(self):
        async def malformed(socket,path=None):
            try:
                await socket.recv();await socket.send(json.dumps({'t':'joined','userid':2}))
                await socket.recv();await socket.send(json.dumps({'t':'tick','sample':[1],'scene':self.host.scene}))
                await socket.wait_closed()
            except websockets.exceptions.ConnectionClosed:return
        server=await websockets.serve(malformed,'127.0.0.1',0)
        try:
            config={'mode':'join','server':f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}','token':TOKEN,'userid':2}
            self.remote=CoopLink(config,Path(self.temp.name)/'malformed',scene_token)
            await self.remote.start()
            await until(lambda:self.remote.task.done() or self.remote.status['state']=='retrying')
            self.assertFalse(self.remote.task.done(),'Malformed sample must not kill reconnect worker')
            self.assertEqual(self.remote.status['state'],'retrying')
        finally:
            await self.remote.close();server.close();await server.wait_closed()

    async def test_missing_player_reports_actionable_reason_without_token(self):
        config={'mode':'join','server':f'ws://127.0.0.1:{self.port}','token':TOKEN,'player':'Wrong Name'}
        self.remote=CoopLink(config,Path(self.temp.name)/'missing',scene_token)
        await self.remote.start()
        await until(lambda:self.remote.status['state']=='retrying')
        status=(self.remote.ems/'l4d2mc_room_status.txt').read_text()
        self.assertIn('exact player name',status)
        self.assertIn('Remote Survivor',status)
        self.assertNotIn(TOKEN,status)
        self.assertNotIn('Wrong Name',status)

    async def test_stale_host_reports_source_instead_of_bad_player(self):
        self.frozen=True
        await until(lambda:not self.host.ready)
        async with websockets.connect(f'ws://127.0.0.1:{self.port}') as socket:
            await socket.send(json.dumps({'t':'join','token':TOKEN,'userid':99}))
            self.assertEqual(json.loads(await socket.recv())['reason'],'source')
            with self.assertRaises(websockets.exceptions.ConnectionClosed) as rejected:await socket.recv()
            self.assertEqual(rejected.exception.reason,'l4d2mc:source')

    async def test_failed_background_task_is_not_silent(self):
        async def fail():raise ValueError('worker failure')
        link=CoopLink({'mode':'join'},Path(self.temp.name)/'failed',scene_token)
        link.task=asyncio.create_task(fail())
        await asyncio.gather(link.task,return_exceptions=True)
        with self.assertRaisesRegex(RuntimeError,'Co-op worker failed'):link.check_task()

    async def test_initial_none_scene_handshake_and_private_actor_files(self):
        remote=await self.join()
        self.assertEqual(RoomSource(remote).read()['feet'],pose(2,self.frame)['feet'])
        self.assertEqual(remote.peers['players'][0]['id'],1)
        text='generation c1m1_hotel 1 12 0 0 0 0 1\nend 12 0'
        remote.files['gameplay']=text
        target=self.ems/'l4d2mc_coop_2.txt'
        await until(target.exists)
        self.assertEqual(target.read_text(),text)
        self.assertFalse((self.ems/'l4d2mc_coop_1.txt').exists())
        self.assertFalse((self.ems/'l4d2mc_gameplay.txt').exists())

    async def test_slow_recipient_queue_resync_does_not_disconnect_sender(self):
        remote=await self.join();original=self.host.clients[2]['socket']
        async with websockets.connect(f'ws://127.0.0.1:{self.port}') as slow:
            await slow.send(json.dumps({'t':'join','token':TOKEN,'userid':3}))
            self.assertEqual(json.loads(await slow.recv())['t'],'joined')
            queue=self.host.clients[3]['events']
            queue.extend({'t':'coopblocks','scene':self.host.scene,'rows':[[1,1,1,17]]} for _ in range(256))
            remote.guest_event({'t':'peerblocks','scene':remote.scene,'rows':[[9,2,3,17]]})
            await until(lambda:self.host.ledger.get((9,2,3))==17)
            await asyncio.sleep(.1)
            self.assertIs(self.host.clients[2]['socket'],original)
            self.assertIsNotNone(RoomSource(remote).read())
            self.assertLess(len(queue),256)
            self.assertTrue(any(row==[9,2,3,17] for event in queue for row in event.get('rows',[])))

    async def test_source_userid_reassignment_reconnects_by_unique_name(self):
        remote=await self.join(player='Remote Survivor');old=self.host.clients[2]['socket']
        self.peer_uid=4
        await until(lambda:4 in self.host.players)
        await until(lambda:2 not in self.host.clients and 4 in self.host.clients,timeout=4)
        self.assertTrue(old.closed if hasattr(old,'closed') else old.state.name=='CLOSED')
        await until(lambda:RoomSource(remote).read() is not None and RoomSource(remote).read()['feet'][0]==4*320)
        text='generation c1m1_hotel 1 12 0 0 0 0 1\nend 12 0'
        remote.files['gameplay']=text
        await until((self.ems/'l4d2mc_coop_4.txt').exists)
        self.assertFalse((self.ems/'l4d2mc_coop_2.txt').exists())

    async def test_block_events_no_echo_and_tombstone_delivery(self):
        remote=await self.join();remote.pop_events();self.host.pop_events()
        remote.guest_event({'t':'peerblocks','scene':remote.scene,'rows':[[4,2,6,17]]})
        await until(lambda:self.host.ledger.get((4,2,6))==17)
        await asyncio.sleep(.12)
        self.assertTrue(any(e.get('rows')==[[4,2,6,17]] for e in self.host.pop_events()))
        self.assertFalse(any(e.get('rows')==[[4,2,6,17]] for e in remote.pop_events()))
        self.host.guest_event({'t':'peerblocks','scene':self.host.scene,'rows':[[4,2,6,0]]})
        await until(lambda:any(e.get('rows')==[[4,2,6,0]] for e in remote.outbound))
        self.assertEqual(self.host.ledger.get((4,2,6)),0)

    async def test_same_scene_reconnect_bootstrap_delivers_offline_tombstones(self):
        scene=self.host.scene
        self.host.guest_event({'t':'peerblocks','scene':scene,'rows':[[5,2,3,17],[6,2,3,18]]})
        remote=await self.join()
        await until(lambda:any(e.get('t')=='coopblocks' for e in remote.outbound))
        materialized={}
        def apply(events):
            for event in events:
                if event.get('t')=='coopblocks':
                    for x,y,z,state in event['rows']:
                        if state:materialized[(x,y,z)]=state
                        else:materialized.pop((x,y,z),None)
        apply(remote.pop_events());self.assertEqual(materialized[(5,2,3)],17)
        await remote.close();self.remote=None
        await until(lambda:2 not in self.host.clients)
        self.host.guest_event({'t':'peerblocks','scene':scene,'rows':[[5,2,3,0]]})
        remote=await self.join()
        await until(lambda:any(row==[5,2,3,0] for e in remote.outbound for row in e.get('rows',[])))
        apply(remote.pop_events())
        self.assertNotIn((5,2,3),materialized)
        self.assertEqual(materialized[(6,2,3)],18)

    async def test_bootstrap_fills_missing_cells_without_overwriting_live_or_deleted(self):
        scene=self.host.scene
        self.host.guest_event({'t':'peerblocks','scene':scene,'rows':[[2,3,4,17],[3,3,4,0]]})
        self.host.pop_events()
        self.host.apply_guest(3,{'t':'peerblocks','scene':scene,'bootstrap':True,'rows':[[2,3,4,55],[3,3,4,55],[4,3,4,55]]})
        self.assertEqual(self.host.ledger[(2,3,4)],17)
        self.assertEqual(self.host.ledger[(3,3,4)],0)
        self.assertEqual(self.host.ledger[(4,3,4)],55)
        sent=[row for event in self.host.pop_events() for row in event.get('rows',[])]
        self.assertEqual(sent,[[4,3,4,55]],'Ignored bootstrap rows must not overwrite remote guest worlds')

    async def test_source_frame_expires_even_with_fresh_file_and_live_network(self):
        remote=await self.join();self.frozen=True
        frozen=(self.host.scene,self.frame)
        # Export, host ingestion and remote delivery are separate scheduling
        # boundaries. First consume the last frame exported before the freeze;
        # an older received-age timeout does not mean that final frame expired.
        await until(lambda:self.host.pose_identity==frozen and remote.pose_identity==frozen)
        host_pose_at=self.host.pose_at;remote_pose_at=remote.pose_at
        await until(lambda:not self.host.ready and remote.sample is None)
        received=remote.received
        await until(lambda:remote.received>received)
        self.assertLess(time.monotonic()-remote.received,LEASE)
        self.assertIn(2,self.host.clients)
        self.assertIsNone(RoomSource(self.host).read())
        self.assertIsNone(RoomSource(remote).read())
        self.assertIsNone(self.host.peers,'Host must not continually republish frozen Source avatars')
        self.assertEqual(self.host.pose_identity,frozen);self.assertEqual(remote.pose_identity,frozen)
        self.assertEqual(self.host.pose_at,host_pose_at,'Fresh files must not renew a frozen frame lease')
        self.assertEqual(remote.pose_at,remote_pose_at,'Fresh network ticks must not renew a frozen frame lease')

    async def test_client_watchdog_expires_repeated_pose_even_when_host_keeps_sending_it(self):
        async def frozen_host(socket,path=None):
            try:
                await socket.recv();await socket.send(json.dumps({'t':'joined','userid':2}))
                async for raw in socket:
                    await socket.send(json.dumps({'t':'tick','scene':self.host.scene,'sample':pose(2,91),'events':[]}))
            except websockets.exceptions.ConnectionClosed:return
        server=await websockets.serve(frozen_host,'127.0.0.1',0)
        try:
            config={'mode':'join','server':f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}','token':TOKEN,'userid':2}
            self.remote=CoopLink(config,Path(self.temp.name)/'repeated-pose',scene_token)
            await self.remote.start()
            await until(lambda:RoomSource(self.remote).read() is not None)
            pose_at=self.remote.pose_at
            await until(lambda:self.remote.status['state']=='waiting_source')
            received=self.remote.received
            await until(lambda:self.remote.received>received)
            self.assertIsNotNone(self.remote.sample,'Test host continues sending its frozen pose')
            self.assertIsNone(RoomSource(self.remote).read(),'Repeated frames must never revive the client watchdog')
            self.assertEqual(self.remote.pose_at,pose_at)
        finally:
            await self.remote.close();server.close();await server.wait_closed()

    async def test_scene_reset_clears_room_state_and_ignores_old_blocks(self):
        remote=await self.join();old=self.host.scene
        self.host.guest_event({'t':'peerblocks','scene':old,'rows':[[3,4,5,17]]})
        self.host.collisions[2]=([(3,4,5)],time.monotonic())
        self.host.metadata[2]=({'main':'minecraft:diamond_sword'},time.monotonic())
        self.epoch=2
        await until(lambda:self.host.scene!=old and remote.scene==self.host.scene)
        self.assertFalse(self.host.ledger);self.assertFalse(self.host.collisions);self.assertFalse(self.host.metadata)
        remote.guest_event({'t':'peerblocks','scene':old,'rows':[[6,7,8,17]]})
        await asyncio.sleep(.12);self.assertFalse(self.host.ledger)

    async def test_colliders_union_is_bounded_and_sorted_for_all_actor_positions(self):
        remote=await self.join()
        local=[(x,0,0) for x in range(1,301)]
        other=[(x,0,1) for x in range(1,301)]
        def file(rows):return '12 c1m1_hotel 1\n'+'\n'.join('%d %d %d'%row for row in rows)+f'\nend 12 {len(rows)}'
        self.host.files['collision']=file(local);remote.files['collision']=file(other)
        output=self.ems/'l4d2mc_collision.txt'
        await until(lambda:output.exists() and len(output.read_text().splitlines())==514)
        lines=output.read_text().splitlines();cells=[tuple(map(int,row.split())) for row in lines[1:-1]]
        self.assertEqual(len(cells),512);self.assertEqual(len(set(cells)),512)
        self.assertTrue(any(row[2]==0 for row in cells));self.assertTrue(any(row[2]==1 for row in cells))
        self.assertEqual(lines[-1],f'end {lines[0].split()[0]} 512')

    async def test_partial_gameplay_snapshot_is_not_written(self):
        # Incomplete data must not replace the last complete per-actor mailbox.
        complete='generation c1m1_hotel 1 12 0 0 0 0 1\nend 12 0'
        self.host.accept_file(2,'gameplay',complete)
        partial='generation c1m1_hotel 1 13 0 0 0 0 1\nevent 9 interact'
        try:self.host.accept_file(2,'gameplay',partial)
        except ValueError:pass
        self.assertEqual((self.ems/'l4d2mc_coop_2.txt').read_text(),complete)

    async def test_peer_entity_ids_are_scoped_to_authenticated_owner(self):
        remote=await self.join()
        local_row=[7,'minecraft:pig',1,2,3,90,0]
        remote_row=[7,'minecraft:iron_golem',4,5,6,180,0]
        self.host.guest_event({'t':'peerentitystate','scene':self.host.scene,'rows':[local_row]})
        remote.guest_event({'t':'peerentitystate','scene':remote.scene,'owner':1,'rows':[remote_row]})
        await until(lambda:2 in self.host.entity_states)
        await until(lambda:remote.peer_entities is not None and remote.peer_entities['owners'])
        owners={r['id']:r['rows'] for r in self.host.entities(0)['owners']}
        self.assertEqual(owners[1],[local_row]);self.assertEqual(owners[2],[remote_row])
        self.assertEqual(remote.peer_entities['owners'],[{'id':1,'rows':[local_row]}])
        await until(lambda:self.host.peer_entities is not None and self.host.peer_entities['owners'])
        self.assertEqual(self.host.peer_entities['owners'],[{'id':2,'rows':[remote_row]}])

    async def test_peer_entity_expiration_and_scene_reset_clear_owned_proxies(self):
        remote=await self.join()
        event={'t':'peerentitystate','scene':remote.scene,'rows':[[8,'minecraft:goat',1,2,3,90,0]]}
        remote.guest_event(event);await until(lambda:2 in self.host.entity_states)
        rows,_=self.host.entity_states[2];self.host.entity_states[2]=(rows,time.monotonic()-LEASE-.01)
        await until(lambda:self.host.peer_entities is not None and not self.host.peer_entities['owners'])
        self.assertIn(2,self.host.clients,'Only the expired entity state is removed, not the connected player')
        remote.guest_event(event);await until(lambda:self.host.entity_states[2][1]>time.monotonic()-LEASE)
        old=self.host.scene;self.epoch=2
        await until(lambda:self.host.scene!=old and remote.scene==self.host.scene)
        self.assertFalse(self.host.entity_states)
        remote.guest_event(event);await asyncio.sleep(.1);self.assertFalse(self.host.entity_states)

    async def test_peer_entity_snapshot_bounds_preserve_last_valid_state(self):
        row=[8,'minecraft:goat',1,2,3,90,0]
        base={'t':'peerentitystate','scene':self.host.scene,'rows':[row]}
        self.host.apply_guest(1,base)
        malformed=[[[i+1,'minecraft:goat',1,2,3,0,0] for i in range(65)],
            [[8,'minecraft:goat',1024,2,3,0,0]],[[8,'minecraft:goat',1,2,3,361,0]],
            [[8,'bad registry',1,2,3,0,0]],[row,row],[[True,'minecraft:goat',1,2,3,0,0]],
            [[8,'minecraft:goat',float('nan'),2,3,0,0]]]
        for rows in malformed:
            with self.assertRaises(ValueError):self.host.apply_guest(1,{**base,'rows':rows})
            self.assertEqual(self.host.entity_states[1][0],[row])
        maximum=[[i+1,'minecraft:goat',1,2,3,0,0] for i in range(64)]
        self.host.apply_guest(1,{**base,'rows':maximum})
        self.assertEqual(len(self.host.entity_states[1][0]),64)

    async def test_peer_actions_survive_latest_snapshots(self):
        remote=await self.join()
        event={'t':'avatar','scene':remote.scene,'main':'minecraft:diamond_sword','off':'minecraft:shield','swing':9,'swinghand':'main','using':True,'usehand':'off'}
        remote.guest_event(event)
        await until(lambda:self.host.metadata.get(2,({},0))[0].get('swing')==9)
        self.assertTrue(self.host.roster(1)['players'][0]['using'])
        self.assertEqual(self.host.roster(1)['players'][0]['usehand'],'off')
        for bad in ({'swing':True},{'swing':-1},{'using':'yes'},{'usehand':'invalid'}):
            with self.assertRaises(ValueError):self.host.apply_guest(2,{**event,**bad})
        self.assertEqual(self.host.metadata[2][0]['swing'],9)

if __name__=='__main__':unittest.main()
