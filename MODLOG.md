# MODLOG — L4D2 × Minecraft

## 2026-10-07 — исследование

- Запрос: Minecraft внутри L4D2. Уточнение пользователя: «Ломать и строить блоки в L4D2, с его зомби и оружием».
- Прочитаны навыки universal-modder: mod-any-game, mashup-mods, game-recon, game-research-websearch, share-field-notes; playbooks Source и Minecraft.
- Поиск KB начат с локального `knowledge/INDEX.md` и публичного индекса. Прямого готового решения Minecraft-песочницы в L4D2 не найдено в просмотренных материалах. Есть заметки Portalcraft, Minecraft/GTA V и L4D-мобы в Minecraft; они решают другие задачи.
- `um` не на PATH. Использован установленный пакет без установки: `python -m um scan <game path> --json`, cwd — папка плагина. Результат: Source 1, x86 native, 59144 проиндексированных файла, сканирование не усечено.
- Сканер отметил ASI loader, но не указал файл/активность: это автоматическая эвристика, не подтверждённое состояние. Отсутствие anti-cheat в отчёте не означает отсутствие VAC.
- L4D2 найден в Steam: AppID 550, build 23990068. Полные пути и доказательства в MODDING_PLAN.md.
- В server.dll обнаружены имена ключевых VScript API. Поиск строк не заменяет runtime-тест.
- Read-only исследованы gameinfo, addonlist, Workshop-папка, папки инструментов и стандартный каталог Minecraft. 49 Workshop VPK; SourceMod/Metamod и основные Authoring Tools не обнаружены.
- Попытка прочесть scripts/vscripts из VPK сначала встретила не-UTF-8 имя; после tolerant decode дерево разобрано, но `.nut` в указанном префиксе не найдено. Скрипты из VPK не использованы как доказательство; формат остальных скриптов не исследован. Файлы не извлекались.
- VDC-страницы вернули ошибку доступа. Резерв: первичный код VSLib, официальный Source SDK и локальные файлы.
- Выбран рекомендуемый путь: собственная VScript-мутация с небольшим блоковым полем. Настоящий Minecraft-процесс и рендер-композитор не нужны для уточнённого запроса.
- Подготовлен MODDING_PLAN.md: варианты, проверяемый первый прототип, ограничения, лаборатория, источники.
- Не выполнялось: установка, запуск игры, изменение bindings/config/registry/saves, скачивание loaders, публикация. Скриншотов нет, потому что игровой тест не запускался. Backup ещё не нужен: изменений игровых файлов не было.

## Поисковые запросы

- Left 4 Dead 2 Minecraft building blocks SourceMod
- site:github.com left4dead2 minecraft blocks
- site:steamcommunity.com/sharedfiles Minecraft VScript Left 4 Dead 2
- Left 4 Dead 2 Fort Spawn plugin
- L4D2 VScript StringToFile TraceLine
- L4D2 GetButtonMask VScript
- site:github.com VSLib Entity L4D2
- site:developer.valvesoftware.com Left 4 Dead 2 SpawnEntityFromTable

## Следующий этап и критерий завершения

После согласования первого прототипа: дизайн/план; технический тест одного твердого объекта. Успех подтверждать логом, просмотренным изображением и взаимодействием в настоящем L4D2. Изучение выполнено; создание и проверка мода остаются впереди.

## 2026-10-07 — согласование объёма

- Пользователь одобрил предложенный первый прототип: «Давай пока так да, потом уже будем всё дорабатывать».
- Подготовлен письменный дизайн `docs/superpowers/specs/2026-10-07-l4d2-block-sandbox-design.md`: компоненты, команды, сетка, формат сохранения, ограничения, тесты и восстановление.
- Выполнен обзор дизайна: отделены временный prop и конечный куб; уточнены ограничения навигации, загрузка без стирания существующих построек, проверка файлов без исполнения кода и неопределённость бюджета entities.
- Рабочая папка до этого не была Git-репозиторием. История проекта создаётся только в `l4d2-minecraft` для сохранения исследовательских документов и дизайна.
- Письменный дизайн пока не одобрен; product code не создавался и игра не изменялась.

## 2026-10-07 — код черновика и смена цели

- Пользователь явно отменил планирование: «делай, без плана. сразу код». После этого созданы VScript core/runtime, mode, оригинальные куб/текстуры, сборщик, установщик и незавершённый launcher.
- Пользователь разрешил установку официальных Authoring Tools Steam 563 и автоматические локальные игровые тесты. Установлены tools buildid 14602762.
- Резервные копии до запуска: `C:\Users\Rizen\.universal-modder\backups\l4d2mc-cfg\20261007-195528.zip`, `...\l4d2mc-steam-profile\20261007-195528.zip`; addonlist отдельно в `backups/addonlist-original.txt` (um backup работает с папками, не одиночными файлами). Установщик также сохраняет cfg/addonlist в `backups/<timestamp>`.
- Тест core сначала дал ожидаемый CORE FAIL («block core is not implemented»), после реализации — CORE PASS в настоящем L4D2. Проверены отрицательная сетка, границы, парсинг сохранений/дубликатов/лимита, ray-box.
- Официальный studiomdl успешно собрал cube.mdl/vvd/dx90.vtx/phy, физический объём 32768.00 in³. Устранена ошибка декодирования stdout компилятора (Windows ACP vs UTF-8); исходная компиляция была успешной.
- VPK собран официальным vpk.exe и установлен как `left4dead2/addons/l4d2mc_blocks.vpk`. Флаг addonContent_Mutation добавлен по первичному примеру автора другого режима.
- Свежий запуск с `+map` загружал coop; запуск `map c1m1_hotel mcblocks` через exec CFG действительно загрузил ScriptMode mcblocks. Надёжный launcher этого черновика пока не подтверждён; оставлен draft.
- С активными Workshop-модами обнаружен отказ model consistency по models/infected/hunter.mdl; для локальных тестов временно отключены другие аддоны. Снимок отказа просмотрен.
- Интеграционный тест упал на ray collision. Диагностика установила причину теста: длинная трасса начиналась внутри геометрии карты (startsolid), поэтому не выбирала куб. Короткая трасса ±17 попала в проп и грань x=447.96875 при ожидаемой448; физическая форма реальна. Дальнейшие тесты сохранения/стояния/орды не выполнялись до смены цели.
- Источник картины API: TraceHull отсутствует, Director.GetMapName доступен, NetProps bbox используются вместо отсутствующих GetBoundingMins/Maxs.
- Пользователь уточнил конечную цель: настоящий Minecraft, связанный с картами и движком L4D2, по образцу Minecraft в Portal 2. VScript-песочница больше не считается конечным решением.
- Запрос пользователя: исследовать Portalcraft. Найдены точный Portal 2 repo Griffdog21/Portalcraft и релиз v1.1.0, прочитаны metadata JAR, shader и launcher, без установки/исполнения. Открытых C++/Java исходников в main нет. Отдельно прочитан MIT-код GongerNonger/portalcraft для Portal 1, не путать проекты.
- Пользователь указал Minecraft gameDir Legacy Launcher. Последний подтверждённый профиль OptiFine1.20.1/Java17, тогда как Portalcraft использует26.3/Fabric/Java25. Аккаунтные данные не читались, игровой профиль не менялся.
- Составлено PASSTHROUGH_RESEARCH.md с источниками, интерфейсами L4D2 и первым проверяемым результатом реальной интеграции.
- Восстановлены исходные Workshop-флаги, собственный черновой VPK отключён, временные loose tests и test CFG убраны. Native hooks/ReShade и новые Minecraft-профили не устанавливались.


## 2026-10-07: настоящий guest passthrough

Создан passthrough/guest из MIT-примера universal-modder, отдельный Fabric
профиль L4D2MC-Fabric-26.3, оригинальный VScript-мост камеры/коллизий,
Python/WebSocket relay и x86 ReShade compositor. User разрешил оба loader и
временную проверку MSAA. Профиль запускается самим пользователем через Legacy
Launcher, авторизация остаётся у launcher; аккаунты/токены не читались.

Компиляция: Microsoft OpenJDK25.0.1 из существующего launcher; Zig0.15.2
официальный архив с подтверждённым SHA256; ReShade SDK tagv6.8.0. Загруженный
с официального www.reshade.me setup имеет ожидаемый signer thumbprint, но
Get-AuthenticodeSignature сообщил UnknownError (полная trust-проверка не
подтверждена). Нативные retail файлы не изменялись, добавлены собственные
loader/adapter/scripts/models с receipt.

Первый Zig -shared -static создал ar вместо PE: обнаружено PE-проверкой,
исправлено -shared без -static. Реальный MSVC/MinGW x86 ABI конфликт в
find_uniform_variable вызвал дампы; исправлено явным result pointer и
thiscall для API20 slot20. Последующие реальные запуски стабильны.

Игровые доказательства: evidence/passthrough-first-link.png (реальный HUD),
no-msaa.png (гостевой блок в карте), inventory-confirmed.png (мышь/хотбар).
Source TraceLine попал в коллизию реального MC блока face639.969 при
ожидаемом640. Полный тест глубины за стенами ещё не завершён. Отдельная
проба occlusion попала в prop_dynamic и не является доказательством wall
occlusion. В игре были временные тестовые постройки в отдельном guest world.

Проверки: guest Gradle build, native x86 PE/export validation, 10 Python
тестов. Code review выявил ownership, устаревшие коллизии/клавиши и recovery
backup; внесены соответствующие исправления. Не объявлять законченной total
conversion: пока только локальный c1m1_hotel, 128 кубических коллизий,
примерная VScript-камера, нет полного BSP/Steve-body/navmesh.


Дополнительная проверка коллизий: настоящий Source-сценарий с контролируемым
снимком создал 1 collider; после прекращения обновлений через 1.2s осталось0.
Это отдельный fixture-тест lease, не полная проверка отключения обоих игр.
Последнее обновление установлено после штатного закрытия игр; сохранён guest
world. Workshop-флаги совпали с launch backup побайтно. В последнем JAR
добавлены controller attach/release и syncdone ack; эти аварийные ветки
прошли сборку/ревью, отдельный игровой запуск после них ещё не выполнялся.


## 2026-10-08 — camera / Source support fixes

- Native read-only VEngineClient013 view/projection (L4D2 extra HideLoadingPlaque slot):
  WorldToScreenMatrix slot37, WorldToViewMatrix slot38. Reference:
  https://github.com/Lak3/l4d2-internal-base/blob/main/src/SDK/L4D2/Interfaces/EngineClient.h
- Real camera pose, FOV, near/far; observed Source near7/far~5000 and vfov104.82
  differed from previous approximate VScript FOV73.74/clip30000.
- Snapshot metadata before texture upload; removed late rejection that left
  new pixels with old pose. Reprojection validates its reconstructed hit in
  host screen coordinates to avoid duplicate blocks at depth discontinuities.
- Source aim trace produces virtual AIR-cell hit support for ordinary BlockItem;
  no new barriers. One-time per-chunk migration scoped to own guest overworld.
  Chunk callback uses chunk.setBlockState (level.setBlock deadlocked loading),
  backup guest-before-support-migration-20261008 excludes locked session.lock.
- Startup Escape could cancel world loading; removed and restricted screen
  closing to joined player.
- 13 Python tests + guest/native build pass. Source floor placement at two
  unoccupied positions and wall placement verified by exact block-change events.
  Placement intersecting player body correctly remains rejected.
- Camera fixtures: three views, one yellow component, projected bounds error
  <=2.07px (evidence/fix-camera-projection-check.json). 7.2s rapid-turn clip,
  72 sampled frames had one yellow component, no missing fixture; this alone
  did not exclude other blocks flickering (user reported remaining problem).
- Generic Depth automatic largest-vertices snapshot suspected to switch sky/map
  passes. Locked c1m1_hotel CLEAR2 via ReShade UI. Wall fixture invisible at
  pitches0/10/25/40, visible with occlusion bypass; evidence/fix-wall-depth-check.json.
  Generic Depth primary reference (BSD-3-Clause):
  https://github.com/crosire/reshade/blob/v6.8.0/examples/09-depth/generic_depth_addon.cpp
  Depth pass selection is map-specific pending broader testing.

- D3D9 streaming: dynamic shader-resource-only front/back textures, all three
  layers mapped WRITE_DISCARD then swapped together. COPY_DEST maps to
  RENDERTARGET in ReShade D3D9 and is incompatible with DYNAMIC; removed.
  Official primary references: crosire/reshade v6.8.0 source/d3d9/
  d3d9_impl_device.cpp and d3d9_impl_type_convert.cpp.
- True raw-color diagnostic ignores BOTH depth buffers. 896 raw frames had
  no disappearing yellow fixture; 896 no-warp/depth frames were also stable.
- Paired stationary test exposed whole-world disappearance frames94/95 with
  guest eye [252.284027,-28.657433,-401.207214] versus actual player eye
  [20.088867,90.961929,-181.631287], delta341.2286 MC units, unchanged angles.
  Cross-check native eye against VScript within8 MC units before forwarding;
  native and bridge retain measured calibration on rejected auxiliary views.
  Reject nonfinite extracted planes. Regression includes real teleport.
- User confirmed flicker stopped. Added visible-surface seeded inverse tracking
  for translated views, validated screen correspondence and nearest-hit search
  before tracked fallback. Final shader hotcompiled14:01:36 (13.125s).
  Controlled 20s motion clips preserve fixture; yellow-area statistics alone
  are affected by moving Source bots and cannot prove all-frame correctness.
  User confirmed whole blocks while walking and stable distant position, but
  reports residual smooth restoration on fast actions; no claim of zero latency.
- Non-integral Source support planes now select ceil(normal+) / floor-1(normal-)
  to keep a whole voxel outside brush. Existing builds preserved; potential
  sub-voxel gap documented. 18 Python tests pass. Camera poll ~4ms vs15ms.


## 2026-10-08 — Minecraft controls / avatar / combat integration (in progress)
User requests Steve, Minecraft held items instead of host guns, native Minecraft
bindings E/LMB/RMB/hotbar/wheel, TNT/creepers/mobs affecting host people/infected.
Keep existing real-Minecraft passthrough and Source authority for map/movement.
Use real Minecraft avatar in detached host camera, hide own Source survivor
render and viewmodel reversibly rather than converting a duplicate Steve mesh.
Reuse existing guest explosion/MobWar/projectile hooks; add bounded data-only
Source combat mailbox. No source assets or credentials need copying.
First slice: control press/hold/release/GUI routing + reversible host key config.
Checks: no Source shot from mouse1, E opens real inventory, 1–9 and wheel select,
F5 shows real Steve, sword damages Source infected, TNT blast damages host
entities and reacts to Source geometry; mob damage/proxies with cleanup leases.


### Corrections after user gameplay reports (2026-10-08)
- User explicitly requests original Source walking/jumping. Removed forced
  0.627927/0.96175 multipliers and Shift/Ctrl rebinding/relay; Steve crouch now
  follows Source IN_DUCK. Native Source mouse/look remain authoritative.
- Confirmed ED_Alloc root in console: thousands of unavailable
  DoEntFireByInstanceHandle errors after env_explosion spawn, before serial ack.
  Consume before effects; supported EntFire by unique name; queue Kill first;
  reserve entity budget; disable physics bone followers and preserve valid leases.
  Runtime probe: three duplicate events produced one blast, then zero remaining;
  own infected health500 removed by blast. No user entities were test targets.
- Source interact uses door Toggle/button Press (Use input is not universal).
  Runtime own-door probe usable=true, state0→state1(opening), automatic cleanup.
  Door consumes RMB before Minecraft places an item; Minecraft blocks/entities
  still take precedence. Locked-door behavior remains the engine's behavior.
- Floor activation normalizes LevelResource.ROOT (trailing '.' otherwise defeats
  private-world check). Shared immutable client snapshots prevent TNT prediction
  falling through server-only planes. Unknown physical support freezes server
  ticks; host-offline projectiles freeze too. Source masks only owned collision
  props while sampling floor/walls and restores solid flags even on error.
  Runtime old-cube overlap floor probe returned Y89.0244, flags6144 restored.
- GUI: VClient016 IN_DeactivateMouse alone did not stop recentering. Final code
  uses VGUI_Surface031 SetCursorAlwaysVisible, UnlockCursor, SetCursor plus
  one deactivation and focus-aware restoration; no detours or vtable writes.
  Cursor300,250 stayed unchanged12 samples/2.4s after Source focus settled.
  Official SDK semantics: ValveSoftware/source-sdk-2013 src/game/client/in_mouse.cpp;
  L4D2 interface layouts: Lak3/l4d2-internal-base src/SDK/L4D2/Interfaces.
  Minecraft26.3 mapped InputConstants confirmed SDL left1/right3; corrected
  mouse click AND drag values, replacing old GLFW0/1. New guest runtime pending.
- F5: camera only gets rendered yaw; Steve head gets raw Source look; ideal
  camera lag0; settings and binds restored by launcher. Added initial GUI snapshot
  on guest connection so an already-open inventory survives bridge reconnect.
- Forced flushed guest-world save through a temporary, own JDK Attach agent
  calling public server.saveEverything on server thread; result=true. Backed up
  whole private world before graceful WM_CLOSE. Restored flushed entity regions
  to preserve hostile user mobs removed by the old detach hook; new hook only
  discards tagged stand-ins. Backup location recorded privately in evidence.
- Java build and native x86 build succeed;27 Python tests pass. New JAR installed.
  Minecraft closed, normal Legacy launch requested; full new guest physics/input
  and F5 verification is still required. Do not call this a complete conversion.

2026-10-08 gameplay correction (verification in progress): removed unverified native engine command vtable calls after E crash; Windows Application event confirmed tier0.dll 0xc0000417. Five real guest inventory open/close cycles with safe adapter kept Source process alive. Fixed E physical-key latch to prevent immediate reopen after screen closes; corrected VGUI dc_none=1 from Valve Cursor.h, expires GUI lease even on incomplete pose writes. Added atomic authoritative block region snapshots, periodic reconciliation, nearest512 host collision budget and1400 total edict guard. Added Source actor factions and golem targeting of infected; goal-driven hostile Minecraft mobs target survivors. Source melee scale15 (diamond sword7 ->105 before cooldown). Python32 tests pass, native and Java builds pass; new Java/final cursor runtime verification requires normal guest relaunch.

2026-10-08 user requests cursor/pearls/chorus/map interactions/AI/other maps/loading UI; explicitly forbids launching games. Prepared code without starting games: source pteleport+chorus data events; pearl traces Source surfaces and discards guest pearl on acknowledged hit; Source destination floor+hull ray sampling because retail TraceHull is absent, resets velocity/fall speed. Chorus consume effect requests Source floor search.8-field gameplay header carries held mouse actions; Source m_afButtonForced gets IN_USE and IN_ATTACK only for carry/pour map items, original bits saved/restored; Java nativeuse suppresses duplicate door Toggle. Goal-driven proxy pursuits now move against transient Source collision planes, sidestep collisions; ranged attack and creeper swelling handled separately. Brain-driven hostiles remain a limitation. Loader accepts -Map and reattaches on transitions. New depth capture selects largest full-resolution world-camera pass (D3D9 shader-readable texture only, MSAA/surfaces retain GenericDepth fallback), explicit API20 x86 handle ABI slots10/13 checked by read-only review. Shader gains MC_HOST_DEPTH optional semantic. Loading/cutscene/externalfreeze flags gate Minecraft composition and relay. Cursor handling retains dc_none and pending focus activation; perworld Windows cursor hiding is reversible, no window subclass.34Python tests, Java/native builds and launcher parser pass. Source/Minecraft are closed; new gameplay/depth/cursor slice installed but explicitly NOT runtime-verified.

Final offline verification:35Python tests pass. Added native read-only render-ready status shared channel and launcher/HostInput command deferral during loading, test confirms no process launch while Source unready. Largest depth pass excludes non-screen-size buffers/shader-unreadable surfaces; cursor counter restoration retains outside-app cursor. Five installed files SHA256 match builds. No game launched after user prohibition.


2026-10-08 offline regression correction after user screenshots/reports:
- Removed experimental source_depth hooks from active compositor, restored FX
  byte-for-byte to verified camera baseline 2550c2a. Generic Depth remains;
  other maps have no runtime verification.
- Advertise nativeuse=false, restore explicit door/button interact, exclude
  those targets from forced Use to avoid duplicate Toggle.
- Remove Source mob collider creation; clean old owned numbered cube props
  at script attach. Guest mobs remain visible and combat-capable; Source player
  may pass through them. Building blocks retain their collision props.
- Wider/three-height wall probes and bounded terrain anchor. Read-only review
  found opposing startsolid probes could cage a partially embedded mob;
  reverse probes now select a nearest shallow escape direction. Deep ambiguous
  intersections withhold new support instead of publishing an unbounded path.
- User forbids opening games. Offline builds/tests/install only; runtime
  occlusion, door, mob escape and movement behavior are still pending.

Final regression checkpoint: Java/native build succeeded (x86 AddonInit verified),
35 Python tests passed, diff whitespace check passed. Final read-only review found
no further concrete errors in escape bounds, coordinate signs or owned-prop
cleanup. Five own installed files match their source/build SHA256. No games
launched or operated; live behavior is explicitly unverified.


2026-10-08 requested "improve everything", continued code-only/no game launches.
Prepared per-map NBT block+blockentity archives, bounded restore, 60-second/save/
transition/shutdown checkpoints. Retained early CHUNK_LOAD, captured container
NBT directly from CHUNK_UNLOAD, retry world handshake/latest requested map.
Reviewer found partial transition and archive-vs-vanilla-flush loss paths;
added durable transition/checkpoint markers, recovery and saveEverything(true,
true,true) before deleting markers. Own world backup made before installation.
Added opt-in /l4d2mc survival|creative, preserved Source movement/health authority;
food regenerates, golden apples give bounded temporary HP. Equipment lease feeds
armor/toughness/front shield reduction with wear; pre-damage chaining only when
scripted mode supports it, ordinary coop nonfatal compensation cannot prevent
incap/lethal blows. Generic game-event registration guarded for retail API.
Added golem follow/guard/attack commands + crouch RMB empty-hand follow.
Added proximity/LOS barricade pressure with hardness and Tank scaling, reset
per-map damage; rare infected supplies. Explicit redstone link + bounded signal
snapshot controls doors/buttons, transient links per session. Arrow payload
uses verified mapped AbstractArrow.baseDamage accessor+speed, Source scale15;
legacy projectile rows remain valid, critical multiplier approximate1.25.
No complete Source navmesh, all-enchantment effects, bed checkpoints or per-map
mob archive implemented. Official-script control reference read from
https://raw.githubusercontent.com/sw1ft747/l4d2-vscript-projects/master/prop_hunt/scripts/vscripts/scriptedmode.nut
(AllowTakeDamage contract, original source files not included in mod).
Java build and40 Python tests pass; native/shader unchanged from prior verified
build. All new runtime behavior remains unverified due no-launch instruction.

Final recovery review added durable footprint (previous archive + current cells
+ all touched AIR positions), retained in touched through repeated interrupted
recovery and cleared only after successful world flush. Projectile combat-only
branch braces fixed; no unconditional brush/pearl damage. World handshake is a
periodic heartbeat even when ready, so leaving/reentering the guest world can
recover without WebSocket reconnect. No runtime tests performed.

Offline world backup (all files SHA256 verified): E:\вин\ПРОЕКТЫ\main\l4d2-minecraft\backups\guest-before-survival-20261008-655b3a77
Four own files installed and verified. No games launched; loaders and graphics settings unchanged.

Final read-only review confirmed retained recovery tombstones through repeated interruptions; no further concrete errors in the targeted check. Runtime verification remains pending.


2026-10-08 world loading hang reported after survival update. Read-only jcmd
Thread.print on existing Minecraft PID4632 confirmed repeated Server thread
MapBuilds.chunk -> capture -> Level.getBlockEntity -> ServerChunkCache.getChunk
-> managedBlock -> Fabric CHUNK_LOAD -> MapBuilds.chunk. Log stuck loading49
spawn chunks/16%, no crash and no archive created. Root cause: global world
lookup inside CHUNK_LOAD before its future completes. Replaced per-cell world
capture with direct chunk.getBlockEntity, as already done for CHUNK_UNLOAD.
No game launched or terminated; no saves restored/deleted. New JAR build/tests
and runtime relaunch status recorded below.

World-load fix built successfully, 40 Python tests passed, diff check passed.
Updated guest JAR installed with matching SHA256. Read-only review confirmed
no world chunk lookup remains in CHUNK_LOAD callback. Existing Minecraft still
runs the old loaded classes; normal user restart is required, no restart/kill
was performed by agent. No archive existed during observed loading hang.


2026-10-08 23:52:18 server crash report: IllegalFormatConversionException
f != java.lang.Integer at SurvivalFeatures.tick:61. Latest log confirms prior
chunk lookup fix worked (spawn loading completed1493ms, player joined). Root:
getArmorValue/Math.clamp(int) passed Integer to %.2f formatter. Extracted pure
GuestMessages equipment serializer with %d for armor and bounded finite double
for toughness. Standalone JVM regression reproduced the exact exception before
fix, passes afterwards for armor0/20, out-of-range values, German default locale
and NaN toughness. verifyGuestMessages is required by Gradle check/build; no
Minecraft process started by test. Java build and40Python tests pass. Fixed JAR
installed and SHA256 matched. No saves modified/restored, no game launched;
next normal user launch remains required for in-game confirmation.

2026-10-09 F5/gameplay update, offline only: inventory/world/view weapon models
hidden per owner and restored on drop. Steve uses survivor yaw for front F5;
Hunter pin rotates body/armor/items prone. Teammate HUD Source card footprints
are restored over guest shield/hand, disabled in guest GUI, count at pose+96.
No world depth/reprojection changes. Actual vanilla guest FIRE now survives
validated transient native floors; contact snapshots ignite Source actors,
native entityflame or bounded fallback DOT, no native ground inferno. Totem
held in either hand is durably consumed before native incap/defib rescueHP100,
then animation35 after Source-applied receipt; inactive dead mailbox only
accepts rescue result/ack. Whole-team-wipe before handshake remains unverified.
Golems use fresh live targets, nearest48 host actors, ironcommon1hit/SI180,
direct jump before move, low vehicle probes. TNT shallow floor embedding
raises only body probe origin after confirmed floor, airborne fall preserved.
Checkpoint RMB uses native use (bar removal), explicit guest intent with
120ms pulse prevents lost taps and doors behind MC mob clicks. Full build:
63Python/11JVM/6Source suites+x86PE, nine owned installed files SHA-verified.
No games launched; FX runtime compilation/visual alignment not verified.
Final read-only review found aggregate receipt budget could abort player saves;
RewardLedger.stage now validates a copy before all chapter/pickup/totem costs
or grants. Mixed-family regression passes without modifying rejected state.
Guest package rebuilt with final vanilla DEATH_PROTECTION effects and installed
again; reviewer found no remaining concrete P1/P2 blockers in these code paths.


2026-10-09: Offline update requested without game launches. Added bounded
Source navmesh routes (12 jobs,64 neighbor checks/think, actual stair floor and
headroom, pending-target jitter retained) and height-sensitive Java cursor.
Esc stays native Source; VEngineVGui001 IsGameUIVisible gates compositor/input,
yields cursor to VGUI, and closes guest GUI without opening Minecraft pause.
Removed blanket ReShade input block. Added2560x1440 noborder BAT for measured
primary monitor. Shield directional stumble/airborne SI stagger, Smoker tongue
release, native DropFire with6 pool cap, Source hearts/absorption,8 non-solid
AI golem targets/contact damage, low-ledge jump and embedded-body recovery.
Diamond/netherite Source180/220 damage, normal infected single hit, .35 s cap.
Source epoch/round_start now requests fresh scene on maps/restarts; mobs cleared,
old chunk cells quarantined. Previous builds copied to immutable UUID snapshots
before reset; entity deletion follows durable save+journal (review findings
fixed). Source pin flags select Steve third person. Full Source animations and
runtime confirmation remain outstanding. Official Squirrel3.2 standalone parser
compiles own scripts only; no game executes. Source API calls still need runtime
confirmation. Build,44 Python,2 standalone JVM checks, launcher parse recorded.

Final review also fixed same-map reset crash recovery: transition journal now
references immutable source snapshot (safe filename, exists check); recovery
union includes bounded validated checkpoint tombstones even with transition.
Old two-line journals remain supported. Guest rebuilt and reinstalled after
this repair. Installed SHA256 matches JAR/native/all4VScripts. Diagnostic-only
collision_probe.nut is intentionally not installed. No games started.


2026-10-09 next update: armor enchantment profile via actual MC EnchantmentHelper,
source damage kinds/fall/fire/blast/projectile, Resistance/Fireproof heartbeat,
corrected gear wear5Source HP=1MC HP and creative no-wear. Heal mixin routes
instant-heal/regeneration to Source. Added chapter successful-transition/finale
outbox, bounded supplies/XP/10% equipped repair and inventory overflow reserve.
Read-only review caught cross-file payout transaction risk; moved receipt/reserve
into Player ValueInput/ValueOutput same atomic player.dat unit as items/XP/repair.
Read-only javap caught saveEverything bool only confirms chunks and swallowed
player save errors: ack now requires reading actual player.dat reward receipt.
Invalid custom reward data is preserved unchanged; more rewards fail closed.
World/profile/player saves not touched by agent, hooks run only private guest.
Latest MC log00:39-00:40 showed repeated host replaced, orphan1280x720 Python
bridge15092 still running after games exited. No new crash report found. Stopped
only verified orphan helper; no game processes touched. Added bridge namedmutex,
launcher legacy process guard+mutex, single WScontroller lock+generation,
nonowner message rejection, and idempotent native resize (no RestoreWindow,
duplicate SDLSetWindowSize/SyncWindow). Build47Python/4pureJVM/Squirrel arithmetic
and syntax/PSparse pass; runtime crash disappearance/Mixin behavior unverified.

2026-10-09 connection/HUD/use/fall-totem repair:
Transport was connected; ReShade failed to compile the previous HUD cutout loop.
Compile recovery confirmed by native log and user's visible picture. Replaced
rectangular native framebuffer restoration with guest GUI alpha teammate cards
above the full shield, Source member state export and eight privately extracted
portraits in ignored dist. Native team HUD disabled by own addon. No world-depth
or reprojection change. Checkpoint readback uses LevelResource.PLAYER_DATA_DIR
(players/data in26.3). Native use now sends real client +use/-use with own key32766,
release/hold/carry/GUI guards; no commands issued to running game during work.
Fall rescue resets native momentum/fall accumulator, validates final snapped
floor/hazard for every candidate, restores recent same-scene safe anchor, and
confirms after physics with one bounded retry. Mirrored guest FALL/void suppressed
only under fresh Source health authority. Review caught unsafe final floor snap;
regressions now reject vanished-platform hurt destinations and steep slopes.
Build passed63Python,12JVM programs,7actual Source suites and x86 PE verification.
Nine owned components installed and SHA verified. Games not opened or controlled;
new HUD, door and fall rescue remain runtime unverified, restart required.

2026-10-09 intermittent cursor repair: world cursor ownership no longer depends
on guest pose/input heartbeat. A same-process, window-thread WH_CALLWNDPROCRET
hook clears HTCLIENT WM_SETCURSOR after Source/window class processing; messages
are never swallowed. Source gameplay/menu and foreground rechecked on UI thread.
Inventory, Source/ReShade menus, border and stale presentation yield normally.
Removed render-thread world ShowCursor debt loop. Module pinned until process exit
to protect returning callbacks after Unhook; no hot unload support. Lazy Source
interface references and callback verifier atomic across UI/render threads.
Real Win32 hidden-window test installed hook from live second thread and confirmed
repeated arrow reset, GUI/menu/border/stale/unhook cases without showing or focusing
any window. Foreground accessor mocked only in test; actual game focus unverified.
Full build63Python/12JVM/7Source/native cursor test passed. No games controlled.
Installation attempted: only changed addon32 is locked by running L4D2. New
binary remains in dist; current process still has previous code. Existing
Launch-L4D2MC-2K.bat -> Launch-Minecraft.ps1 applies owned update before starting
next session, so replacement awaits normal user exit/relaunch. No game closed.

2026-10-09 source-alpha audit/preparation:
Three independent agents reviewed logic/render/transport, then independent review
checked integration/clean packaging. Fixed full-outbox totem confirmation loss,
unsent completed nav replies and old-round jobs; reconnect held-key latches,
render-rate duplicate state, bounded latest-server snapshots and stale queued
controller/scene inputs; world presses arriving behind inventory now suppressed.
Portable explicit/env/ignored-local/Steam paths, tool-param build, setup entrypoint
and x86ReShadeAPI preflight before writes. Review caught missing collision cube
in sourceZIP; procedural compiler source now shipped/generated on clean build,
all model/material components required before install. Lazy path resolution
preserves explicit CLI override even with broken local JSON. Root README replaced
obsolete controls with current requirements/known issues/credits/license.
Source-only deterministic allowlist ZIP excludes private HUD/JAR/loader/profiles,
adds embedded hashes, checksum, offline CI and bug template. No public upload yet.
Extracted freshZIP compiled owncube via officialstudiomdl into workspace staging,
guest/native/HUD and all tests:75Python,13JVM,7Source,Win32cursor,PSparse passed.
No games opened/controlled or saves changed; fullcleaninstall/runtime stillpending.
Nine owned components then updated and SHAverified, no locked files this attempt.

2026-10-09 second explicit agent audit:
Logic rebases pill buffer at its actual decayed amount when healing; golden apple
does not revive expired buffer and respects native maxHP. ViewSizePolicy acknowledges
actual resize, recovers later external changes/failed pending request after2s.
Transport evicts far collisioncache entries instead rejectingnewregion; guest
mob/projectile/physics snapshots expire after.75s tickstall; ReplyTracker separate
serverOwner cancels stoppedserverpending while retainingdelivered receipts.
Installer regressions reproduced partialearlyupdate on missing/conflictinglatefile
and corruptedtarget on interruptedcopy. Now fullpreflight, stagedhash/atomicreplace,
receipt atomicJSON, ordinaryIOrollback, checksum/existence recheck foruseredits,
durablependingjournal before replace and startuprecovery. Recovery preservesunexpected
externaltarget/receiptchanges. Testsisolatedtemporary receipts; no saves changed.
Aggregatebuild84Python,13JVM,7Source,Win32cursor passed; no games launched.

2026-10-10 continuation (Claude): reviewed uncommitted LAN co-op/Elytra/crouch/eating
work. Retail L4D2 console showed an earlier l4d2mc_coop.nut:151 compile error; the
current installed script equals the repo copy and the 19:05 session loaded without it.
Build under Python3.13 (websockets17) exposed a room-handler signature break:
websockets>=13 passes only the connection. Handler path is now optional; the test
checks closed state for both APIs. Launcher runtime still uses Python3.12/websockets10.4.
Full build passed: 106 Python, JVM, Source suites, x86 PE, cursor test. update.py
installed everything except L4D2Minecraft.addon32 (locked by running L4D2).
Bridge process from the 19:05 launch was no longer running. In-game test pending restart.
Retail VM still rejected l4d2mc_coop.nut ChapterReward (line151 col142, then line165):
"end of statement expected (; or lf)" at a statement that followed an if-body
(block, or if/else-if chain) on the same line. Split those lines; the installed
retail VM now compiles coop and flight via -hijack +exec script_execute (oracle).
Standalone sq3.2 does not catch this. Launchers started from the agent shell die
with the tool call (process tree kill), leaving an orphan bridge; start the .bat
via explorer.exe. 19:21 relaunch: fresh pose, bridge+launcher alive, no script errors.
F5 weapon: live diag showed the held weapon_pistol already had EF_NODRAW and
kRenderNone but stayed visible. The client draws an owner's active weapon in third
person regardless of both. Hiding now uses kRenderTransColor with m_clrRender alpha 0,
and restore puts back the saved mode and colour. Hot-reloaded into the running game:
weapon rm=1, clr=0x00FFFFFF. User visual confirmation pending. Co-op host cfg now sets
sv_allow_lobby_connect_only 0 for direct +connect. Added tools/pack_for_friend.ps1
and docs/FRIEND_GUIDE_RU.md; release/l4d2mc-friend.zip (93MB) checked: no tokens,
local config, JAR or VPK inside.
Alpha 0 alone did not hide the carried weapon in F5 (user screenshots). Carried weapons
now also get m_iWorldModelIndex 0, and the saved index comes back on drop/restore.
Per-frame sampling over 8 s showed stable hidden state (melee, wm=0, no resets).
Ledge hang exported visible=false (scripted view entity / frozen flags), so Steve
disappeared and hiding paused. The hang now counts like a pin for visibility. F5 now
sets c_thirdpersonshoulderoffset 0 (restored with the other controlled vars).
Third-person "Steve eaten by world on fast spin": the compositor reprojects one MC
depth layer, and orbit-camera translation exposes disocclusion. Not fixed yet.
Reverted m_iWorldModelIndex=0: the client re-deployed the weapon on every change (constant draw/holster sound, flashlight swinging). F5 weapon stays visible until a non-model approach is found. Manual script copies desynced the install receipt; synced hashes for files equal to repo source.
Axe lying next to Steve: the interact event (RMB use on a door with no block/entity target) called DropItem on a held weapon_melee as if it were a carry prop. The survivor was left with no weapons and the dropped axe stayed visible. Interact now drops only CarryItem props; the test now covers a gascan drop and keeping the melee.
Golem stall: l4d2mc_survival.nut aggro used e.IsBot(), which retail CTerrorPlayer lacks.
Every aggro tick threw once a special infected was in range. Now IsPlayerABot(e).
F5 front camera: Source clamps cam_idealyaw to c_minyaw/c_maxyaw (+-135), so the
requested 180 became -135 (side view). F5 now sets the limits to +-180, restored
on exit. Held melee (weapon_melee) still draws in third person despite EF_NODRAW
and alpha 0; testing survivor m_clrRender alpha 0 live. Shader: near (<4 m) guest
surfaces accept 6 px back-projection error instead of 1.5 px, so Steve's silhouette
survives orbit turns. Compiles at next ReShade start.
Link drop: PlayerSync.tick returned on a stale pose. With Elytra equipped flying was off, so Steve fell into the void and died repeatedly. Now he hovers at the last host position. Stuck respawn: hostHealth set positive health on a dead ServerPlayer, and the server ignores PERFORM_RESPAWN while health>0. Health sync now skips dead players and zeroes revived-dead health.
Perf pass (no content changes): native upload streams shared memory straight into the back textures and checks seq after the copy, instead of first copying the 44 MB snapshot. The red/blue swap moved from a per-pixel CPU loop to .bgra on the three colour reads in the effect, so uploads are plain memcpy. HidePlayerWeapons runs its full entity scan 4x/s instead of 30x/s and rechecks cached attachments between scans (a detached model is still restored on the next tick). Shader change is unverified until ReShade compiles it at launch.
Golem idle after first kill: in the default attack order a golem with no target had no destination. Attack now regroups with the player like follow. Survivor itself gets kRenderTransColor alpha 0 (HideSurvivor) so client-side melee/holster attachments disappear; restored with the hidden record. Shader: MotionBias*|WarpT| added to the depth allowance (blocks sank into the floor while walking); near tolerance lowered to 4 px. User reports repeated draw/holster again; a 5 s per-frame server sample showed no weapon/state/viewmodel changes (only movement buttons).
Deploy-sound spam confirmed gone after we stopped writing predicted_viewmodel render state, but the third-person pistol came back, so the pistol draws through the viewmodel. Viewmodel now gets render colour only (TransparentModel; no EF_NODRAW, the flag the client toggles while deploying). The restore path skips flag writes for these records. Golem: SourcePursuitGoal drops a target after 60 ticks without getting closer (wall, other floor, no route) and ignores it for 10 s; MobWar.targetFor respects that.
Front F5 diagnosis by sampling the native render camera: back view 3.00 m straight behind; front view 2.04 fwd / 2.04 side (135 deg). Cause: -hijack argv parsed '+c_minyaw -180' as a launch switch, so the -135 limit stayed. Perspective commands now go through an owned cfg (l4d2mc_view.cfg, +exec). Front view also inverts m_pitch, as Minecraft does; the launcher restores m_pitch and forces it positive. Tick profiling by stubbing stages: 4.5 ms average per think (warning every tick, 70 ms spikes). CoopExport rebuilt the whole host pose and wrote a second file even solo; it now runs only with a remote human survivor and reuses the cached host pose. GroundPhysics probe budget 6->3 bodies per think (~50 traces each). Result: 2.6 ms average. Golem: melee protectors ignore proxies more than 3 blocks above/below.
F5 front head: Source keeps the front camera pitch equal to the aim. The front view now inverts m_pitch and the guest mirrors Steve's head (pose 'front'), as Minecraft's front view does. Splash/lingering potions, snowballs and eggs fell through the floorless guest world. They are now reported as 'thrown', Source-traced without host damage, and broken in place via a Projectile.onHit invoker. Blocks breaking up while walking: screen bursts showed reprojection slivers and missing edges. PosePrediction slider and fps_max 120 changed nothing. Added CameraLead: the bridge leads only the guest's camera copy by velocity*35 ms (L4D2MC_CAMERA_LEAD, capped 1 unit, reset on teleport, never during elytra drive), so the compositor's leftover translation shrinks.
Regression: PlayerSync.hold ran whenever live() was null, including hidden/cutscene poses. It teleported Steve back and stopped fall flying mid-flight: the jumping, closed wings and doubled wind sound. It now holds only on a real link loss (no pose for 0.5 s), never while fall flying. The near tolerance, motion bias and camera lead did not fix walking artifacts and were set back to 0 by default. Steve tearing: the exporter wrote the host pose instead of the camera MC actually rendered from (the elytra chase cam differs). It now exports mainCamera().position() plus Steve's feet relative to the camera (desc 112..127). The compositor passes SteveCam/SteveUp in MC camera space; the effect takes pixels inside Steve's capsule unwarped and rejects translated Steve copies. Unverified until ReShade compiles it in game.
Method reset per universal-modder frame-compositing note (diagnostics first, hypothesis list). H1: the host pose leads the depth buffer by one frame. mat_queue_mode=-1 (auto, queued on multicore); the compositor reads VEngineClient WorldToViewMatrix at reshade_begin_effects while the main thread may already be on the next frame. Test: mat_queue_mode 0 live; walking/F5 artifacts should mostly vanish if H1 holds. Measured: MC 114-119 fps, readback 6.6 ms, bridge loop ~4 ms; uncapping MC fps and fps_max 120 did not change artifacts. Earlier tweaks (near tolerance, motion bias, camera lead) disproved.

## 2026-10-11: co-op reliability and remote combat

- Three agents audited room transport, Source/guest combat ownership, and projectile/aim timing. User changes preserved; no games launched or closed.
- Fixed loss of pending block edits on disconnect/backlog overflow, added authenticated input IDs/replay dedupe and bounded application receipts; room events remain pending until guarded Minecraft server dispatch emits roomack.
- Split 5-second network membership lease from the unchanged 1-second frozen Source watchdog; tick delay now includes elapsed RTT rather than adding another fixed sleep.
- Python bridge drains bounded guest message batches and logs them together. Source reply acknowledgements no longer evict discrete melee/teleport events from the gameplay deque.
- Remote client mob copies accept melee routed through their actual owning guest server, with current-scene/owner/distance validation and duplicate-hit suppression. Remote projectile/splash damage against these client-only mob replicas remains unsupported.
- Projectile reports retain launch origins across snapshot coalescing; Source immediately traces the first segment and skips resolved/zero-length retries. Fresh aim is applied before attacks/throws; front-camera physical pitch inversion removed.
- New Update-Coop.cmd/tools/update_coop.ps1 rebuild/check/update an existing owned installation without starting games or changing room config. Both PCs must update and restart before testing.
- Final updater: Gradle build/check passed; 133 Python tests passed; host Squirrel syntax and all 11 Source regression scripts passed. Rebuilt guest JAR installed locally. Tests exercise real loopback sockets; a real two-PC latency/gameplay verification is still required.
- Deliverable: release/l4d2mc-coop-update.zip (sources, no private portraits/retail assets or room secrets). Full friend ZIP updated too.
- Generated co-op YouTube thumbnail and English title/description copy saved under output/youtube; built-in imagegen used.
