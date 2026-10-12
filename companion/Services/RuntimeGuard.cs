using System;
using System.Diagnostics;
using System.Management;
namespace L4D2MC.Companion {
 public static class RuntimeGuard {
  public static bool IsMinecraftCommand(string command)=>command!=null&&(command.IndexOf("L4D2MC-Fabric",StringComparison.OrdinalIgnoreCase)>=0||command.IndexOf("net.minecraft.client.main.Main",StringComparison.OrdinalIgnoreCase)>=0||command.IndexOf("net.fabricmc.loader",StringComparison.OrdinalIgnoreCase)>=0);
  public static void RequireClosedGames(){
   bool running=false;foreach(var process in Process.GetProcessesByName("left4dead2")){using(process)running=true;}
   // Inspect only JVM identity. Command lines may contain credentials; never log them.
   try{using(var search=new ManagementObjectSearcher("SELECT CommandLine FROM Win32_Process WHERE Name='javaw.exe' OR Name='java.exe'"))using(var rows=search.Get())foreach(ManagementObject row in rows)using(row)if(IsMinecraftCommand(row["CommandLine"] as string))running=true;}catch(ManagementException){}
   if(running)throw new InvalidOperationException(Localization.Text("Перед обновлением закрой Minecraft и L4D2. Лаунчер можно оставить открытым."));
  }
 }
}
