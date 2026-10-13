using System;
using System.Collections.Generic;
using System.Linq;

namespace L4D2MC.Companion {
 public static class Localization {
  public static string Language="ru";
  public static readonly IReadOnlyDictionary<string,string> English = Catalog.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries).Select(l=>l.Split('|')).ToDictionary(p=>p[0],p=>p[1]);
  static readonly KeyValuePair<string,string>[] Pairs=English.OrderByDescending(p=>Math.Max(p.Key.Length,p.Value.Length)).ToArray();
  public static string Text(string value){
   if(value==null)return null;
   if(value.StartsWith("Готово • ",StringComparison.Ordinal)||value.StartsWith("Done • ",StringComparison.Ordinal))
    return (Language=="en"?"Done • ":"Готово • ")+Text(value.Substring(value.IndexOf(" • ",StringComparison.Ordinal)+3));
   // Accept either language so a visible status can switch without restarting a task.
   foreach(var p in Pairs){
    if(value.StartsWith(p.Key,StringComparison.Ordinal))return Language=="en"?p.Value+value.Substring(p.Key.Length):value;
    if(value.StartsWith(p.Value,StringComparison.Ordinal))return Language=="en"?value:p.Key+value.Substring(p.Value.Length);
   }
   return value;
  }
  const string Catalog=@"Производительность Minecraft|Minecraft performance
Качество · 100%, без лимита FPS|Quality · 100%, uncapped FPS
Баланс · 75%, 90 FPS|Balanced · 75%, 90 FPS
Слабый ПК · 50%, 60 FPS|Low-end PC · 50%, 60 FPS
L4D2 сохраняет своё разрешение. Ниже режим — меньше нагрузка, мягче картинка Minecraft.|L4D2 keeps its resolution. Lower presets reduce load and soften Minecraft visuals.
Неверный файл контрольной суммы релиза.|Invalid release checksum file.
Обновить и установить|Update and install
Перед обновлением закрой Minecraft и L4D2. Лаунчер можно оставить открытым.|Close Minecraft and L4D2 before updating. The launcher can stay open.
Имя карты: только буквы, цифры и подчёркивание.|Map name: letters, numbers and underscores only.
Карта соло / хоста · например c1m1_hotel|Solo / host map · for example c1m1_hotel
1 / Запусти Minecraft|1 / Start Minecraft
2 / Запусти связку|2 / Start the mashup
Left 4 Dead 2 · папка с left4dead2.exe|Left 4 Dead 2 · folder containing left4dead2.exe
Minecraft · папка с versions|Minecraft · folder containing versions
Python, Java, Zig, ReShade и Squirrel готовы.|Python, Java, Zig, ReShade and Squirrel are ready.
Архив превышает допустимый размер.|The archive exceeds the size limit.
Архив пытается выйти за папку установки.|The archive tries to escape the installation folder.
Архив содержит личные данные.|The archive contains private data.
В папке установки обнаружена ссылка на другой каталог.|The installation folder contains a directory link.
В своём лаунчере выбери L4D2MC-Fabric-26.3. Используй обычный вход в аккаунт. Приложение не запрашивает пароль Minecraft.|Select L4D2MC-Fabric-26.3 in your launcher and sign in normally. This app does not ask for your Minecraft password.
Вернуться в одиночный режим|Switch to solo mode
Версия проекта: |Project version: 
Выбери адрес общей LAN/VPN сети. Приглашение содержит ключ комнаты — отправь его только другу.|Choose your shared LAN/VPN address. The invitation contains the room key — share it only with your friend.
Выбери папки игр. Приложение скачает исходники с GitHub, подготовит инструменты и установит мод. Затем запусти профиль Minecraft в своём лаунчере и нажми «Запустить связку».|Choose your game folders. The app downloads the source from GitHub, prepares the tools and installs the mod. Then start the Minecraft profile in your launcher and click Start the mashup.
Выбери папку|Choose a folder
Высота|Height
Готовность системы|System readiness
Готово • |Done • 
Готово|Ready
Две игры. Одна карта.|Two games. One map.
Для мода нужна отдельная папка проекта, не папка игры.|Choose a separate project folder, not a game folder.
Дождись завершения операции. Окно можно свернуть.|Wait for the operation to finish. You can minimize this window.
Журнал|Log
Идём вдвоём|Better together
Исходники проверены и обновлены. Сохранения и настройки комнаты сохранены.|Source verified and updated. Saves and room settings were preserved.
Комната создана|Room created
Контрольная сумма не совпадает: |Checksum mismatch: 
Мост и L4D2 запустятся вместе. В коопе автоматически используется сохранённая комната. Оставь это окно открытым во время игры.|The bridge and L4D2 start together. Co-op uses your saved room settings. Keep this window open while playing.
Мост работает|Bridge running
На GitHub пока нет исходников с контрольной суммой.|No source release with a checksum was found on GitHub.
Найти автоматически|Detect automatically
Настроить →|Set up →
Начни с установки|Start with setup
Небезопасный путь архива.|Unsafe archive path.
Нужны купленные игры и официальные L4D2 Authoring Tools. Перед установкой закрой обе игры. Инструменты скачиваются в папку проекта; аудио и текстуры берутся из твоих игр.|You need your own games and official L4D2 Authoring Tools. Close both games before installation. Tools are downloaded into the project; audio and textures come from your installed games.
Обновление проекта|Updating project
Одиночный режим|Solo mode
Одиночная игра|Solo game
Хост комнаты|Room host
Гость • |Guest • 
Открыть Minecraft / лаунчер|Open Minecraft / launcher
Открыть файл журнала|Open log file
Ошибка: |Error: 
Папка установки не должна быть ссылкой.|The installation folder must not be a directory link.
Папки|Folders
Повреждён файл исходников: |Damaged source file: 
Подключение сохранено|Connection saved
Поехали|Let's play
Приглашение скопировано. Передай его другу в общей LAN/VPN сети.|Invitation copied. Share it with your friend on the same LAN/VPN.
Режим комнаты применится при следующем запуске связки.|The room mode applies the next time you start the bridge.
Подожди: сейчас идёт игра или установка. Это действие доступно после неё.|Wait: a game session or installation is running. This action is available after it.
Приглашение|Invitation
Присоединиться к другу|Join a friend
Проверить ещё раз|Check again
Проект мода · отдельная папка|Mod project · separate folder
Разрешение: от 320×240 до 3840×2160.|Resolution must be between 320×240 and 3840×2160.
Режим гостя сохранён для твоего ника: |Guest mode saved for your nickname: 
Скачать / обновить проект|Download / update project
Скачать → собрать → установить|Download → build → install
Скачивание оборвалось. Повторите попытку.|Download interrupted. Please try again.
Скачивание: |Downloading: 
Сначала скачай проект в разделе установки.|Download the project in Setup first.
Сначала установи мод.|Install the mod first.
Сначала установите Left 4 Dead 2 Authoring Tools в Steam. Кнопка есть в разделе установки.|Install Left 4 Dead 2 Authoring Tools in Steam first. The button is on the Setup page.
Создать и скопировать приглашение|Create and copy invitation
Создать комнату|Host a room
Сохранить подключение|Save connection
Твой Minecraft. В L4D2.|Your Minecraft. Inside L4D2.
Твой собственный ник в L4D2 · не ник хоста|Your own L4D2 nickname · not the host's name
Укажи папку Minecraft в разделе установки.|Choose your Minecraft folder in Setup.
Укажи полный путь к папке проекта.|Enter an absolute path to the project folder.
Укажите папки L4D2 и Minecraft.|Choose the L4D2 and Minecraft folders.
Установить мод|Install mod
Установка и обновления|Setup and updates
Установка мода|Installing mod
Установка, обновления и кооп в одном окне.|Setup, updates and co-op in one window.
Шаг завершился с ошибкой |Operation failed with exit code 
. Подробности — в журнале.|. See the log for details.
Ширина|Width
↓   Установка|↓   Setup
≡   Журнал|≡   Log
▶   Играть|▶   Play
▶  Запустить связку|▶  Start the mashup
◈   Обзор|◈   Overview
○ Мод ещё не установлен|○ Mod not installed yet
○ Нужны Steam Authoring Tools|○ Steam Authoring Tools required
○ Проект ещё не скачан|○ Project not downloaded yet
○ Укажи папку Left 4 Dead 2|○ Choose your Left 4 Dead 2 folder
○ Укажи папку Minecraft|○ Choose your Minecraft folder
◎   Кооператив|◎   Co-op
✓ Authoring Tools установлены|✓ Authoring Tools installed
✓ Left 4 Dead 2 найден|✓ Left 4 Dead 2 found
✓ Minecraft найден|✓ Minecraft found
✓ Мод установлен|✓ Mod installed
✓ Проект найден|✓ Project found
Выберите IPv4-адрес вашей LAN/VPN сети.|Choose an IPv4 address on your LAN/VPN.
Введите собственный ник из L4D2.|Enter your own L4D2 nickname.
Слишком длинное приглашение.|The invitation is too long.
Не удалось прочитать код приглашения.|Could not read the invitation code.
Некорректное приглашение.|Invalid invitation.";
 }
}
