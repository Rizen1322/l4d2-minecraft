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
