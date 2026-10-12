# 0.3.0 Alpha — Desktop Companion & Combat Audio

Download **L4D2MC-Companion.exe** below. Run it, open **Установка**, check the detected game folders and click **Установить мод**. The app downloads this release's source archive and official build tools. Install L4D2 Authoring Tools through its Steam button if needed. Both games must be closed during installation.

**Кооператив** creates a private LAN/VPN invitation or joins a friend's room using your own L4D2 nickname. **Играть** starts the bridge and L4D2 at the selected borderless resolution. Launch the Minecraft profile through your normal launcher first.

Minecraft weak/strong/sweep sounds now accompany hits against Source infected. Confirmed hit sounds are deduplicated across retries; dead infected do not generate successful-hit sounds. No Minecraft audio files are distributed.

Requirements: Windows 10/11, .NET Framework 4.8, Steam L4D2, Minecraft Java 26.3 and official L4D2 Authoring Tools. Shared LAN/VPN connectivity is still required for co-op. The EXE is unsigned.

Validation: WPF release build and visual preview; real child-process Unicode/quoted arguments; invitation and archive checks; clean GitHub download, complete tool preparation and native/Fabric/Source build; 134 Python tests and 11 Source regression suites. Local installed components updated without launching games. Actual game audio and installation on a second PC still need verification.

The source ZIP contains code and documentation. Game-derived JARs, HUD portraits, private configs, saves and downloaded toolchains are excluded. SHA-256 files accompany both assets.
