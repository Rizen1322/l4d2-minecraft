import unittest
import math
import struct
import json
import os
import tempfile
from pathlib import Path
from unittest.mock import patch
from bridge import SourceSnapshot
from performance import guest_view

class PerformanceTests(unittest.TestCase):
    def test_source_cache_avoids_reparsing_but_never_renews_frozen_pose(self):
        with tempfile.TemporaryDirectory() as folder:
            file=Path(folder)/'pose.txt';sample={'v':1,'map':'c1m1_hotel','f':6,'p':[0,0,96],'feet':[0,0,32],'r':[0,0,0],'hfov':90}
            file.write_text(json.dumps(sample));reader=SourceSnapshot(file)
            with patch('bridge.time.monotonic',return_value=0):self.assertEqual(reader.read()['f'],6)
            with patch.object(Path,'read_text',side_effect=AssertionError('Unchanged JSON reparsed')):
                with patch('bridge.time.monotonic',return_value=.05):self.assertEqual(reader.read()['f'],6)
            with patch('bridge.time.monotonic',return_value=1.01):self.assertIsNone(reader.read())
            self.assertEqual(reader.changed,0)
    def test_source_cache_forced_read_covers_coarse_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            file=Path(folder)/'pose.txt';sample={'v':1,'map':'c1m1_hotel','f':6,'p':[0,0,96],'feet':[0,0,32],'r':[0,0,0],'hfov':90}
            file.write_text(json.dumps(sample));info=file.stat();reader=SourceSnapshot(file)
            with patch('bridge.time.monotonic',return_value=0):self.assertEqual(reader.read()['f'],6)
            sample['f']=7;file.write_text(json.dumps(sample));os.utime(file,ns=(info.st_atime_ns,info.st_mtime_ns))
            with patch('bridge.time.monotonic',return_value=.05):self.assertEqual(reader.read()['f'],6)
            with patch('bridge.time.monotonic',return_value=.11):self.assertEqual(reader.read()['f'],7)
    def test_quality_preserves_existing_resolution_and_uncapped_fps(self):
        self.assertEqual(guest_view(2560,1440),{'t':'view','w':2560,'h':1440,'fps':260,'lowfx':False})
    def test_guest_only_profiles_reduce_transfer_and_keep_aspect(self):
        for profile,dimensions,fps in [('balanced',(1920,1080),90),('low',(1280,720),60)]:
            view=guest_view(2560,1440,profile)
            self.assertEqual((view['w'],view['h']),dimensions)
            self.assertEqual(view['w']/view['h'],2560/1440)
            self.assertEqual(view['fps'],fps)
            self.assertEqual(view['lowfx'],profile=='low')
        self.assertEqual(guest_view(1920,1080,'low')['h'],540)
    def test_small_and_ultrawide_outputs_respect_minimum_size(self):
        for w,h in [(320,240),(3840,240),(321,241),(3440,1440)]:
            result=guest_view(w,h,'low')
            self.assertGreaterEqual(result['w'],320);self.assertGreaterEqual(result['h'],240)
            self.assertLessEqual(result['w'],w);self.assertLessEqual(result['h'],h)
            self.assertLess(abs(result['w']/result['h']-w/h),.01)
    def test_invalid_dimensions_rejected(self):
        for dims in [(319,720),(1280,239),(True,720),(4096,2160)]:
            with self.assertRaises(ValueError):guest_view(*dims)
    def test_shader_march_numeric_reference_keeps_coverage_and_bounds(self):
        # Float32 reference for the shader's replacement geometric schedule.
        # It must retain all 24 samples and the exact near/far endpoints.
        f32=lambda value:struct.unpack('f',struct.pack('f',value))[0]
        near=f32(.2)
        for far in [.5,.51,1,2,10,100,400]:
            far=f32(far);factor=f32(math.pow(f32(far/near),f32(1/23)))
            current=near;values=[]
            for i in range(24):
                z=far if i==23 else current;values.append(z)
                old=near*math.pow(far/near,i/23)
                self.assertLess(abs(z-old)/old,5e-6)
                current=f32(current*factor)
            self.assertEqual(values[0],near);self.assertEqual(values[-1],far)
            self.assertTrue(all(a<b for a,b in zip(values,values[1:])))
