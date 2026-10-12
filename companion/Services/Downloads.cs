using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace L4D2MC.Companion {
    public sealed class Downloads {
        readonly HttpClient http=new HttpClient{Timeout=TimeSpan.FromMinutes(30)};
        readonly Action<string> log;readonly Action<double> progress;readonly string cache;
        public Downloads(string cache,Action<string> log,Action<double> progress){this.cache=cache;this.log=log;this.progress=progress;Directory.CreateDirectory(cache);http.DefaultRequestHeaders.UserAgent.ParseAdd("L4D2MC-Companion/0.3.0");}
        public static Dictionary<string,object> Obj(object value)=>(Dictionary<string,object>)value;
        public static IEnumerable<object> Arr(object value)=>((IEnumerable)value).Cast<object>();
        public async Task<object> Api(string url){using(var response=await http.GetAsync(url)){response.EnsureSuccessStatusCode();return Json.Decode<object>(await response.Content.ReadAsStringAsync());}}
        public async Task<string> File(string url,string name,string expected=null) {
            var target=Paths.Child(cache,name);
            if(System.IO.File.Exists(target)&&expected!=null&&Paths.Hash(target)==expected.ToLowerInvariant())return target;
            log(Localization.Text("Скачивание: ")+name);var temporary=target+".part";
            using(var response=await http.GetAsync(url,HttpCompletionOption.ResponseHeadersRead)) {
                response.EnsureSuccessStatusCode();var length=response.Content.Headers.ContentLength??0;
                using(var input=await response.Content.ReadAsStreamAsync())using(var output=new FileStream(temporary,FileMode.Create,FileAccess.Write,FileShare.None,81920,true)){
                    var buffer=new byte[81920];long total=0;int count;var last=DateTime.MinValue;
                    while((count=await input.ReadAsync(buffer,0,buffer.Length))>0){await output.WriteAsync(buffer,0,count);total+=count;if((DateTime.UtcNow-last).TotalMilliseconds>150){progress(length>0?100.0*total/length:0);last=DateTime.UtcNow;}}
                    if(length>0&&total!=length)throw new IOException(Localization.Text("Скачивание оборвалось. Повторите попытку."));
                }
            }
            if(expected!=null&&(!Regex.IsMatch(expected,"^[a-fA-F0-9]{64}$")||Paths.Hash(temporary)!=expected.ToLowerInvariant()))throw new InvalidDataException(Localization.Text("Контрольная сумма не совпадает: ")+name);
            if(System.IO.File.Exists(target))System.IO.File.Delete(target);System.IO.File.Move(temporary,target);progress(100);return target;
        }
        public static void Extract(string archive,string destination) {
            Directory.CreateDirectory(destination);long bytes=0;int count=0;
            using(var zip=ZipFile.OpenRead(archive))foreach(var entry in zip.Entries){
                if(++count>150000||(bytes+=entry.Length)>3L*1024*1024*1024)throw new InvalidDataException(Localization.Text("Архив превышает допустимый размер."));
                var target=Paths.Child(destination,entry.FullName.Replace('/',Path.DirectorySeparatorChar));
                if(entry.FullName.EndsWith("/")){Directory.CreateDirectory(target);continue;}
                Directory.CreateDirectory(Path.GetDirectoryName(target));entry.ExtractToFile(target,true);
            }
        }
        public async Task DownloadProject(string root) {
            if(Paths.Game(root)||Paths.Minecraft(root))throw new InvalidOperationException(Localization.Text("Для мода нужна отдельная папка проекта, не папка игры."));
            var releases=Arr(await Api("https://api.github.com/repos/Rizen1322/l4d2-minecraft/releases?per_page=20"));
            Dictionary<string,object> source=null,checksum=null;string tag=null;
            foreach(var releaseValue in releases){var release=Obj(releaseValue);if((bool)release["draft"])continue;var assets=Arr(release["assets"]).Select(Obj).ToArray();source=assets.FirstOrDefault(a=>((string)a["name"]).EndsWith("-source.zip"));if(source==null)continue;checksum=assets.FirstOrDefault(a=>(string)a["name"]==(string)source["name"]+".sha256");if(checksum!=null){tag=(string)release["tag_name"];break;}}
            if(source==null||checksum==null)throw new InvalidDataException(Localization.Text("На GitHub пока нет исходников с контрольной суммой."));
            log(Localization.Text("Версия проекта: ")+tag);
            var checksumFile=await File((string)checksum["browser_download_url"],"source.sha256");
            var sha=System.IO.File.ReadAllText(checksumFile).Split(new[]{' ','\r','\n','\t'},StringSplitOptions.RemoveEmptyEntries)[0];
            var archive=await File((string)source["browser_download_url"],"source.zip",sha);
            var staging=Path.Combine(cache,"source-"+Guid.NewGuid().ToString("N"));Extract(archive,staging);
            var payload=Path.Combine(staging,"l4d2-minecraft");var manifest=Json.Object(System.IO.File.ReadAllText(Path.Combine(payload,"SOURCE-MANIFEST.json")));
            // Validate every file before replacing any existing source. Personal data is never a payload.
            foreach(var row in manifest){var file=Paths.Child(payload,row.Key);if(Paths.Hash(file)!=(string)row.Value)throw new InvalidDataException(Localization.Text("Повреждён файл исходников: ")+row.Key);var parts=row.Key.Replace('\\','/').Split('/');if(parts.Any(p=>new[]{"backups","guest-game","evidence","toolchains"}.Contains(p))||Path.GetFileName(row.Key)=="l4d2mc.coop.json"||Path.GetFileName(row.Key)=="l4d2mc.local.json")throw new InvalidDataException(Localization.Text("Архив содержит личные данные."));Paths.Child(root,row.Key);}
            foreach(var row in manifest){var target=Paths.Child(root,row.Key);Directory.CreateDirectory(Path.GetDirectoryName(target));System.IO.File.Copy(Paths.Child(payload,row.Key),target,true);}
            log(Localization.Text("Исходники проверены и обновлены. Сохранения и настройки комнаты сохранены."));
        }
    }
}
