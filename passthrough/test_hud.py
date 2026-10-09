import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import hud_layout


class TeamHudTests(unittest.TestCase):
    def test_cards_scale_with_height_and_do_not_cut_the_hotbar_or_other_shield_pixels(self):
        for width, height in ((1280,720),(1920,1080),(2560,1440),(3440,1440)):
            scale=height/480
            for slot in range(3):
                y=(480-hud_layout.BOTTOM+(3-slot)*hud_layout.STRIDE+20)*scale
                self.assertTrue(hud_layout.covered(20*scale,y,width,height,3))
                self.assertFalse(hud_layout.covered(120*scale,y,width,height,3))
                self.assertFalse(hud_layout.covered(20*scale,y,width,height,3,gui=True))
                self.assertFalse(hud_layout.covered(20*scale,y,width,height,0))
            self.assertFalse(hud_layout.covered(width/2,height-30,width,height,3))
            self.assertFalse(hud_layout.covered(10*scale,280*scale,width,height,3))

    def test_single_teammate_does_not_reserve_empty_slots(self):
        self.assertTrue(hud_layout.covered(20,450,854,480,1))
        self.assertFalse(hud_layout.covered(20,350,854,480,1))

    def test_installed_shader_geometry_matches_hud_builder(self):
        path=Path(__file__).with_name('shaders')/'TeamHud.fxh'
        self.assertEqual(path.read_text(),hud_layout.shader_header())


if __name__=='__main__':unittest.main()
