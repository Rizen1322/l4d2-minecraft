import math
import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch
from bridge import CollisionSnapshot, camera, position, surface, render_camera, relay_keys,HostInput,SourceSnapshot,parse_movement_bindings,movement_mask,RewardOutbox


class SessionTests(unittest.TestCase):
    def test_full_collision_cache_keeps_complete_new_region_and_evicts_old_far_cells(self):
        with tempfile.TemporaryDirectory() as d:
            cache=CollisionSnapshot(Path(d)/'collision')
            cache.cells={(x,y,-1) for x in range(-1000,-900) for y in range(100)}
            cache.apply({'t':'blocks','bounds':[10,0,10,10,1,10],'set':[10,0,10,10,1,10]})
            self.assertEqual(len(cache.cells),10000)
            self.assertTrue({(10,0,10),(10,1,10)}<=cache.cells)
            cache.apply({'t':'blocks','bounds':[10,0,10,10,1,10],'set':[]})
            self.assertTrue({(10,0,10),(10,1,10)}.isdisjoint(cache.cells))
            cache.publish('c1m1_hotel',[100,0,100],active=False)
            cache.apply({'t':'blocks','set':[100,0,100]})
            self.assertIn((100,0,100),cache.cells)
            self.assertLessEqual(len(cache.cells),10000)
    def test_disconnect_releases_native_input_and_reconnect_reasserts_held_button(self):
        from bridge import reset_input_session
        from types import SimpleNamespace
        calls=[]
        inputs=SimpleNamespace(enabled=True,focused=True,gui_open=True,was_gui=True,
            down={1:True},world_down={2:True},gui_down={0x45:True},repeat_at={0x45:123})
        memory=SimpleNamespace(input=lambda *args:calls.append(('input',args)))
        host=SimpleNamespace(set_gui=lambda open:calls.append(('gui',open)),controls=lambda active:calls.append(('controls',active)))
        reset_input_session(inputs,memory,host)
        self.assertFalse(inputs.enabled or inputs.focused or inputs.gui_open or inputs.was_gui)
        self.assertIn(('input',(False,False,0)),calls)
        self.assertIn(('controls',False),calls)
        self.assertEqual(inputs.down,{})
        self.assertEqual(inputs.gui_down,{})
        self.assertEqual(inputs.repeat_at,{})
        self.assertEqual(relay_keys({2},inputs.world_down,focused=True,gui=False),[{'t':'key','k':'use','down':True}])

    def test_source_snapshots_are_not_queued_for_each_new_render_camera_frame(self):
        from bridge import SourceUpdateGate
        gate=SourceUpdateGate();sample={'map':'c1m1_hotel','epoch':12,'f':20}
        self.assertTrue(gate.changed(sample,False))
        for _ in range(120):self.assertFalse(gate.changed(sample,False))
        self.assertTrue(gate.changed(sample,True)) # Retry snapshots rejected during world preparation.
        self.assertFalse(gate.changed(sample,True))
        self.assertTrue(gate.changed(dict(sample,f=21),True))
        self.assertTrue(gate.changed(dict(sample,epoch=13),True))

    def test_rewards_survive_map_load_and_invalid_tokens_are_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'rewards';box=RewardOutbox(path)
            path.write_text('c1m1_hotel_1 c1m1_hotel 0 2\nbad;quit c1m2_streets 0 0\nc1m4_atrium_2 c1m4_atrium 1 1\x00')
            rewards=box.read();self.assertEqual(len(rewards),2)
            self.assertEqual(rewards[0]['difficulty'],2);self.assertTrue(rewards[1]['finale'])
            path.write_text('x'*9000);self.assertEqual(box.read(),[])

    def test_partial_source_write_keeps_last_valid_sample(self):
        with tempfile.TemporaryDirectory() as directory:
            file=Path(directory)/'pose'
            sample={"v":1,"f":1,"map":"c1m1_hotel","p":[0,0,64],"feet":[0,0,0],"r":[0,0,0],"hfov":90}
            import json
            file.write_text(json.dumps(sample));reader=SourceSnapshot(file)
            with patch('bridge.time.monotonic',return_value=10):self.assertEqual(reader.read(),sample)
            file.write_text('{')
            with patch('bridge.time.monotonic',return_value=10.1):self.assertEqual(reader.read(),sample)
            with patch('bridge.time.monotonic',return_value=11.2):self.assertIsNone(reader.read())
    def test_gui_close_movement_uses_actual_source_binds(self):
        bindings=parse_movement_bindings('bind "w" "+forward; r_cleardecals"\nbind "CTRL" "+duck"\nbind "SHIFT" "+speed"\nbind "e" "+use"')
        self.assertEqual(movement_mask({0x57,0x11},bindings),1|32)
        self.assertEqual(movement_mask({0x45},bindings),0)

class InputTests(unittest.TestCase):
    @unittest.skipUnless(__import__('sys').platform=='win32','Windows named mutex')
    def test_second_bridge_exits_before_connecting_or_touching_games(self):
        import ctypes,subprocess,sys
        kernel=ctypes.WinDLL('kernel32',use_last_error=True);kernel.CreateMutexW.restype=ctypes.c_void_p
        lock=kernel.CreateMutexW(None,True,r'Local\L4D2MinecraftBridge')
        if not lock:self.fail('Cannot create regression lock')
        try:
            child=subprocess.run([sys.executable,str(Path(__file__).with_name('bridge.py'))],capture_output=True,text=True,timeout=5)
            self.assertNotEqual(child.returncode,0)
            self.assertIn('already running',child.stderr)
            self.assertNotIn('connected',child.stdout)
        finally:kernel.CloseHandle(ctypes.c_void_p(lock))

    def test_escape_is_owned_by_source_in_inventory_and_world(self):
        for gui in (True,False):
            state={}
            self.assertEqual(relay_keys({0x1B},state,focused=True,gui=gui),[])
            self.assertEqual(relay_keys(set(),state,focused=True,gui=gui),[])

    def test_inventory_close_does_not_reopen_while_e_still_held(self):
        state={}
        relay_keys({0x45},state,focused=True,gui=False)
        relay_keys(set(),state,focused=True,gui=True)
        self.assertEqual(relay_keys({0x45},state,focused=True,gui=True),[])
        self.assertEqual(relay_keys({0x45},state,focused=True,gui=False),[])
        relay_keys(set(),state,focused=True,gui=False)
        self.assertIn({'t':'key','k':'inventory','down':True},relay_keys({0x45},state,focused=True,gui=False))

    def test_source_walk_and_jump_keys_are_not_replaced(self):
        self.assertEqual(relay_keys({0x10,0x11,0x57,0x20},{},focused=True,gui=False),[])

    def test_cleanup_never_relaunches_absent_source(self):
        host=HostInput(Path('absent-source'))
        with patch.object(host,'_window',return_value=None),patch('bridge.subprocess.Popen') as launch:
            self.assertFalse(host._send(['+cl_mouseenable','1']))
            launch.assert_not_called()
    def test_commands_wait_until_source_finished_loading(self):
        host=HostInput(Path('absent-source'))
        with patch.object(host,'_window',return_value=123),patch.object(host,'_engine_ready',return_value=False),patch('bridge.subprocess.Popen') as launch:
            self.assertFalse(host._send(['+exec','test']))
            launch.assert_not_called()

    def test_minecraft_buttons_and_hotbar(self):
        state = {}
        messages = relay_keys({1,2,0x45,0x33}, state, focused=True, gui=False)
        self.assertIn({'t':'key','k':'attack','down':True},messages)
        self.assertIn({'t':'key','k':'use','down':True},messages)
        self.assertIn({'t':'key','k':'inventory','down':True},messages)
        self.assertIn({'t':'slot','n':2},messages)
        self.assertEqual(relay_keys({1,2,0x45,0x33},state,focused=True,gui=False), [])

    def test_open_gui_or_lost_focus_releases_world_buttons(self):
        state = {}
        relay_keys({1,2},state,focused=True,gui=False)
        released=relay_keys({1,2},state,focused=True,gui=True)
        self.assertIn({'t':'key','k':'attack','down':False},released)
        self.assertIn({'t':'key','k':'use','down':False},released)
        relay_keys({1},state,focused=True,gui=False)
        self.assertIn({'t':'key','k':'attack','down':False},relay_keys({1},state,focused=False,gui=False))


class CameraTests(unittest.TestCase):
    def test_pin_kind_and_native_team_card_count_survive_camera_relay(self):
        sample={"v":1,"f":1,"p":[0,0,64],"feet":[0,0,0],"r":[0,0,0],"hfov":90,"pin":"hunter","teammates":3}
        pose=camera(sample,16/9)
        self.assertEqual(pose['pin'],'hunter');self.assertEqual(pose['teammates'],3)
        sample.update(pin='unknown',teammates=20)
        pose=camera(sample,16/9)
        self.assertEqual(pose['pin'],'none');self.assertEqual(pose['teammates'],3)
        sample['teamhud']=[{'name':'Ellis','character':'ellis','hp':75,'temp':10,'max':100,'incap':False,'dead':False}]
        self.assertEqual(camera(sample,16/9)['teamhud'],sample['teamhud'])
        sample.pop('teamhud');self.assertEqual(camera(sample,16/9)['teamhud'],[])

    def test_cutscene_visibility_survives_camera_conversion(self):
        sample={"v":1,"f":2,"p":[0,0,64],"feet":[0,0,0],"r":[0,0,0],"hfov":90,"visible":False}
        self.assertFalse(camera(sample,16/9)['visible'])

    def test_source_crouch_and_door_state_survive_camera_conversion(self):
        sample={"v":1,"f":2,"p":[0,0,64],"feet":[0,0,0],"r":[0,0,0],"hfov":90,"buttons":4,"usable":True}
        pose=camera(sample,16/9)
        self.assertTrue(pose['sneak']);self.assertTrue(pose['usable'])

    def test_render_view_outlier_never_teleports_guest_camera(self):
        pose = {'p':[20.088867,90.961929,-181.631287], 'r':[23.2474,14.50185,0], 'fov':73.7398}
        good = dict(pose, fov=104.8218, render_sequence=100)
        sky = dict(good, p=[252.284027,-28.657433,-401.207214], render_sequence=102)
        selected = render_camera(pose, sky, good)
        self.assertEqual(selected['p'], pose['p'])
        self.assertEqual(selected['fov'], good['fov'])
        self.assertNotIn('render_sequence', selected)

    def test_real_render_camera_keeps_bob_and_calibration(self):
        pose = {'p':[20,90,-181], 'r':[23,14,0], 'fov':73.7398}
        actual = dict(pose, p=[20.02,90.1,-181], fov=104.8218, render_sequence=100)
        self.assertEqual(render_camera(pose,actual)['p'], actual['p'])
        self.assertEqual(render_camera(pose,actual)['fov'], actual['fov'])

    def test_real_teleport_follows_new_player_eye(self):
        previous = {'p':[20,90,-181], 'r':[23,14,0], 'fov':104.8218, 'render_sequence':100}
        moved = {'p':[200,20,50], 'r':[45,0,0], 'fov':73.7398}
        selected = render_camera(moved,previous,previous)
        self.assertEqual(selected['p'], moved['p'])
        self.assertEqual(selected['r'], moved['r'])
        self.assertEqual(selected['fov'], previous['fov'])
    def test_source_axes_and_negative_coordinates(self):
        self.assertEqual(position([-32, 64, 96]), [-1, 3, -2])

    def test_forward_vectors_match_in_both_engines(self):
        for yaw in (0, 90, 180, -90, 37):
            source = [32*math.cos(math.radians(yaw)), 32*math.sin(math.radians(yaw)), 0]
            mapped = position(source)
            mc_yaw = math.radians(-yaw-90)
            self.assertAlmostEqual(mapped[0], -math.sin(mc_yaw))
            self.assertAlmostEqual(mapped[2], math.cos(mc_yaw))

    def test_camera_field_of_view_uses_source_reference_aspect(self):
        sample = {"v":1,"f":7,"p":[32,64,96],"feet":[32,64,32],"r":[0,10,0],"hfov":90}
        pose = camera(sample, 16/9)
        self.assertEqual(pose["r"], [-90,10,0])
        self.assertAlmostEqual(pose["fov"], 73.7397952917)
        self.assertEqual(pose["pl"], [1,1,-2])

    def test_nonfinite_pose_is_rejected(self):
        with self.assertRaises(ValueError):
            position([float("nan"),0,0])


class SurfaceTests(unittest.TestCase):
    def test_rough_floor_does_not_hover_one_voxel(self):
        support=surface({'hit':[64,96,97.28], 'normal':[0,0,1]})
        self.assertEqual(support['cell'],[2,3,-3])


    def test_non_grid_floor_keeps_whole_cube_above_surface(self):
        support = surface({'hit':[64,96,2864], 'normal':[0,0,1]})
        self.assertEqual(support['cell'], [2,90,-3])
        self.assertGreaterEqual(support['cell'][1], support['pos'][1])

    def test_non_grid_wall_and_ceiling_do_not_embed_cube(self):
        self.assertEqual(surface({'hit':[80,96,2880], 'normal':[1,0,0]})['cell'], [3,90,-3])
        self.assertEqual(surface({'hit':[80,96,2880], 'normal':[-1,0,0]})['cell'], [1,90,-3])
        self.assertEqual(surface({'hit':[64,96,2864], 'normal':[0,0,-1]})['cell'], [2,88,-3])

    def test_floor_uses_outside_cell_and_tolerates_trace_roundoff(self):
        sample = {"hit":[64,96,2879.969], "normal":[0,0,1]}
        self.assertEqual(surface(sample)["cell"], [2,90,-3])
    def test_wall_and_ceiling_use_hit_normal(self):
        self.assertEqual(surface({"hit":[64,96,2880],"normal":[-1,0,0]})["cell"], [1,90,-3])
        self.assertEqual(surface({"hit":[64,96,2880],"normal":[0,0,-1]})["cell"], [2,89,-3])
    def test_miss_never_invents_support(self):
        self.assertIsNone(surface({"hit":None}))


class CollisionTests(unittest.TestCase):
    def test_changes_remove_cells_and_snapshot_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = CollisionSnapshot(Path(directory) / 'collision.txt')
            snapshot.apply({'t':'blocks','set':[v for x in range(600) for v in [x,90,-176]]})
            snapshot.apply({'t':'blocks','clear':[0,90,-176]})
            snapshot.publish('c1m1_hotel', [0,90,-176])
            lines = snapshot.path.read_text().splitlines()
            self.assertEqual(len(lines),514)
            self.assertEqual(lines[1], '1 90 -176')
            self.assertNotIn('0 90 -176',lines[1:])

    def test_authoritative_region_removes_missing_blocks_but_keeps_outside(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot=CollisionSnapshot(Path(directory)/'collision.txt')
            snapshot.apply({'t':'blocks','set':[1,90,1,2,90,1,100,90,1]})
            snapshot.apply({'t':'blocks','bounds':[0,0,0,10,100,10],'set':[2,90,1]})
            self.assertEqual(snapshot.cells,{(2,90,1),(100,90,1)})
            with self.assertRaises(ValueError):
                snapshot.apply({'t':'blocks','bounds':[0,0,0,10,100,10],'set':['bad',0,0]})
            self.assertEqual(snapshot.cells,{(2,90,1),(100,90,1)})

    def test_map_change_removes_old_collisions(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = CollisionSnapshot(Path(directory) / 'collision.txt')
            snapshot.apply({'t':'blocks','set':[1,90,-176]})
            snapshot.publish('c1m1_hotel',[0,90,0])
            snapshot.publish('c1m2_streets',[0,90,0])
            self.assertEqual(len(snapshot.path.read_text().splitlines()),2)

    def test_bad_cells_and_map_names_never_become_script(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = CollisionSnapshot(Path(directory) / 'collision.txt')
            for values in [[1,2], [True,0,0], [1024,0,0], ['print(1)',0,0]]:
                with self.assertRaises(ValueError):
                    snapshot.apply({'t':'blocks','set':values})
            with self.assertRaises(ValueError):
                snapshot.publish('x;quit',[0,0,0])

    def test_invalid_message_is_atomic_and_inactive_snapshot_is_empty(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = CollisionSnapshot(Path(directory)/'collision.txt')
            snapshot.apply({'t':'blocks','set':[1,90,-176]})
            with self.assertRaises(ValueError):
                snapshot.apply({'t':'blocks','set':[2,90,-176,'invalid',0,0]})
            self.assertEqual(snapshot.cells,{(1,90,-176)})
            snapshot.publish('c1m1_hotel',[0,90,0],active=False)
            self.assertEqual(len(snapshot.path.read_text().splitlines()),2)
            self.assertEqual(snapshot.cells,{(1,90,-176)})


if __name__ == "__main__":
    unittest.main()

class BodyCameraTests(unittest.TestCase):
    def test_client_body_uses_camera_frame_and_rejects_auxiliary_body(self):
        p={'p':[0,2,0],'pl':[0,0,0],'h':0,'fov':70}
        a={'p':[0,2,1],'pl':[0,0,.7],'h':45,'fov':70}
        self.assertEqual(render_camera(p,a)['pl'],[0,0,.7])
        a['pl']=[0,0,1000]
        self.assertEqual(render_camera(p,a)['pl'],p['pl'])

class PickupOutboxTests(unittest.TestCase):
    def test_pickup_survives_map_vm_and_rejects_unknown_items(self):
        from bridge import PickupOutbox
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'pickups';p.write_text('pickup_1_2 bow\npickup_1_3 speed_potion\npickup_1_4 weapon_gascan\npickup_bad;quit tnt\n\x00')
            self.assertEqual([v['item'] for v in PickupOutbox(p).read()],['bow','speed_potion'])

class SceneTests(unittest.TestCase):
    def test_map_and_same_map_restart_have_distinct_stable_tokens(self):
        from bridge import scene_token
        a=scene_token('c1m1_hotel',11)
        self.assertEqual(a,scene_token('c1m1_hotel',11))
        self.assertNotEqual(a,scene_token('c1m1_hotel',12))
        self.assertNotEqual(a,scene_token('c1m2_streets',11))
        self.assertTrue(0<a<2**63)
    def test_stale_block_snapshot_cannot_restore_old_collisions(self):
        with tempfile.TemporaryDirectory() as d:
            c=CollisionSnapshot(Path(d)/'collision');c.scene=22
            c.apply({'t':'blocks','scene':22,'set':[1,2,3]})
            c.apply({'t':'blocks','scene':11,'bounds':[-10,-10,-10,10,10,10],'set':[4,5,6]})
            self.assertEqual(c.cells,{(1,2,3)})
            c.apply({'t':'blocks','set':[9,9,9]})
            self.assertEqual(c.cells,{(1,2,3)})

class ScopedGameplayTests(unittest.TestCase):
    def test_old_combat_rejected_but_durable_receipts_survive(self):
        from bridge import accepts_scene
        for kind in ['melee','effects','mobs','phys','blocks','syncdone']:
            self.assertFalse(accepts_scene({'t':kind,'scene':1},2))
            self.assertTrue(accepts_scene({'t':kind,'scene':2},2))
        self.assertTrue(accepts_scene({'t':'pickupack','key':'pickup_1_2'},2))
        self.assertTrue(accepts_scene({'t':'rewardack','key':'c1m1_hotel_1'},2))

class FramedCollisionTests(unittest.TestCase):
    def test_epoch_and_final_record_count_identify_complete_snapshot(self):
        with tempfile.TemporaryDirectory() as d:
            c=CollisionSnapshot(Path(d)/'collision');c.epoch=17
            c.apply({'t':'blocks','set':[1,2,3,4,5,6]});c.publish('c1m1_hotel',[0,0,0])
            rows=c.path.read_text().splitlines();header=rows[0].split();footer=rows[-1].split()
            self.assertEqual(header[2],'17')
            self.assertEqual(footer,['end',header[0],str(len(rows)-2)])
