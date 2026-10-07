import math
import unittest
import tempfile
from pathlib import Path
from bridge import CollisionSnapshot, camera, position


class CameraTests(unittest.TestCase):
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
