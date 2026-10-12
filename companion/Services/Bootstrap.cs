using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Threading.Tasks;

namespace L4D2MC.Companion {
    public sealed class Bootstrap {
        readonly Settings settings;readonly Downloads download;readonly Action<string> log;public readonly Runner Runner;
        string Root=>settings.Project;
        string Tools=>Path.Combine(Root,"toolchains");
        public Bootstrap(Settings settings,Downloads download,Action<string> log){this.settings=settings;this.download=download;this.log=log;Runner=new Runner(settings.Project,log);}
        public async Task Prepare() {
            Directory.CreateDirectory(Tools);
            var python=Path.Combine(Tools,"python312");
            if(!System.IO.File.Exists(Path.Combine(python,"python.exe"))){var zip=await download.File("https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip","python312.zip");Downloads.Extract(zip,python);}
            // Embedded Python is isolated; only the private tool environment and project modules are added.
            System.IO.File.WriteAllLines(Path.Combine(python,"python312._pth"),new[]{"python312.zip",".","Lib\\site-packages",Path.Combine(Root,"passthrough"),Path.Combine(Root,"tools"),"import site"});
            Runner.PythonDir=python;
            var py=Path.Combine(python,"python.exe");
            if(!Directory.Exists(Path.Combine(python,"Lib","site-packages","pip"))){var pip=await download.File("https://bootstrap.pypa.io/get-pip.py","get-pip.py");await Runner.Run(py,pip,"--no-warn-script-location");}
            // The embeddable interpreter ignores pip's temporary build-environment paths.
            // Install build metadata locally; websockets' C speedup is optional.
            await Runner.Run(py,"-m","pip","install","setuptools","wheel","--disable-pip-version-check");
            await Runner.Run(py,"-m","pip","install","-r",Path.Combine(Root,"requirements.txt"),"--no-build-isolation","--disable-pip-version-check");
            var java=Path.Combine(Tools,"jdk25");
            if(!System.IO.File.Exists(Path.Combine(java,"bin","java.exe"))){
                var assets=Downloads.Arr(await download.Api("https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse"));
                var package=Downloads.Obj(Downloads.Obj(Downloads.Obj(assets.First())["binary"])["package"]);
                var zip=await download.File((string)package["link"],"jdk25.zip",(string)package["checksum"]);
                var tmp=Path.Combine(Tools,"jdk-download");Downloads.Extract(zip,tmp);var dir=Directory.GetDirectories(tmp).First(d=>System.IO.File.Exists(Path.Combine(d,"bin","java.exe")));Directory.Move(dir,java);
            }
            Runner.JavaHome=java;
            var zigRoot=Path.Combine(Tools,"zig-x86_64-windows-0.15.2");
            if(!System.IO.File.Exists(Path.Combine(zigRoot,"zig.exe"))||!System.IO.File.Exists(Path.Combine(zigRoot,"lib","std","Build","Cache.zig"))){
                var index=Downloads.Obj(await download.Api("https://ziglang.org/download/index.json"));var spec=Downloads.Obj(Downloads.Obj(index["0.15.2"])["x86_64-windows"]);
                var zip=await download.File((string)spec["tarball"],"zig0152.zip",(string)spec["shasum"]);Downloads.Extract(zip,Tools);
            }
            var sdk=Path.Combine(Tools,"reshade-6.8.0");
            if(!System.IO.File.Exists(Path.Combine(sdk,"include","reshade.hpp"))){var zip=await download.File("https://github.com/crosire/reshade/archive/refs/tags/v6.8.0.zip","reshade-sdk.zip");Downloads.Extract(zip,Tools);}
            var dll=Path.Combine(Tools,"ReShade32.dll");
            if(!System.IO.File.Exists(dll)){
                var exe=await download.File("https://reshade.me/downloads/ReShade_Setup_6.8.0_Addon.exe","ReShade_Setup_6.8.0_Addon.exe");
                // The official installer is a PE+ZIP; read its payload without running its UI.
                await Runner.Run(py,"-c","import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); open(sys.argv[2],'wb').write(z.read('ReShade32.dll'))",exe,dll);
            }
            var squirrel=Path.Combine(Tools,"squirrel-parser");var sq=Path.Combine(squirrel,"sq-win32.exe");
            if(!System.IO.File.Exists(sq)){
                if(!System.IO.File.Exists(Path.Combine(squirrel,"sq","sq.c"))){var zip=await download.File("https://github.com/albertodemichelis/squirrel/archive/refs/tags/v3.2.zip","squirrel32.zip");var tmp=Path.Combine(Tools,"squirrel-download");Downloads.Extract(zip,tmp);Directory.Move(Directory.GetDirectories(tmp).First(),squirrel);}
                var args=new List<string>{"c++","-target","x86-windows-gnu","-O2","-static","-x","c++","-I",Path.Combine(squirrel,"include"),Path.Combine(squirrel,"sq","sq.c")};
                args.AddRange(Directory.GetFiles(Path.Combine(squirrel,"squirrel"),"*.cpp"));args.AddRange(Directory.GetFiles(Path.Combine(squirrel,"sqstdlib"),"*.cpp"));args.AddRange(new[]{"-o",sq});await Runner.Run(Path.Combine(zigRoot,"zig.exe"),args.ToArray());
            }
            log("Python, Java, Zig, ReShade и Squirrel готовы.");
        }
        public async Task Install() {
            if(!Paths.Game(settings.Game)||!Paths.Minecraft(settings.Minecraft))throw new InvalidOperationException("Укажите папки L4D2 и Minecraft.");
            if(!System.IO.File.Exists(Path.Combine(settings.Game,"bin","vpk.exe"))||!System.IO.File.Exists(Path.Combine(settings.Game,"bin","studiomdl.exe")))throw new InvalidOperationException("Сначала установите Left 4 Dead 2 Authoring Tools в Steam. Кнопка есть в разделе установки.");
            await Prepare();
            await Runner.Run("powershell.exe","-NoProfile","-ExecutionPolicy","Bypass","-File",Path.Combine(Root,"Setup-L4D2MC.ps1"),"-Game",settings.Game,"-Minecraft",settings.Minecraft,"-JavaHome",Runner.JavaHome,"-ReShadeDll",Path.Combine(Tools,"ReShade32.dll"),"-Zig",Path.Combine(Tools,"zig-x86_64-windows-0.15.2","zig.exe"),"-ReShadeInclude",Path.Combine(Tools,"reshade-6.8.0","include"),"-Squirrel",Path.Combine(Tools,"squirrel-parser","sq-win32.exe"));
        }
        public Runner LaunchRunner(){var py=Path.Combine(Tools,"python312");if(System.IO.File.Exists(Path.Combine(py,"python.exe")))Runner.PythonDir=py;var java=Path.Combine(Tools,"jdk25");if(System.IO.File.Exists(Path.Combine(java,"bin","java.exe")))Runner.JavaHome=java;return Runner;}
    }
}
