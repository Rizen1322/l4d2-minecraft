"""Local VScript -> Minecraft WebSocket + ReShade camera shared memory.

Source is authoritative. This bridge never sends movement into L4D2.
Run only with a separate guest world. Camera eye data is approximate: Source
view effects and third-person/spectator cameras need a native camera adapter.
"""
import argparse
import asyncio
import ctypes
import json
import math
import mmap
from pathlib import Path
import struct
import subprocess
import time
import re
from combat import GameplayMailbox

POSE_NAME = r"Local\L4D2MinecraftPose"
POSE_FORMAT = "<IIQdddffff"
POSE_SIZE = 128

MINECRAFT_KEYS = {1:'attack', 2:'use', 4:'pick', 0x45:'inventory',
                  0x51:'drop', 0x46:'swap', 0x74:'perspective',
                  0x54:'chat', 0xBF:'command', 0x78:'inventory',
                  **{0x31+i:f'slot{i}' for i in range(9)}}
GUI_SCAN = {**{0x41+i:(4+i,97+i) for i in range(26)},
            **{0x31+i:(30+i,49+i) for i in range(9)},0x30:(39,48),
            0x0D:(40,13),0x08:(42,8),0x09:(43,9),0x20:(44,32),
            0x10:(225,1073742049),0x11:(224,1073742048),0x12:(226,1073742050),
            0x25:(80,1073741904),0x26:(82,1073741906),0x27:(79,1073741903),0x28:(81,1073741905),
            0x2E:(76,127),0x24:(74,1073741898),0x23:(77,1073741901),
            0xBD:(45,45),0xBB:(46,61),0xDB:(47,91),0xDD:(48,93),
            0xDC:(49,92),0xBA:(51,59),0xDE:(52,39),0xC0:(53,96),
            0xBC:(54,44),0xBE:(55,46),0xBF:(56,47)}


def relay_keys(pressed, state, *, focused, gui):
    """Edge/hold semantics: world actions are released on focus or GUI changes."""
    result = []
    for key, action in MINECRAFT_KEYS.items():
        down = focused and key in pressed
        # E reaches the screen as guikey. Keep its physical latch when that
        # screen closes, so the same held press cannot reopen it in world mode.
        if gui and key==0x45:
            before=state.get(key,False)
            if before and not down:result.append({'t':'key','k':'inventory','down':False})
            state[key]=down
            continue
        if gui and not (key==0x78):
            down = False
        before = state.get(key,False)
        if down != before:
            if action.startswith('slot'):
                if down: result.append({'t':'slot','n':int(action[4:])})
            elif action in ('perspective','chat','command'):
                if down: result.append({'t':'key','k':action,'down':True})
            else:
                result.append({'t':'key','k':action,'down':down})
        state[key] = down
    return result


MOVEMENT_ACTIONS=('forward','back','moveleft','moveright','jump','duck','speed')
def parse_movement_bindings(text):
    names={'SPACE':0x20,'SHIFT':0x10,'CTRL':0x11,'ALT':0x12,'UPARROW':0x26,'DOWNARROW':0x28,'LEFTARROW':0x25,'RIGHTARROW':0x27}
    result={}
    for key,commands in re.findall(r'^bind\s+"([^"\r\n]+)"\s+"([^"\r\n]*)"',text,re.M|re.I):
        key=key.upper();vk=ord(key) if len(key)==1 and key.isascii() else names.get(key)
        if vk is None:continue
        for command in commands.split(';'):
            command=command.strip().lower()
            if command.startswith('+') and command[1:] in MOVEMENT_ACTIONS:
                result[vk]=result.get(vk,0)|(1<<MOVEMENT_ACTIONS.index(command[1:]))
    return result

def movement_mask(pressed,bindings):
    mask=0
    for key,bits in bindings.items():
        if key in pressed:mask|=bits
    return mask

class RewardOutbox:
    def __init__(self,path):self.path=path
    def read(self):
        try:content=self.path.read_text(encoding='ascii').rstrip('\x00\r\n ')
        except (OSError,UnicodeError):return []
        if len(content)>8192:return []
        result=[]
        for line in content.splitlines()[:32]:
            fields=line.split()
            if len(fields)!=4:continue
            key,map_name,finale,difficulty=fields
            if not re.fullmatch(r'[A-Za-z0-9_]{1,128}',key) or not re.fullmatch(r'[A-Za-z0-9_]{1,96}',map_name) or finale not in ('0','1') or difficulty not in ('0','1','2'):continue
            result.append({'t':'chapterreward','key':key,'map':map_name,'finale':finale=='1','difficulty':int(difficulty)})
        return result

class PickupOutbox:
    ITEMS={'golden_apple','cookie','speed_potion','flint_and_steel','tnt','slowness_potion','wooden_sword',
           'stone_sword','iron_sword','diamond_sword','netherite_sword','bow','crossbow','totem_of_undying'}
    def __init__(self,path):self.path=path
    def read(self):
        try:content=self.path.read_text(encoding='ascii').rstrip('\x00\r\n ')
        except (OSError,UnicodeError):return []
        if len(content)>16384:return []
        result=[]
        for line in content.splitlines()[:64]:
            f=line.split()
            if len(f)==2 and re.fullmatch(r'pickup_[A-Za-z0-9_]{1,112}',f[0]) and f[1] in self.ITEMS:
                result.append({'t':'pickup','key':f[0],'item':f[1]})
        return result

class SourceSnapshot:
    """Retain a validated pose through a partial StringToFile write, never indefinitely."""
    def __init__(self,path):self.path=path;self.sample=None;self.identity=None;self.changed=-1e30
    def read(self):
        now=time.monotonic()
        try:
            sample=json.loads(self.path.read_text(encoding='utf-8').rstrip('\x00\r\n '))
            camera(sample,1.0)
            if not isinstance(sample['map'],str) or not re.fullmatch(r'[A-Za-z0-9_]+',sample['map']):raise ValueError('invalid map')
            if time.time()-self.path.stat().st_mtime>1:return None
            identity=(sample['map'],sample['f'])
            if identity!=self.identity:self.identity=identity;self.changed=now
            self.sample=sample
        except (OSError,ValueError,KeyError,TypeError):pass
        return self.sample if now-self.changed<1 else None

class InputRelay:
    """Read only our hotkeys while the L4D2 window is foreground."""
    def __init__(self,movement_cfg=None):
        self.movement_bindings=parse_movement_bindings(movement_cfg.read_text(encoding='utf-8-sig',errors='replace')) if movement_cfg else {}
        self.focused=False
        self.down = {}
        self.world_down = {}
        self.gui_down={};self.was_gui=False;self.repeat_at={}
        self.gui_open = False
        self.enabled = False
        self.user = ctypes.windll.user32
        self.user.GetForegroundWindow.restype = ctypes.c_void_p

    def messages(self):
        window = self.user.GetForegroundWindow()
        title = ctypes.create_unicode_buffer(512)
        self.user.GetWindowTextW(ctypes.c_void_p(window), title, len(title))
        focused = self.enabled and title.value.startswith("Left 4 Dead 2")
        self.focused=focused
        pressed = {key for key in MINECRAFT_KEYS if self.user.GetAsyncKeyState(key)&0x8000}
        result = relay_keys(pressed,self.world_down,focused=focused,gui=self.gui_open)
        modifiers=(1 if self.user.GetAsyncKeyState(0x10)&0x8000 else 0)|(64 if self.user.GetAsyncKeyState(0x11)&0x8000 else 0)|(256 if self.user.GetAsyncKeyState(0x12)&0x8000 else 0)
        for command in result:
            if command.get('t')=='key':command['mods']=modifiers
        if self.gui_open and focused:
            held={k for k in GUI_SCAN if self.user.GetAsyncKeyState(k)&0x8000}
            if not self.was_gui:self.gui_down={k:k in held for k in GUI_SCAN}
            for vk,(scan,code) in GUI_SCAN.items():
                down=vk in held;before=self.gui_down.get(vk,False);now=time.monotonic()
                repeated=down and before and vk not in (0x10,0x11,0x12) and now>=self.repeat_at.get(vk,float('inf'))
                if down!=before or repeated:
                    result.append({'t':'guikey','scan':scan,'code':code,'mods':modifiers,'down':down})
                    if down:
                        self.repeat_at[vk]=now+(0.05 if repeated else 0.4)
                        # Translate only foreground in-game GUI typing, using its
                        # keyboard layout. No keys typed into other apps are relayed.
                        state=(ctypes.c_ubyte*256)()
                        for k in range(256):state[k]=0x80 if self.user.GetAsyncKeyState(k)&0x8000 else 0
                        state[0x14]|=self.user.GetKeyState(0x14)&1
                        text=ctypes.create_unicode_buffer(8)
                        self.user.GetKeyboardLayout.restype=ctypes.c_void_p
                        thread=self.user.GetWindowThreadProcessId(ctypes.c_void_p(window),None)
                        layout=self.user.GetKeyboardLayout(thread)
                        count=self.user.ToUnicodeEx(vk,self.user.MapVirtualKeyW(vk,0),state,text,8,4,ctypes.c_void_p(layout))
                        if count>0 and not(modifiers&64):
                            printable=''.join(c for c in text.value[:count] if ord(c)>=32)
                            if printable:result.append({'t':'text','s':printable})
                self.gui_down[vk]=down
        else:
            self.gui_down.clear();self.repeat_at.clear()
        self.was_gui=self.gui_open and focused
        if self.gui_open and focused:
            class Point(ctypes.Structure):
                _fields_ = [('x',ctypes.c_long),('y',ctypes.c_long)]
            class Rect(ctypes.Structure):
                _fields_ = [('left',ctypes.c_long),('top',ctypes.c_long),('right',ctypes.c_long),('bottom',ctypes.c_long)]
            point, rect = Point(), Rect()
            self.user.GetCursorPos(ctypes.byref(point))
            self.user.ScreenToClient(ctypes.c_void_p(window),ctypes.byref(point))
            self.user.GetClientRect(ctypes.c_void_p(window),ctypes.byref(rect))
            if rect.right > 0 and rect.bottom > 0:
                drag = next((button for key,button in [(1,0),(2,1)] if self.down.get(key)), -1)
                result.append({'t':'pointer','x':point.x/rect.right,'y':point.y/rect.bottom,'drag':drag,'mods':modifiers})
        for key, button in [(1,0),(2,1)]:
            down = self.gui_open and focused and bool(self.user.GetAsyncKeyState(key)&0x8000)
            if down != self.down.get(key,False):
                result.append({'t':'mouse','b':button,'down':down,'mods':modifiers})
            self.down[key] = down
        return result

    def movement(self):
        return movement_mask({key for key in self.movement_bindings if self.focused and self.user.GetAsyncKeyState(key)&0x8000},self.movement_bindings)


class CollisionSnapshot:
    """Bounded, data-only reverse channel. Never emits executable Squirrel."""
    def __init__(self, path):
        self.path, self.cells, self.sequence, self.map = path, set(), 0, None

    def apply(self, message):
        if message.get('t') != 'blocks':
            return
        cells = set(self.cells)
        bounds = message.get('bounds')
        if bounds is not None:
            if len(bounds)!=6 or not all(type(x) is int and abs(x)<=1023 for x in bounds) or any(bounds[i]>bounds[i+3] for i in range(3)):
                raise ValueError('invalid snapshot bounds')
            cells={c for c in cells if not all(bounds[i]<=c[i]<=bounds[i+3] for i in range(3))}
        for field, add in [('clear', False), ('set', True)]:
            values = message.get(field, [])
            if len(values) % 3 or len(values) > 30000:
                raise ValueError('invalid block snapshot')
            for i in range(0, len(values), 3):
                cell = tuple(values[i:i+3])
                if not all(type(x) is int and abs(x) <= 1023 for x in cell):
                    raise ValueError('invalid block cell')
                if add:
                    cells.add(cell)
                else:
                    cells.discard(cell)
        if len(cells) > 10000:
            raise ValueError('collision cache limit exceeded')
        self.cells = cells

    def publish(self, map_name, centre, active=True):
        if not map_name or not all(c.isalnum() or c == '_' for c in map_name):
            raise ValueError('invalid map name')
        if self.map is not None and self.map != map_name:
            self.cells.clear()
        self.map = map_name
        # Bound host props independently of the cache; Source also checks its free edicts.
        rows = sorted(self.cells, key=lambda c: sum((c[i]+0.5-centre[i])**2 for i in range(3)))[:512] if active else []
        self.sequence += 1
        data = [f'{self.sequence} {map_name}'] + ['%d %d %d' % c for c in rows]
        self.path.write_text('\n'.join(data), encoding='ascii')


class FrameHeartbeat:
    """Open existing frame memory read-only; never create a fake guest mapping."""
    def __init__(self):
        self.kernel = ctypes.windll.kernel32
        self.kernel.OpenFileMappingW.argtypes = [ctypes.c_ulong,ctypes.c_int,ctypes.c_wchar_p]
        self.kernel.OpenFileMappingW.restype = ctypes.c_void_p
        self.kernel.MapViewOfFile.argtypes = [ctypes.c_void_p,ctypes.c_ulong,ctypes.c_ulong,ctypes.c_ulong,ctypes.c_size_t]
        self.kernel.MapViewOfFile.restype = ctypes.c_void_p
        self.kernel.UnmapViewOfFile.argtypes = [ctypes.c_void_p]
        self.kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        self.handle, self.view = None, None
        self.counter, self.changed = None, -100.0
        self.next_open = 0.0

    def fresh(self,max_age=0.5):
        now = time.monotonic()
        if not self.view and now >= self.next_open:
            self.next_open = now + 1
            self.handle = self.kernel.OpenFileMappingW(4,False,r'Local\L4D2MinecraftFrame')
            if self.handle:
                self.view = self.kernel.MapViewOfFile(self.handle,4,0,0,4096)
                if not self.view:
                    self.kernel.CloseHandle(self.handle)
                    self.handle = None
        if not self.view:
            return False
        header = ctypes.string_at(self.view,48)
        magic, version = struct.unpack_from('<II',header)
        counter = struct.unpack_from('<q',header,32)[0]
        slot = struct.unpack_from('<i',header,40)[0]
        if magic != 0x5450434D or version != 1 or counter < 1 or slot not in (0,1,2):
            return False
        if counter != self.counter:
            self.counter, self.changed = counter, now
        return now-self.changed < max_age

    def close(self):
        if self.view:
            self.kernel.UnmapViewOfFile(self.view)
        if self.handle:
            self.kernel.CloseHandle(self.handle)


class RenderPose(FrameHeartbeat):
    def menu_open(self):
        if not self.view:
            self.read()
        if not self.view:return False
        self.kernel.GetTickCount64.restype=ctypes.c_ulonglong
        data=ctypes.string_at(self.view,128)
        stamp=struct.unpack_from('<Q',data,72)[0]
        return 0<=self.kernel.GetTickCount64()-stamp<2000 and bool(struct.unpack_from('<I',data,80)[0])

    def read(self):
        if not self.view:
            self.handle=self.kernel.OpenFileMappingW(4,False,r'Local\L4D2MinecraftRenderPose')
            if self.handle:
                self.view=self.kernel.MapViewOfFile(self.handle,4,0,0,128)
        if not self.view:
            return None
        data=ctypes.string_at(self.view,128)
        magic,seq,stamp,x,y,z,yaw,pitch,roll,fov=struct.unpack_from(POSE_FORMAT,data)
        after=ctypes.c_uint32.from_address(self.view+4).value
        self.kernel.GetTickCount64.restype=ctypes.c_ulonglong
        if magic!=0x50434D4C or seq&1 or after!=seq or not 0<=self.kernel.GetTickCount64()-stamp<100:
            return None
        result={'p':[x,y,z],'r':[yaw,pitch,roll],'fov':fov,'render_sequence':seq}
        if struct.unpack_from('<I',data,116)[0]==0x424f4459:
            result['pl']=list(struct.unpack_from('<ddd',data,88));result['h']=struct.unpack_from('<f',data,112)[0]
        return result


def render_camera(pose, actual, previous=None):
    """Accept the player view, never Source's distant auxiliary render camera.

    Eight Minecraft units allow local view bob and the usual third-person
    offset. VScript's eye position stays authoritative across real teleports.
    Keep the last measured FOV on rejection so calibration does not flicker.
    """
    result = dict(pose)
    if actual and all(math.isfinite(v) for v in actual['p']) and math.dist(actual['p'], pose['p']) <= 8:
        result.update({k:v for k,v in actual.items() if k not in ('pl','h')})
        if 'pl' in actual and all(math.isfinite(v) for v in actual['pl']) and math.dist(actual['pl'],pose['pl'])<=8 and math.isfinite(actual.get('h',0)):
            result['pl']=actual['pl'];result['h']=actual.get('h',pose['h'])
    elif previous:
        result['fov'] = previous['fov']
    return result


def position(source):
    if len(source) != 3 or not all(math.isfinite(float(x)) for x in source):
        raise ValueError("invalid Source position")
    x, y, z = map(float, source)
    return [x / 32.0, z / 32.0, -y / 32.0]


def camera(sample, aspect):
    if sample.get("v") != 1 or aspect <= 0:
        raise ValueError("unsupported camera sample")
    yaw, pitch, roll = map(float, sample["r"])
    hfov = float(sample["hfov"])
    if not all(math.isfinite(x) for x in [yaw, pitch, roll, hfov]) or not 10 < hfov < 170:
        raise ValueError("invalid camera angles")
    # Source's fov is horizontal at the reference 4:3 aspect, expanded for widescreen.
    # The vertical fov thus uses 4:3, rather than current aspect.
    vfov = math.degrees(2 * math.atan(math.tan(math.radians(hfov) / 2) / (4 / 3)))
    return {"t": "cam", "f": int(sample["f"]), "p": position(sample["p"]),
            "pl": position(sample["feet"]), "r": [-yaw - 90, pitch, -roll],
            "fov": vfov, "fp": True, "h": -yaw - 90, "look":[-yaw-90,pitch], "gun": False, "nativeuse":bool(sample.get("nativeuse",False)),"visible":bool(sample.get("visible",True)),"usable":bool(sample.get("usable",False)),"carrying":bool(sample.get("carrying",False)),"burning":bool(sample.get("burning",False)),"sneak":bool(sample.get("buttons",0)&4)}


def surface(sample):
    """Virtual support from Source geometry; never place invisible Minecraft blocks."""
    if sample.get('hit') is None:
        return None
    hit = position(sample['hit'])
    normal = position(sample['normal'])
    axis = max(range(3), key=lambda i: abs(normal[i]))
    if abs(normal[axis]) < 0.01:
        return None
    sign = 1 if normal[axis] > 0 else -1
    cell = [math.floor(v) for v in hit]
    # Source traces stop 1/32 unit before a brush. Snap a nearly integral
    # boundary before selecting the air cell on the outside of the surface.
    v = hit[axis]
    if abs(v - round(v)) < 1/64:
        v = round(v)
    # A Source floor/wall need not coincide with the voxel grid. Choose the
    # nearest floor cell to avoid a full-block hover on rough terrain. Walls
    # and ceilings still select a whole cell outside the brush.
    cell[axis] = math.floor(v + .5) if axis == 1 and sign > 0 else (math.ceil(v) if sign > 0 else math.floor(v) - 1)
    return {'pos': hit, 'cell': cell, 'face': axis * 2 + (1 if sign > 0 else 0)}


class PoseMemory:
    def __init__(self):
        self.memory = mmap.mmap(-1, POSE_SIZE, tagname=POSE_NAME)
        self.sequence = 0
        ctypes.windll.kernel32.GetTickCount64.restype = ctypes.c_ulonglong

    def input(self,gui,enabled,movement):
        struct.pack_into('<I',self.memory,80,movement)
        struct.pack_into('<Q',self.memory,72,ctypes.windll.kernel32.GetTickCount64() if enabled else 0)
        struct.pack_into('<I',self.memory,64,int(gui))

    def publish(self, pose):
        self.sequence += 2
        # Odd/even sequence prevents a reader from accepting a partial write.
        struct.pack_into("<I", self.memory, 4, self.sequence - 1)
        milliseconds = ctypes.windll.kernel32.GetTickCount64()
        packet = struct.pack(POSE_FORMAT, 0x50434D4C, self.sequence - 1, milliseconds,
                             *pose["p"], *pose["r"], pose["fov"])
        self.memory[:len(packet)] = packet
        struct.pack_into("<I", self.memory, 84, int(pose.get("visible",True)))
        struct.pack_into("<I", self.memory, 4, self.sequence)


class HostInput:
    def __init__(self, game, play_cfg='', restore_cfg=''):
        self.exe = game / 'left4dead2.exe'
        self.disabled = False
        self.perspective = 0
        self.play_cfg,self.restore_cfg=play_cfg,restore_cfg
        self.controls_enabled=False
        self.next_controls_send=0.0

    def _window(self):
        user=ctypes.windll.user32
        user.FindWindowW.restype=ctypes.c_void_p
        window=user.FindWindowW('Valve001',None)
        title=ctypes.create_unicode_buffer(512)
        user.GetWindowTextW(ctypes.c_void_p(window),title,len(title))
        return window if title.value.startswith('Left 4 Dead 2') else None

    def _engine_ready(self):
        reader=FrameHeartbeat()
        try:
            reader.handle=reader.kernel.OpenFileMappingW(4,False,r'Local\L4D2MinecraftRenderPose')
            if not reader.handle:return True
            reader.view=reader.kernel.MapViewOfFile(reader.handle,4,0,0,128)
            if not reader.view:return True
            data=ctypes.string_at(reader.view,128)
            stamp=struct.unpack_from('<Q',data,72)[0]
            if not stamp:return True # Compatibility with the older adapter.
            reader.kernel.GetTickCount64.restype=ctypes.c_ulonglong
            now=reader.kernel.GetTickCount64()
            return 0<=now-stamp<2000 and bool(struct.unpack_from('<I',data,64)[0])
        finally:reader.close()

    def _send(self,arguments):
        # -hijack starts a new game if the old one has already gone away.
        # Cleanup must never relaunch it. Keep even a race fallback insecure.
        if not self._window() or not self._engine_ready():return False
        subprocess.Popen([str(self.exe),'-insecure','-hijack',*arguments],
            creationflags=subprocess.CREATE_NO_WINDOW,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        return True

    def set_gui(self, open):
        if self.disabled == open:
            return
        user = ctypes.windll.user32
        user.FindWindowW.restype = ctypes.c_void_p
        window = user.FindWindowW('Valve001', None)
        title = ctypes.create_unicode_buffer(512)
        user.GetWindowTextW(ctypes.c_void_p(window), title, len(title))
        if not title.value.startswith('Left 4 Dead 2'):
            self.disabled = False
            return
        # Native cursor ownership is synchronous. Never queue delayed mouse-disable
        # commands that can arrive after the screen has already closed.
        # VGUI mouse ownership is synchronous; executable command interface ABI
        # is deliberately not called from the render thread.

        self.disabled = open

    def cycle_perspective(self):
        self.perspective=(self.perspective+1)%3
        commands=['firstperson'] if self.perspective==0 else ['thirdperson',
            'cam_idealdist 96','cam_ideallag 0','cam_idealpitch 0','cam_idealyaw '+('180' if self.perspective==2 else '0')]
        self._send([part for command in commands for part in ('+'+command.split()[0],*command.split()[1:])])

    def controls(self,active):
        if active==self.controls_enabled or time.monotonic()<self.next_controls_send:return
        cfg=self.play_cfg if active else self.restore_cfg
        if cfg:
            if not re.fullmatch(r'[a-zA-Z0-9_]+',cfg):raise ValueError('invalid control cfg')
            if not self._send(['+exec',cfg]):
                self.next_controls_send=time.monotonic()+0.5
                return
        self.controls_enabled=active
        if not active:self.perspective=0


async def transmit(args):
    memory = PoseMemory()
    inputs = InputRelay(args.game/"left4dead2/cfg/config.cfg")
    host_input = HostInput(args.game,args.play_cfg,args.restore_cfg)
    frames = FrameHeartbeat()
    render = RenderPose()
    try:
        await connected_loop(args, memory, inputs, host_input, frames, render)
    finally:
        host_input.set_gui(False)
        host_input.controls(False)
        memory.memory.close()
        frames.close()
        render.close()


async def connected_loop(args, memory, inputs, host_input, frames, render):
    import websockets
    sample_path = args.game / "left4dead2/ems/l4d2mc_pose.txt"
    collision = CollisionSnapshot(sample_path.with_name('l4d2mc_collision.txt'))
    gameplay = GameplayMailbox(sample_path.with_name('l4d2mc_gameplay.txt'))
    source=SourceSnapshot(sample_path)
    rewards=RewardOutbox(sample_path.with_name('l4d2mc_rewards.txt'))
    pickups=PickupOutbox(sample_path.with_name('l4d2mc_pickups.txt'))
    last_frame = None
    while True:
        try:
            async with websockets.connect("ws://127.0.0.1:25601", max_size=1024*1024) as socket:
                print("Minecraft guest connected", flush=True)
                collision.cells.clear()
                await socket.send(json.dumps({'t':'attach'}))
                await socket.send(json.dumps({'t':'clear'}))
                # Resume the guest if its pause menu was left open; reconnects begin in play mode.
                # Do not send Escape during world startup: it cancels Minecraft's loading screen.
                await socket.send(json.dumps({"t": "view", "w": args.width, "h": args.height}))
                last_frame = None
                last_collision = 0.0
                last_ground = None
                sync_after = None
                synced = False
                sync_id = time.monotonic_ns()
                next_sync = 0.0
                last_render = None
                last_wheel = None
                last_gameplay = 0.0
                last_rewards=0.0
                guest_map = None
                map_ready = False
                last_world_request = 0.0
                last_reply_frame = None
                was_host_menu = False
                while True:
                    host_fresh = False
                    try:
                        sample=source.read()
                        if sample is not None:
                            host_fresh = True
                            session=(sample['map'],sample.get('epoch',0))
                            if guest_map != session:
                                guest_map=session;map_ready=False
                                collision.cells.clear()
                                gameplay.events.clear();gameplay.mobs.clear();gameplay.physics.clear();gameplay.projectiles.clear()
                                gameplay.navigation.clear();gameplay.equipment=None;gameplay.signals=[];gameplay.protection=None
                                last_frame=None;last_render=None
                                last_world_request=0.0
                            if time.monotonic()-last_world_request>1.0:
                                await socket.send(json.dumps({'t':'world','map':guest_map[0],'epoch':guest_map[1]}))
                                last_world_request=time.monotonic()
                            pose = camera(sample, args.width / args.height)
                            actual=render.read()
                            pose = render_camera(pose, actual, last_render)
                            if 'render_sequence' in pose:
                                last_render = pose
                            pose['visible']=bool(sample.get('visible',True)) and map_ready
                            pose['fp'] = host_input.perspective==0 and not sample.get('pinned',False)
                            identity = (sample["map"], sample.get("epoch",0), map_ready, sample["f"], pose.get('render_sequence'))
                            if identity != last_frame:
                                memory.publish(pose)
                                await socket.send(json.dumps(pose))
                                if sync_after is None:
                                    sync_after = time.monotonic() + 0.3
                                last_frame = identity
                                if time.monotonic() - last_collision > 0.25:
                                    collision.publish(sample['map'], pose['p'], active=map_ready and frames.fresh(3.0))
                                    last_collision = time.monotonic()
                                if sync_after is not None and frames.fresh() and time.monotonic() >= max(sync_after,next_sync):
                                    await socket.send(json.dumps({'t':'blocksync','r':16,'id':sync_id}))
                                    next_sync = time.monotonic()+2
                                pose_surface = surface(sample)
                                await socket.send(json.dumps({'t':'surface','hit':pose_surface}))
                                if 'health' in sample:
                                    await socket.send(json.dumps({'t':'hosthealth','h':sample['health']}))
                                if 'actors' in sample:
                                    await socket.send(json.dumps({'t':'peds','p':sample['actors']}))
                                if sample.get('physground'):
                                    await socket.send(json.dumps({'t':'physground','p':sample['physground']}))
                                if sample['f']!=last_reply_frame:
                                    for reply in sample.get('replies',[])[:64]:
                                        await socket.send(json.dumps(reply))
                                        if 'rid' in reply and reply.get('t')!='pickup':gameplay.apply({'t':'replyack','id':reply['rid']})
                                    last_reply_frame=sample['f']
                                if 'wheel' in sample:
                                    wheel=sample['wheel']
                                    if last_wheel is not None and wheel!=last_wheel:
                                        await socket.send(json.dumps({'t':'scroll','d':wheel-last_wheel}))
                                    last_wheel=wheel
                    except (OSError, ValueError, KeyError, TypeError):
                        pass  # VScript file can be observed during its write.
                    if time.monotonic()-last_rewards>1.0:
                        for reward in rewards.read()+pickups.read():await socket.send(json.dumps(reward))
                        last_rewards=time.monotonic()
                    host_menu=render.menu_open()
                    if host_menu and not was_host_menu:
                        await socket.send(json.dumps({'t':'key','k':'escape','down':True}))
                        inputs.gui_open=False
                    was_host_menu=host_menu
                    inputs.enabled = not host_menu and map_ready and host_fresh and bool(sample.get("visible",True)) and frames.fresh(3.0)
                    host_input.controls(inputs.enabled)
                    gui_enabled = inputs.gui_open and inputs.enabled
                    host_input.set_gui(gui_enabled)
                    commands=inputs.messages()
                    memory.input(gui_enabled,inputs.enabled,inputs.movement())
                    for command in commands:
                        if command.get('k')=='perspective':host_input.cycle_perspective()
                        else:await socket.send(json.dumps(command))
                    if collision.map and time.monotonic()-last_gameplay>0.05:
                        gameplay.publish(collision.map,active=inputs.enabled,gui=gui_enabled,
                            sprint=inputs.enabled and not gui_enabled and bool(inputs.user.GetAsyncKeyState(0x11)&0x8000),
                            attack=inputs.world_down.get(1,False),use=inputs.world_down.get(2,False))
                        last_gameplay=time.monotonic()
                    # Drain server notices without starving the sender.
                    try:
                        reply = await asyncio.wait_for(socket.recv(), timeout=0.001)
                        try:
                            event = json.loads(reply)
                            collision.apply(event)
                            gameplay.apply(event)
                            if event.get('t') == 'syncdone' and event.get('id') == sync_id:
                                synced = True
                            if event.get('t') == 'mapready' and guest_map is not None and event.get('map')==guest_map[0] and event.get('epoch',0)==guest_map[1]:
                                map_ready=bool(event.get('ready'))
                            if event.get('t') == 'ui':
                                inputs.gui_open = bool(event.get('open')) and not host_menu
                        except (ValueError, TypeError):
                            pass
                        args.events.parent.mkdir(parents=True, exist_ok=True)
                        with args.events.open("a", encoding="utf-8") as output:
                            output.write(reply + "\n")
                    except asyncio.TimeoutError:
                        pass
                    # The old 5ms receive wait + 10ms sleep capped camera delivery
                    # below the guest's 120 FPS. Poll at ~250Hz without busy-waiting.
                    await asyncio.sleep(0.003)
        except (OSError, websockets.exceptions.ConnectionClosed) as error:
            if isinstance(error,websockets.exceptions.ConnectionClosed) and error.rcvd and error.rcvd.code==1008:
                raise RuntimeError('Minecraft is already owned by another bridge; stop the older launcher') from error
            host_input.set_gui(False)
            collision.cells.clear()
            if collision.map:
                collision.publish(collision.map,[0,0,0])
            print("Waiting for Minecraft guest:", type(error).__name__, flush=True)
            await asyncio.sleep(2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--game", type=Path, default=Path(r"E:\SteamLibrary\steamapps\common\Left 4 Dead 2"))
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--events", type=Path, default=Path(__file__).parent / "events.jsonl")
    parser.add_argument('--play-cfg',default='')
    parser.add_argument('--restore-cfg',default='')
    arguments = parser.parse_args()
    if not 320 <= arguments.width <= 3840 or not 240 <= arguments.height <= 2160:
        parser.error("unsupported guest dimensions")
    lock=None
    try:
        kernel=ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.CreateMutexW.restype=ctypes.c_void_p
        lock=kernel.CreateMutexW(None,True,r'Local\L4D2MinecraftBridge')
        if not lock:raise OSError('cannot acquire bridge lock')
        if ctypes.get_last_error()==183:
            kernel.CloseHandle(ctypes.c_void_p(lock));lock=None
            raise SystemExit('Another Minecraft bridge is already running. Close its launcher first.')
        asyncio.run(transmit(arguments))
    except KeyboardInterrupt:
        pass
    finally:
        if lock:kernel.CloseHandle(ctypes.c_void_p(lock))
