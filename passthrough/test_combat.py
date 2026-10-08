import tempfile
import unittest
from pathlib import Path
from combat import GameplayMailbox,source_position


class CombatTests(unittest.TestCase):
    def test_damage_units_and_axes(self):
        self.assertEqual(source_position([2,90,-175]),(64,5600,2880))
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'explosion','pos':[2,90,-175],'r':4})
            box.apply({'t':'melee','d':7,'r':3})
            box.publish('c1m1_hotel')
            s=box.path.read_text();self.assertIn('explosion 64 5600 2880 128.0',s);self.assertIn('melee 105.0 96.0',s)

    def test_no_executable_tokens_and_atomic_entity_snapshot(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'mobs','m':[[1,'creeper',2,90,-175]]})
            for bad in [[2,'x;quit',0,0,0],[2,'zombie',float('nan'),0,0]]:
                with self.assertRaises(ValueError):box.apply({'t':'mobs','m':[bad]})
            self.assertEqual(len(box.mobs),1)

    def test_bounded_replay_and_map_disconnect_cleanup(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            for i in range(40):box.apply({'t':'interact'})
            self.assertEqual(len(box.events),32)
            self.assertEqual(box.events[0][0],9)
            box.publish('c1m1_hotel');box.publish('c1m2_streets')
            self.assertEqual(len(box.events),0)
            box.apply({'t':'interact'});box.publish('c1m2_streets',active=False)
            self.assertEqual(len(box.path.read_text().splitlines()),1)

    def test_mob_hit_carries_attacker_for_source_trace_filter(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'mobhit','h':123,'id':456,'d':3,'from':[2,90,-175]})
            box.publish('c1m1_hotel')
            self.assertIn('mobhit 123 15.0 64 5600 2880 456',box.path.read_text())

    def test_food_heal_is_bounded_and_in_source_health_units(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'heal','h':20});box.publish('c1m1_hotel')
            self.assertIn('heal 20.0',box.path.read_text())
            for h in [0,101,float('nan'),True]:
                with self.assertRaises(ValueError):box.apply({'t':'heal','h':h})

    def test_teleports_and_held_actions_are_data_only(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'pteleport','pos':[2,90,-175]})
            box.apply({'t':'chorus'})
            box.publish('c2m1_highway',attack=True,use=True)
            text=box.path.read_text()
            self.assertEqual(text.splitlines()[0].split()[-2:],['1','1'])
            self.assertIn('teleport 64 5600 2880',text)
            self.assertIn('chorus',text)
            with self.assertRaises(ValueError):box.apply({'t':'pteleport','pos':[float('nan'),0,0]})
