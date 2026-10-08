import math
import unittest
import tempfile
from pathlib import Path
from bridge import CollisionSnapshot, camera, position, surface, render_camera


class CameraTests(unittest.TestCase):
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
            snapshot.apply({'t':'blocks','set':[v for x in range(200) for v in [x,90,-176]]})
            snapshot.apply({'t':'blocks','clear':[0,90,-176]})
            snapshot.publish('c1m1_hotel', [0,90,-176])
            lines = snapshot.path.read_text().splitlines()
            self.assertEqual(len(lines),129)
            self.assertEqual(lines[1], '1 90 -176')
            self.assertNotIn('0 90 -176',lines[1:])

    def test_map_change_removes_old_collisions(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = CollisionSnapshot(Path(directory) / 'collision.txt')
            snapshot.apply({'t':'blocks','set':[1,90,-176]})
            snapshot.publish('c1m1_hotel',[0,90,0])
            snapshot.publish('c1m2_streets',[0,90,0])
            self.assertEqual(len(snapshot.path.read_text().splitlines()),1)

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
            self.assertEqual(len(snapshot.path.read_text().splitlines()),1)
            self.assertEqual(snapshot.cells,{(1,90,-176)})


if __name__ == "__main__":
    unittest.main()
