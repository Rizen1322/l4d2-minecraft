import sys
import struct
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from private_hud_assets import decode_vtf,extract


class TeamHudTests(unittest.TestCase):
    def test_vtf_preserves_transparent_pixels_and_selects_full_size_mip(self):
        header=bytearray(80)
        struct.pack_into('<4sIIIHHIHH',header,0,b'VTF\0',7,2,80,2,2,0,1,0)
        struct.pack_into('<IBI',header,52,0,2,0xffffffff)
        pixels=bytes([255,0,0,255,0,255,0,128,0,0,255,0,0,0,0,255])
        image=decode_vtf(bytes(header)+bytes([255,255,255,255])+pixels)
        self.assertEqual(image.size,(2,2))
        self.assertEqual(image.getpixel((1,0)),(0,255,0,128))
        self.assertEqual(image.getpixel((0,1)),(0,0,255,0))
        with self.assertRaises(ValueError):decode_vtf(bytes(header)+pixels[:3])

    def test_embedded_vpk_preload_and_payload_are_joined(self):
        tree=b'vtf\0materials/vgui\0portrait\0'+struct.pack('<IHHIIH',0,3,0x7fff,0,4,0xffff)+b'pre'+b'\0\0\0'
        data=struct.pack('<III',0x55aa1234,1,len(tree))+tree+b'data'
        key='materials/vgui/portrait.vtf'
        with tempfile.TemporaryDirectory() as directory:
            archive=Path(directory)/'pak01_dir.vpk';archive.write_bytes(data)
            self.assertEqual(extract(archive,{key})[key],b'predata')

    def test_world_shader_has_no_hud_rectangular_restoration(self):
        shader=(Path(__file__).with_name('shaders')/'L4D2Minecraft.fx').read_text()
        self.assertNotIn('nativeTeamHud(',shader)
        self.assertIn('overlay.rgb + saturate(color) * (1.0 - overlay.a)',shader)


if __name__=='__main__':unittest.main()
