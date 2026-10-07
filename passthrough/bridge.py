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

POSE_NAME = r"Local\L4D2MinecraftPose"
POSE_FORMAT = "<IIQdddffff"
POSE_SIZE = 128


class InputRelay:
    """Read only our hotkeys while the L4D2 window is foreground."""
    def __init__(self):
        self.down = {}
        self.gui_open = False
        self.enabled = False
        self.user = ctypes.windll.user32
        self.user.GetForegroundWindow.restype = ctypes.c_void_p

    def messages(self):
        window = self.user.GetForegroundWindow()
        title = ctypes.create_unicode_buffer(512)
        self.user.GetWindowTextW(ctypes.c_void_p(window), title, len(title))
        focused = self.enabled and title.value.startswith("Left 4 Dead 2")
        commands = {0x56: ("use",), 0x42: ("attack",), 0x4E: ("scroll",), 0x78: ("inventory",)}
        if self.gui_open:
            commands[0x1B] = ('escape',)
        result = []
        for key, (action,) in commands.items():
            down = focused and bool(self.user.GetAsyncKeyState(key) & 0x8000)
            previous = self.down.get(key, False)
            if down != previous:
                if action == "scroll":
                    if down:
                        result.append({"t":"scroll", "d":-1})
                else:
                    result.append({"t":"key", "k":action, "down":down})
            self.down[key] = down
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
                result.append({'t':'pointer','x':point.x/rect.right,'y':point.y/rect.bottom,'drag':drag})
        for key, button in [(1,0),(2,1)]:
            down = self.gui_open and focused and bool(self.user.GetAsyncKeyState(key)&0x8000)
            if down != self.down.get(key,False):
                result.append({'t':'mouse','b':button,'down':down})
            self.down[key] = down
        return result


class CollisionSnapshot:
    """Bounded, data-only reverse channel. Never emits executable Squirrel."""
    def __init__(self, path):
        self.path, self.cells, self.sequence, self.map = path, set(), 0, None

    def apply(self, message):
        if message.get('t') != 'blocks':
            return
        cells = set(self.cells)
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
        # Only 128 nearest cells may become host props in this prototype.
        rows = sorted(self.cells, key=lambda c: sum((c[i]+0.5-centre[i])**2 for i in range(3)))[:128] if active else []
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

    def fresh(self):
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
        return now-self.changed < 0.5

    def close(self):
        if self.view:
            self.kernel.UnmapViewOfFile(self.view)
        if self.handle:
            self.kernel.CloseHandle(self.handle)


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
            "fov": vfov, "fp": True, "h": -yaw - 90, "gun": False}


class PoseMemory:
    def __init__(self):
        self.memory = mmap.mmap(-1, POSE_SIZE, tagname=POSE_NAME)
        self.sequence = 0
        ctypes.windll.kernel32.GetTickCount64.restype = ctypes.c_ulonglong

    def publish(self, pose):
        self.sequence += 2
        # Odd/even sequence prevents a reader from accepting a partial write.
        struct.pack_into("<I", self.memory, 4, self.sequence - 1)
        milliseconds = ctypes.windll.kernel32.GetTickCount64()
        packet = struct.pack(POSE_FORMAT, 0x50434D4C, self.sequence - 1, milliseconds,
                             *pose["p"], *pose["r"], pose["fov"])
        self.memory[:len(packet)] = packet
        struct.pack_into("<I", self.memory, 4, self.sequence)


class HostInput:
    def __init__(self, game):
        self.exe = game / 'left4dead2.exe'
        self.disabled = False

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
        subprocess.Popen([str(self.exe), '-hijack', '+cl_mouseenable', '0' if open else '1'],
                         creationflags=subprocess.CREATE_NO_WINDOW,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.disabled = open


async def transmit(args):
    memory = PoseMemory()
    inputs = InputRelay()
    host_input = HostInput(args.game)
    frames = FrameHeartbeat()
    try:
        await connected_loop(args, memory, inputs, host_input, frames)
    finally:
        host_input.set_gui(False)
        memory.memory.close()
        frames.close()


async def connected_loop(args, memory, inputs, host_input, frames):
    import websockets
    sample_path = args.game / "left4dead2/ems/l4d2mc_pose.txt"
    collision = CollisionSnapshot(sample_path.with_name('l4d2mc_collision.txt'))
    last_content = None
    last_change = 0.0
    last_frame = None
    while True:
        try:
            async with websockets.connect("ws://127.0.0.1:25601", max_size=1024*1024) as socket:
                print("Minecraft guest connected", flush=True)
                collision.cells.clear()
                await socket.send(json.dumps({'t':'attach'}))
                # Resume the guest if its pause menu was left open; reconnects begin in play mode.
                await socket.send(json.dumps({'t':'key','k':'escape','down':True}))
                await socket.send(json.dumps({"t": "view", "w": args.width, "h": args.height}))
                last_frame = None
                last_collision = 0.0
                last_ground = None
                sync_after = None
                synced = False
                sync_id = time.monotonic_ns()
                next_sync = 0.0
                while True:
                    host_fresh = False
                    try:
                        content = sample_path.read_text(encoding="utf-8")
                        if content != last_content:
                            last_content, last_change = content, time.monotonic()
                        sample = json.loads(content.rstrip("\x00\r\n "))
                        # Stop publishing when L4D2 closes or no survivor exists.
                        if time.monotonic() - last_change < 0.5 and time.time() - sample_path.stat().st_mtime < 0.5:
                            host_fresh = True
                            pose = camera(sample, args.width / args.height)
                            identity = (sample["map"], sample["f"])
                            if identity != last_frame:
                                memory.publish(pose)
                                await socket.send(json.dumps(pose))
                                if sync_after is None:
                                    sync_after = time.monotonic() + 0.3
                                last_frame = identity
                                if time.monotonic() - last_collision > 0.25:
                                    collision.publish(sample['map'], pose['p'], active=frames.fresh())
                                    last_collision = time.monotonic()
                                if not synced and sync_after is not None and frames.fresh() and time.monotonic() >= max(sync_after,next_sync):
                                    await socket.send(json.dumps({'t':'blocksync','r':16,'id':sync_id}))
                                    next_sync = time.monotonic()+2
                                ground = (math.floor(pose['pl'][0]), math.floor(pose['pl'][2]), math.floor(float(sample['ground'])/32)-1)
                                if ground != last_ground:
                                    await socket.send(json.dumps({'t':'ground','c':[ground[0],ground[1],ground[2],ground[2]]}))
                                    last_ground = ground
                    except (OSError, ValueError, KeyError, TypeError):
                        pass  # VScript file can be observed during its write.
                    inputs.enabled = host_fresh and frames.fresh()
                    gui_enabled = inputs.gui_open and inputs.enabled
                    struct.pack_into('<I',memory.memory,64,int(gui_enabled))
                    host_input.set_gui(gui_enabled)
                    for command in inputs.messages():
                        await socket.send(json.dumps(command))
                    # Drain server notices without starving the sender.
                    try:
                        reply = await asyncio.wait_for(socket.recv(), timeout=0.005)
                        try:
                            event = json.loads(reply)
                            collision.apply(event)
                            if event.get('t') == 'syncdone' and event.get('id') == sync_id:
                                synced = True
                            if event.get('t') == 'ui':
                                inputs.gui_open = bool(event.get('open'))
                        except (ValueError, TypeError):
                            pass
                        args.events.parent.mkdir(parents=True, exist_ok=True)
                        with args.events.open("a", encoding="utf-8") as output:
                            output.write(reply + "\n")
                    except asyncio.TimeoutError:
                        pass
                    await asyncio.sleep(0.01)
        except (OSError, websockets.exceptions.ConnectionClosed) as error:
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
    arguments = parser.parse_args()
    if not 320 <= arguments.width <= 3840 or not 240 <= arguments.height <= 2160:
        parser.error("unsupported guest dimensions")
    try:
        asyncio.run(transmit(arguments))
    except KeyboardInterrupt:
        pass
