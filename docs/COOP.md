# Experimental LAN co-op

Every player runs their own Steam L4D2 and Minecraft Java26.3 profile on a separate
Windows PC. One L4D2 listen server controls the map, infected, movement, damage,
pickups and chapter transitions. This is not a Minecraft dedicated server.

The room shares block states, collision proxies and Steve poses/equipment. Each
player keeps their own private Minecraft inventory. Actor commands and receipts
are routed by Source **userid**, never by the first survivor in an entity list.
Sourcewalking, jumping and Escape remain native for every player.

## Host

1. Install/build the same mod version on all PCs. Launch Minecraft normally.
2. Run `python passthrough/configure_coop.py host` once from the project directory.
   This creates ignored `l4d2mc.coop.json`, with a fresh private room token.
3. Start `Launch-L4D2MC-2K.bat`. This starts the insecure local listen server and
   the room on TCP25602. Give your teammate the LAN IP and token privately.
4. The room resolves their exact L4D2 display name to the current Source userid.
   Display names must be unique among connected human survivors.

## Teammate

1. Run `python passthrough/configure_coop.py join --server 192.168.1.20 --player "Your L4D2 name"`.
   Enter the host token at the hidden prompt. Use your L4D2 name, which may differ
   from your Minecraft name. The room waits until this survivor joins Source.
2. Launch your Minecraft profile normally, then `Launch-L4D2MC-2K.bat`. It uses
   `+connect` instead of loading its own map. A reconnect resolves the new userid
   automatically. Advanced configs can use `--userid`, but that must be updated
   whenever Source assigns a new number (`status` shows userid, not entity index).

If Windows asks about network access, allow the room only on your private LAN.
No firewall rules are installed automatically. The host needs L4D2's normal LAN
port and TCP25602 reachable by the teammate. Do not forward these ports publicly:
the room token authenticates access, but this LAN protocol has no TLS encryption.
Never upload the local config or include its token in a screenshot or repository.
Use `python passthrough/configure_coop.py off` to return to a solo local launch.

## Current limits and verification

- Up to four Source survivors; one local game pair per Windows session/PC.
- All peers need the same Minecraft version and block registry. Foreign mods that
  change registry state IDs are unsupported. Max20000 edited cells per scene,
  including deletion history; Source colliders remain limited to512 nearest cells.
- Block **states** are shared. Chest inventories, block-entity NBT and a full
  Minecraft multiplayer server are not shared. Local mobs remain authoritative
  in their spawning guest; remote views are visual copies. Remote melee hits
  are authenticated by the room and applied by the Minecraft server that owns
  the mob, with distance, scene and duplicate-hit checks. Remote projectile
  and splash damage against these copies is not implemented yet.
- Same-scene reconnect includes deletion tombstones, and old-frame packets stop
  controls after1s. Map change/restart selects a new private scene for all peers.
- Offline tests use real local WebSocket connections, separate actors and actual
  Source handlers. A full two-PC gameplay/latency test remains required.

Network updates must be applied on both PCs. Close Minecraft and the launcher,
extract the update into the existing project directory, and run `Update-Coop.cmd`.
It rebuilds and tests the guest, checks the Source scripts, and updates owned
files without launching games or changing the room invitation/player settings.
Blocks and remote melee use bounded acknowledged queues; snapshots replace old
snapshots. Network participant leases are separate from the frozen-Source
watchdog, and retained block edits include deletion tombstones across reconnects.
The first projectile report retains its launch position so mailbox coalescing
cannot skip a nearby Source wall/floor impact.
