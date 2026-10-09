import tempfile
import unittest
from pathlib import Path
from combat import GameplayMailbox,source_position


class CombatTests(unittest.TestCase):
    def test_mob_kind_survives_tunnel_for_golem_damage_and_rejects_tokens(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'mailbox')
            box.apply({'t':'mobhit','h':4,'id':9,'d':7,'from':[0,0,0],'k':'iron_golem'})
            box.publish('c1m1_hotel')
            self.assertIn('mobhit 4 35.0 0 0 0 9 iron_golem',box.path.read_text())
            with self.assertRaises(ValueError):box.apply({'t':'mobhit','h':4,'d':7,'from':[0,0,0],'k':'iron_golem;quit'})
    def test_enchantments_and_effects_expire_with_equipment(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'protection','e':[4,12,4,16,4],'resistance':2,'fireproof':True})
            box.publish('c1m1_hotel');self.assertIn('protection 4 12 4 16 4 2 1',box.path.read_text())
            for bad in [True,21,float('nan')]:
                with self.assertRaises(ValueError):box.apply({'t':'protection','e':[bad,0,0,0,0],'resistance':0,'fireproof':False})
            box.publish('c1m2_streets');self.assertNotIn('protection',box.path.read_text())

    def test_ignition_is_bounded_data_and_never_replayed_across_maps(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'ignite','pos':[2,90,-175]});box.publish('c1m1_hotel')
            self.assertIn('ignite 64 5600 2880',box.path.read_text())
            for bad in [[True,0,0],[1024,0,0],[float('inf'),0,0]]:
                with self.assertRaises(ValueError):box.apply({'t':'ignite','pos':bad})
            box.publish('c1m2_streets');self.assertNotIn('ignite',box.path.read_text())

    def test_sword_tier_and_tongue_cut_are_validated(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'melee','d':7,'r':3,'cut':True,'tier':1});box.publish('c1m1_hotel')
            self.assertIn('melee 105.0 96.0 1 1',box.path.read_text())
            for tier in [True,3,-1,'2']:
                with self.assertRaises(ValueError):box.apply({'t':'melee','tier':tier})
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
            self.assertEqual(len(box.path.read_text().splitlines()),2)

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
            self.assertEqual(text.splitlines()[0].split()[6:8],['1','1'])
            self.assertIn('teleport 64 5600 2880',text)
            self.assertIn('chorus',text)
            with self.assertRaises(ValueError):box.apply({'t':'pteleport','pos':[float('nan'),0,0]})

    def test_equipment_lease_is_bounded_and_cleared_on_map_change(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'equipment','armor':20,'toughness':8,'blocking':True})
            box.publish('c1m1_hotel')
            self.assertIn('equipment 20.0 8.0 1',box.path.read_text())
            box.publish('c1m2_streets')
            self.assertNotIn('equipment',box.path.read_text())
            for msg in [{'armor':21,'toughness':8,'blocking':True},
                        {'armor':20,'toughness':float('nan'),'blocking':True},
                        {'armor':20,'toughness':8,'blocking':'yes'}]:
                with self.assertRaises(ValueError):box.apply({'t':'equipment',**msg})

    def test_food_regeneration_and_bonus_are_data_only(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'meal','h':32,'golden':True})
            box.publish('c1m1_hotel')
            self.assertIn('meal 32.0 1',box.path.read_text())
            for h in [-1,101,float('inf'),True]:
                with self.assertRaises(ValueError):box.apply({'t':'meal','h':h,'golden':False})

    def test_redstone_link_positions_and_signal_rows_are_validated(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'link','pos':[2,90,-175]})
            box.apply({'t':'signals','s':[[2,90,-175,True]]})
            box.publish('c1m1_hotel')
            self.assertIn('link 2 90 -175',box.path.read_text())
            self.assertIn('signal 2 90 -175 1',box.path.read_text())
            for row in [[0,0,0,'true'],[0.5,0,0,True],[0,0,0,float('nan')]]:
                with self.assertRaises(ValueError):box.apply({'t':'signals','s':[row]})

    def test_expired_equipment_and_redstone_do_not_retain_protection(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            with patch('combat.time.monotonic',return_value=10):
                box.apply({'t':'equipment','armor':20,'toughness':8,'blocking':True})
                box.apply({'t':'signals','s':[[0,0,0,True]]})
            with patch('combat.time.monotonic',return_value=11):box.publish('c1m1_hotel')
            self.assertNotIn('equipment',box.path.read_text())
            self.assertNotIn('signal',box.path.read_text())

    def test_arrows_carry_minecraft_damage_and_legacy_rows_still_work(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            box.apply({'t':'proj','p':[[1,'arrow',2,90,-175,9],[2,'arrow',2,90,-175]]})
            box.publish('c1m1_hotel')
            self.assertIn('projectile 1 arrow 64 5600 2880 135.0',box.path.read_text())
            self.assertIn('projectile 2 arrow 64 5600 2880 60.0',box.path.read_text())
            with self.assertRaises(ValueError):box.apply({'t':'proj','p':[[1,'arrow',0,0,0,float('nan')]]})

    def test_navigation_request_is_data_only_and_expires(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'effects')
            with patch('combat.time.monotonic',return_value=10):
                box.apply({'t':'nav','id':7,'q':9,'from':[2,90,-175],'goal':[2,85,-174],'w':1.4,'h':2.7})
                box.publish('c1m1_hotel')
            self.assertIn('nav 7 9 64 5600 2880 64 5568 2720 44.8 86.4',box.path.read_text())
            with patch('combat.time.monotonic',return_value=12):box.publish('c1m1_hotel')
            self.assertNotIn('nav 7',box.path.read_text())
            with self.assertRaises(ValueError):box.apply({'t':'nav','id':True,'q':1,'from':[0,0,0],'goal':[0,0,0],'w':1,'h':2})

class EnvironmentalTests(unittest.TestCase):
    def test_totem_result_arrives_without_enabling_dead_player_controls(self):
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'totem')
            box.apply({'t':'interact'});box.apply({'t':'melee','d':10,'r':3})
            box.apply({'t':'totemresult','key':'totem_7_2_900','consumed':True})
            box.apply({'t':'replyack','id':9});box.publish('c1m1_hotel',active=False,attack=True,use=True)
            text=box.path.read_text()
            self.assertIn('totemresult totem_7_2_900 1',text);self.assertIn('replyack 9',text)
            self.assertNotIn('interact',text);self.assertNotIn('melee',text)
            for value in ['true',1,None]:
                with self.assertRaises(ValueError):box.apply({'t':'totemresult','key':'totem_7_2_900','consumed':value})

    def test_fire_snapshot_is_atomic_bounded_and_expires(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as d:
            box=GameplayMailbox(Path(d)/'fire')
            with patch('combat.time.monotonic',return_value=10):
                box.apply({'t':'fire','p':[[2,3.04,-5]]});box.publish('c1m1_hotel')
                self.assertIn('fire 64 160 97.28',box.path.read_text())
                for bad in [[[True,0,0]],[[0,0,float('nan')]],[[0,0,0]]*33]:
                    with self.assertRaises(ValueError):box.apply({'t':'fire','p':bad})
                self.assertEqual(box.fires,[(64,160,97.28)])
            with patch('combat.time.monotonic',return_value=11):
                box.publish('c1m1_hotel');self.assertNotIn('\nfire ',box.path.read_text())
                box.apply({'t':'fire','p':[[2,3.04,-5]]});box.publish('c1m2_streets')
                self.assertNotIn('\nfire ',box.path.read_text())

    def test_effects_expire_and_clear_at_map_change(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'mailbox';box=GameplayMailbox(p)
            with patch('combat.time.monotonic',return_value=10):
                box.apply({'t':'effects','speed':1.2,'burn':True});box.publish('c1m1_hotel')
                self.assertIn('effects 1.2 1',p.read_text())
            with patch('combat.time.monotonic',return_value=11):
                box.publish('c1m1_hotel');self.assertNotIn('effects',p.read_text())
                box.apply({'t':'effects','speed':1.2,'burn':True});box.publish('c1m2_streets')
                self.assertNotIn('effects',p.read_text())
            for speed in [float('nan'),-1,3]:
                with self.assertRaises(ValueError):box.apply({'t':'effects','speed':speed,'burn':True})

class FramedGameplayTests(unittest.TestCase):
    def test_heartbeat_has_round_epoch_and_complete_payload_marker(self):
        with tempfile.TemporaryDirectory() as d:
            b=GameplayMailbox(Path(d)/'mailbox');b.epoch=17;b.apply({'t':'heal','h':4});b.publish('c1m1_hotel')
            rows=b.path.read_text().splitlines();header=rows[0].split()
            self.assertEqual(len(header),9);self.assertEqual(header[8],'17')
            self.assertEqual(rows[-1].split(),['end',header[3],str(len(rows)-2)])
