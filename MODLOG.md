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
