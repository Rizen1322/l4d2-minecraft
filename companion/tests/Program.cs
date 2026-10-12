using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using L4D2MC.Companion;
class Program {
 static void Check(bool ok,string why){if(!ok)throw new Exception(why);}
 static void Main(string[] args){
  if(args.Length==2&&args[0]=="--download"){new Downloads(Path.Combine(args[1],"cache"),Console.WriteLine,v=>{}).DownloadProject(Path.Combine(args[1],"project")).GetAwaiter().GetResult();return;}
  if(args.Length==2&&args[0]=="--tools"){new Bootstrap(new Settings{Project=Path.Combine(args[1],"project")},new Downloads(Path.Combine(args[1],"cache"),Console.WriteLine,v=>{}),Console.WriteLine).Prepare().GetAwaiter().GetResult();return;}
  if(args.Length>0&&args[0]=="--echo"){File.WriteAllText(args[1],Json.Encode(args.Skip(2).ToArray()));return;}
  var root=Path.Combine(Path.GetTempPath(),"L4D2MC test "+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
  try{
   var output=Path.Combine(root,"argv.json");var values=new[]{"",@"C:\папка с пробелом\", "one\"two", @"slashes\\\", @"E:\вин\ПРОЕКТЫ\main\l4d2-minecraft\passthrough\bridge.py"};
   var runner=new Runner(root,Console.WriteLine);runner.Run(Process.GetCurrentProcess().MainModule.FileName,new[]{"--echo",output}.Concat(values).ToArray()).GetAwaiter().GetResult();Check(values.SequenceEqual(Json.Decode<string[]>(File.ReadAllText(output))),"Process argument quoting changed values");
   foreach(var path in new[]{"../escape","C:\\escape", "file:stream"}){bool rejected=false;try{Paths.Child(root,path);}catch(InvalidDataException){rejected=true;}Check(rejected,"Unsafe path accepted: "+path);}
   var invite=Room.Create(root,"192.168.1.5");Check(invite==Room.Create(root,"192.168.1.5"),"Host token rotated unexpectedly");Room.Join(root,invite,"Gedayo");var config=Json.Object(File.ReadAllText(Path.Combine(root,"l4d2mc.coop.json")));Check((string)config["player"]=="Gedayo"&&(string)config["mode"]=="join","Guest nick/role changed");Room.Off(root);Check(Room.Describe(root)=="Одиночная игра","Room cleanup failed");
   var zip=Path.Combine(root,"evil.zip");using(var z=ZipFile.Open(zip,ZipArchiveMode.Create)){using(var w=new StreamWriter(z.CreateEntry("../escape.txt").Open()))w.Write("escape");}bool unsafeZip=false;try{Downloads.Extract(zip,Path.Combine(root,"unpack"));}catch(InvalidDataException){unsafeZip=true;}Check(unsafeZip&&!File.Exists(Path.Combine(root,"escape.txt")),"ZIP traversal escaped destination");
   Console.WriteLine("Companion: real Unicode argv, archive traversal, host token and guest nickname passed.");
  }finally{Directory.Delete(root,true);}
 }
}
