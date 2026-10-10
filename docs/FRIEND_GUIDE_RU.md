# Как установить мод другу и играть вместе

Мод экспериментальный. У каждого должны быть **свои** Steam L4D2 и Minecraft Java,
Windows и отдельный ПК. Один игрок — **хост** (держит карту L4D2 и комнату), второй —
**тиммейт**. Оба ставят **один и тот же архив**: разные версии не совместимы.

## 1. Что поставить другу (один раз)

1. **Python 3.12 или новее** — https://www.python.org/downloads/ .
   В установщике отметить **Add python.exe to PATH**.
2. **Java 25** — https://adoptium.net/temurin/releases/?version=25 (JDK, Windows x64, .msi,
   отметить *Set JAVA_HOME*). Если стоит TLauncher с Minecraft 26.3, его Java тоже подойдёт.
3. **Minecraft Java 26.3** в лаунчере (официальном или TLauncher). Один раз запустить 26.3
   без модов, чтобы скачались файлы, и закрыть.
4. **L4D2 Authoring Tools**: Steam → Библиотека → выпадающий список «Инструменты» →
   *Left 4 Dead 2 Authoring Tools* → Установить. Нужны `bin\vpk.exe` и `bin\studiomdl.exe`
   в папке L4D2.
5. **Виртуальная локалка**, если вы не в одной домашней сети:
   [Radmin VPN](https://www.radmin-vpn.com/ru/) (проще) или [Tailscale](https://tailscale.com/).
   Хост создаёт сеть, друг в неё заходит. Дальше везде используется **IP из Radmin/Tailscale**
   (например `26.x.x.x` или `100.x.x.x`). Порты в роутере **не открывать**.

## 2. Установка мода

1. Хост делает архив: в папке проекта
   `powershell -ExecutionPolicy Bypass -File tools\pack_for_friend.ps1`
   → `release\l4d2mc-friend.zip`. Передать файл другу (Telegram/диск).
   В архиве нет игр, сохранений, токена и личных путей; Zig, ReShade и Squirrel уже внутри.
2. Друг распаковывает в постоянную папку, лучше **без пробелов**, например
   `D:\Games\l4d2-minecraft`. Потом папку **не переносить**.
3. Закрыть L4D2 и Minecraft. Открыть PowerShell в этой папке
   (Shift+ПКМ по папке → «Открыть окно PowerShell здесь») и выполнить:

```powershell
python -m pip install -r requirements.txt
powershell -ExecutionPolicy Bypass -File .\Setup-L4D2MC.ps1 `
  -Game 'D:\SteamLibrary\steamapps\common\Left 4 Dead 2' `
  -Minecraft "$env:APPDATA\.minecraft" `
  -ReShadeDll '.\toolchains\ReShade32.dll'
```

   - `-Game` — папка L4D2 (Steam → L4D2 → Управление → Просмотреть локальные файлы).
   - `-Minecraft` — папка лаунчера, где лежит `versions`. Для TLauncher обычно
     `"$env:APPDATA\.minecraft"`; у новых TLauncher может быть
     `"$env:APPDATA\.tlauncher\legacy\Minecraft\game"`.
   - Если Java не нашлась: добавить `-JavaHome 'C:\Program Files\Eclipse Adoptium\jdk-25...'`.
   - В конце должно быть `Setup complete`. Игры скрипт не запускает.
4. В лаунчере Minecraft выбрать версию **L4D2MC-Fabric-26.3** (если нет — обновить список
   версий), запустить, создать/открыть одиночный мир. Проверить соло:
   запустить `Launch-L4D2MC-2K.bat` (для 1080p:
   `.\Launch-Minecraft.ps1 -Width 1920 -Height 1080 -Borderless`).
   Окно консоли лаунчера не закрывать до выхода из L4D2.

## 3. Настроить комнату (один раз)

**Хост** в папке проекта:

```powershell
python passthrough\configure_coop.py host
Get-Content l4d2mc.coop.json
```

Отправить другу **лично** свой Radmin/Tailscale IP и значение `token`. Токен никому
больше не показывать и не выкладывать на скриншотах.

**Друг** (имя — точно как ник в L4D2/Steam, у вас ники должны отличаться):

```powershell
python passthrough\configure_coop.py join --server 26.12.34.56 --player "Ник друга в L4D2"
```

Скрипт спросит токен — вставить (символы не видны, это нормально).

## 4. Каждый раз, чтобы поиграть

1. Оба: Radmin VPN/Tailscale включён, L4D2 закрыта.
2. Оба: запустить Minecraft профиль **L4D2MC-Fabric-26.3**, зайти в свой одиночный мир,
   не сворачивать.
3. **Хост** запускает `Launch-L4D2MC-2K.bat` и ждёт, пока загрузится карта.
4. **Друг** запускает `Launch-L4D2MC-2K.bat`; L4D2 сама подключится к хосту.
5. Если Windows спросит про доступ к сети для Python или L4D2 — разрешить только
   **частные сети**. Хосту нужны L4D2 порт 27015 и TCP 25602 через VPN.
6. Вернуть соло-режим: `python passthrough\configure_coop.py off`.

## Если не работает

- `Close the current L4D2 session` — закрыть L4D2 и запустить снова.
- `A Minecraft bridge is already running` — закрыть старое окно лаунчера; если не помогает,
  в Диспетчере задач завершить `python.exe` с `bridge.py`.
- Друг не подключается: проверить, что пинг до IP хоста идёт (`ping 26.x.x.x`), что ник в
  `join` совпадает с ником в игре, и что у обоих одинаковый архив.
- Ошибки скриптов смотреть в `Left 4 Dead 2\left4dead2\console.log`,
  ошибки моста — в `evidence\bridge-errors.log`. Эти файлы можно прислать хосту.

## Что синхронизируется

Общие: поставленные/сломанные блоки, Стив тиммейта с бронёй и предметом в руке, визуалы
мобов/TNT/снарядов. Свои у каждого: инвентарь Minecraft, сундуки, мобы (у друга видны
копии). До 4 игроков. Полная проверка на двух ПК ещё не проводилась — пишите, что ломается.
