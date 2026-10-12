using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace L4D2MC.Companion {
    public sealed class Settings {
        public string Project {get;set;}="";
        public string Game {get;set;}="";
        public string Minecraft {get;set;}="";
        public string Player {get;set;}="";
        public string Language {get;set;}="ru";
        public int Width {get;set;}=2560;
        public int Height {get;set;}=1440;
        public static string Data=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"L4D2MC");
        public static Settings Load() {
            try{return Json.Decode<Settings>(File.ReadAllText(Path.Combine(Data,"companion.json")))??new Settings();}catch{return new Settings();}
        }
        public void Save(){Directory.CreateDirectory(Data);Json.Write(Path.Combine(Data,"companion.json"),this);}
    }
    public static class Json {
        static JavaScriptSerializer Serializer()=>new JavaScriptSerializer{MaxJsonLength=32*1024*1024};
        public static string Encode(object value)=>Serializer().Serialize(value);
        public static T Decode<T>(string value)=>Serializer().Deserialize<T>(value);
        public static Dictionary<string,object> Object(string value)=>Decode<Dictionary<string,object>>(value);
        public static void Write(string path,object value){Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));var tmp=path+".tmp";File.WriteAllText(tmp,Encode(value),new UTF8Encoding(false));if(File.Exists(path))File.Replace(tmp,path,null);else File.Move(tmp,path);}
    }
    public static class Paths {
        public static bool Game(string p)=>!string.IsNullOrWhiteSpace(p)&&File.Exists(Path.Combine(p,"left4dead2.exe"));
        public static bool Minecraft(string p)=>!string.IsNullOrWhiteSpace(p)&&Directory.Exists(Path.Combine(p,"versions"));
        public static bool Project(string p)=>!string.IsNullOrWhiteSpace(p)&&File.Exists(Path.Combine(p,"Setup-L4D2MC.ps1"))&&File.Exists(Path.Combine(p,"passthrough","bridge.py"));
        public static string Child(string root,string relative) {
            if(string.IsNullOrWhiteSpace(relative)||Path.IsPathRooted(relative)||relative.Contains(":"))throw new InvalidDataException(Localization.Text("Небезопасный путь архива."));
            var basis=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
            if(Directory.Exists(root)&&(File.GetAttributes(root)&FileAttributes.ReparsePoint)!=0)throw new InvalidDataException(Localization.Text("Папка установки не должна быть ссылкой."));
            var value=Path.GetFullPath(Path.Combine(basis,relative));
            if(!value.StartsWith(basis,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException(Localization.Text("Архив пытается выйти за папку установки."));
            for(var p=Path.GetDirectoryName(value);p!=null&&p.StartsWith(basis,StringComparison.OrdinalIgnoreCase);p=Path.GetDirectoryName(p))
                if(Directory.Exists(p)&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new InvalidDataException(Localization.Text("В папке установки обнаружена ссылка на другой каталог."));
            return value;
        }
        public static string Hash(string path){using(var stream=File.OpenRead(path))using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();}
        public static void Detect(Settings s) {
            if(!Project(s.Project)) {
                var d=new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
                for(int i=0;d!=null&&i<7;i++,d=d.Parent)if(Project(d.FullName)){s.Project=d.FullName;break;}
                if(!Project(s.Project))s.Project=Path.Combine(Settings.Data,"project");
            }
            if(Project(s.Project))try{var local=Json.Object(File.ReadAllText(Path.Combine(s.Project,"l4d2mc.local.json")));if(local.ContainsKey("game")&&Game((string)local["game"]))s.Game=(string)local["game"];if(local.ContainsKey("minecraft")&&Minecraft((string)local["minecraft"]))s.Minecraft=(string)local["minecraft"];}catch{}
            if(!Game(s.Game)) {
                var roots=new List<string>();
                try{using(var k=Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")){var p=k?.GetValue("SteamPath") as string;if(p!=null)roots.Add(p);}}catch{}
                roots.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"Steam"));
                foreach(var root in roots.ToArray())try{foreach(Match m in Regex.Matches(File.ReadAllText(Path.Combine(root,"steamapps","libraryfolders.vdf")),"\"path\"\\s+\"([^\"]+)\""))roots.Add(m.Groups[1].Value.Replace(@"\\",@"\"));}catch{}
                foreach(var root in roots){var p=Path.Combine(root,"steamapps","common","Left 4 Dead 2");if(Game(p)){s.Game=p;break;}}
            }
            if(!Minecraft(s.Minecraft))foreach(var p in new[]{Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),@".tlauncher\legacy\Minecraft\game"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),".minecraft")})if(Minecraft(p)){s.Minecraft=p;break;}
        }
        public static string[] Addresses()=>NetworkInterface.GetAllNetworkInterfaces().Where(n=>n.OperationalStatus==OperationalStatus.Up).SelectMany(n=>n.GetIPProperties().UnicastAddresses).Select(a=>a.Address).Where(a=>a.AddressFamily==System.Net.Sockets.AddressFamily.InterNetwork&&!IPAddress.IsLoopback(a)&&!a.ToString().StartsWith("169.254.")).Select(a=>a.ToString()).Distinct().ToArray();
    }
    public static class Room {
        public static string Create(string root,string ip) {
            if(!IPAddress.TryParse(ip,out var address)||address.AddressFamily!=System.Net.Sockets.AddressFamily.InterNetwork)throw new ArgumentException(Localization.Text("Выберите IPv4-адрес вашей LAN/VPN сети."));
            var path=Path.Combine(root,"l4d2mc.coop.json");string token=null;
            try{var old=Json.Object(File.ReadAllText(path));if((string)old["mode"]=="host"&&Regex.IsMatch((string)old["token"],"^[A-Za-z0-9_-]{32,128}$"))token=(string)old["token"];}catch{}
            if(token==null){var b=new byte[32];using(var random=RandomNumberGenerator.Create())random.GetBytes(b);token=Convert.ToBase64String(b).TrimEnd('=').Replace('+','-').Replace('/','_');}
            Json.Write(path,new{mode="host",bind="0.0.0.0",port=25602,token});
            return Convert.ToBase64String(Encoding.UTF8.GetBytes("L4D2MC1|"+ip+"|"+token));
        }
        public static void Join(string root,string invite,string player) {
            player=(player??"").Trim();if(player.Length==0||player.Length>128||player.Any(char.IsControl))throw new ArgumentException(Localization.Text("Введите собственный ник из L4D2."));
            if((invite??"").Length>1024)throw new ArgumentException(Localization.Text("Слишком длинное приглашение."));
            string[] p;try{p=Encoding.UTF8.GetString(Convert.FromBase64String(invite.Trim())).Split('|');}catch{throw new ArgumentException(Localization.Text("Не удалось прочитать код приглашения."));}
            if(p.Length!=3||p[0]!="L4D2MC1"||!IPAddress.TryParse(p[1],out var ip)||ip.AddressFamily!=System.Net.Sockets.AddressFamily.InterNetwork||!Regex.IsMatch(p[2],"^[A-Za-z0-9_-]{32,128}$"))throw new ArgumentException(Localization.Text("Некорректное приглашение."));
            Json.Write(Path.Combine(root,"l4d2mc.coop.json"),new{mode="join",server="ws://"+p[1]+":25602",l4d2server=p[1]+":27015",player,token=p[2]});
        }
        public static void Off(string root){var p=Path.Combine(root,"l4d2mc.coop.json");if(File.Exists(p))File.Delete(p);}
        public static string Describe(string root){try{var c=Json.Object(File.ReadAllText(Path.Combine(root,"l4d2mc.coop.json")));return (string)c["mode"]=="host"?Localization.Text("Хост комнаты"):Localization.Text("Гость • ")+c["player"];}catch{return Localization.Text("Одиночная игра");}}
    }
    public sealed class Runner {
        readonly string root;readonly Action<string> log;public string PythonDir;public string JavaHome;
        public Runner(string root,Action<string> log){this.root=root;this.log=log;}
        public static string Quote(string value) {
            var text=new StringBuilder("\"");int slashes=0;
            foreach(var c in value??"") {
                if(c=='\\'){slashes++;continue;}
                if(c=='"'){text.Append('\\',slashes*2+1);text.Append(c);}
                else {text.Append('\\',slashes);text.Append(c);}
                slashes=0;
            }
            text.Append('\\',slashes*2);text.Append('"');return text.ToString();
        }
        public ProcessStartInfo Start(string exe,IEnumerable<string> args,bool capture=true){
            var p=new ProcessStartInfo(exe,string.Join(" ",args.Select(Quote))){WorkingDirectory=root,UseShellExecute=false,CreateNoWindow=capture,RedirectStandardOutput=capture,RedirectStandardError=capture,StandardOutputEncoding=capture?Encoding.UTF8:null,StandardErrorEncoding=capture?Encoding.UTF8:null};
            if(PythonDir!=null)p.EnvironmentVariables["PATH"]=PythonDir+";"+p.EnvironmentVariables["PATH"];
            if(JavaHome!=null)p.EnvironmentVariables["JAVA_HOME"]=JavaHome;
            p.EnvironmentVariables["PYTHONIOENCODING"]="utf-8";p.EnvironmentVariables["PYTHONUNBUFFERED"]="1";
            return p;
        }
        public Task Run(string exe,params string[] args)=>Task.Run(()=>{
            using(var p=new Process{StartInfo=Start(exe,args)}){
                p.OutputDataReceived+=(s,e)=>{if(e.Data!=null)log(e.Data);};p.ErrorDataReceived+=(s,e)=>{if(e.Data!=null)log(e.Data);};
                p.Start();p.BeginOutputReadLine();p.BeginErrorReadLine();p.WaitForExit();if(p.ExitCode!=0)throw new InvalidOperationException(Localization.Text("Шаг завершился с ошибкой ")+p.ExitCode+Localization.Text(". Подробности — в журнале."));
            }
        });
    }
}
