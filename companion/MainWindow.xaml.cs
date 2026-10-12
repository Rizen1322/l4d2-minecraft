using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace L4D2MC.Companion {
 public partial class MainWindow : Window {
  Settings settings; bool busy; string logPath;
  public MainWindow(){InitializeComponent(); settings=Settings.Load();Paths.Detect(settings);Directory.CreateDirectory(Settings.Data);logPath=Path.Combine(Settings.Data,"companion.log");Fill();RefreshHealth();Closing+=(s,e)=>{if(busy){e.Cancel=true;Status.Text="Дождись завершения операции. Окно можно свернуть.";}};Loaded+=Preview;}
  void Fill(){ProjectPath.Text=settings.Project;GamePath.Text=settings.Game;MinecraftPath.Text=settings.Minecraft;Player.Text=settings.Player;ViewWidth.Text=settings.Width.ToString();ViewHeight.Text=settings.Height.ToString();Address.ItemsSource=Paths.Addresses();if(Address.Items.Count>0)Address.SelectedIndex=0;}
  void Save(){settings.Project=ProjectPath.Text.Trim();settings.Game=GamePath.Text.Trim();settings.Minecraft=MinecraftPath.Text.Trim();settings.Player=Player.Text.Trim();if(!Path.IsPathRooted(settings.Project))throw new ArgumentException("Укажи полный путь к папке проекта.");if(!int.TryParse(ViewWidth.Text,out var w)||w<320||w>3840||!int.TryParse(ViewHeight.Text,out var h)||h<240||h>2160)throw new ArgumentException("Разрешение: от 320×240 до 3840×2160.");settings.Width=w;settings.Height=h;settings.Save();}
  void Log(string line){Dispatcher.Invoke(()=>{LogText.AppendText(line+Environment.NewLine);LogText.ScrollToEnd();File.AppendAllText(logPath,DateTime.Now.ToString("HH:mm:ss ")+line+Environment.NewLine);});}
  Downloads Downloader()=>new Downloads(Path.Combine(Settings.Data,"downloads"),Log,v=>Dispatcher.Invoke(()=>Progress.Value=v));
  async Task Work(string title,Func<Task> action){if(busy)return;busy=true;Status.Text=title;Progress.Value=0;try{Save();await action();Status.Text="Готово • "+title;Progress.Value=100;}catch(Exception e){Status.Text=e.Message;Log("Ошибка: "+e.Message);Show("Logs");}finally{busy=false;RefreshHealth();}}
  void Show(string page){foreach(var p in new[]{Home,Install,Coop,Play,Logs})p.Visibility=p.Name==page?Visibility.Visible:Visibility.Collapsed;}
  void Navigate(object s,RoutedEventArgs e)=>Show((string)((Button)s).Tag);
  void RefreshHealth(){Health.Text=(Paths.Project(settings.Project)?"✓ Проект найден":"○ Проект ещё не скачан")+"\n"+(Paths.Game(settings.Game)?"✓ Left 4 Dead 2 найден":"○ Укажи папку Left 4 Dead 2")+"\n"+(Paths.Minecraft(settings.Minecraft)?"✓ Minecraft найден":"○ Укажи папку Minecraft")+"\n"+(File.Exists(Path.Combine(settings.Game??"","bin","studiomdl.exe"))?"✓ Authoring Tools установлены":"○ Нужны Steam Authoring Tools")+"\n"+(File.Exists(Path.Combine(settings.Project,"backups","passthrough-install.json"))?"✓ Мод установлен":"○ Мод ещё не установлен");RoomState.Text=Room.Describe(settings.Project);}
  void Refresh(object s,RoutedEventArgs e){if(busy)return;try{Save();RefreshHealth();}catch(Exception ex){Status.Text=ex.Message;}}
  void Detect(object s,RoutedEventArgs e){if(busy)return;Paths.Detect(settings);Fill();RefreshHealth();}
  void Browse(object s,RoutedEventArgs e){if(busy)return;using(var dialog=new System.Windows.Forms.FolderBrowserDialog()){dialog.Description="Выбери папку";if(dialog.ShowDialog()==System.Windows.Forms.DialogResult.OK){var tag=(string)((Button)s).Tag;(tag=="Project"?ProjectPath:tag=="Game"?GamePath:MinecraftPath).Text=dialog.SelectedPath;}}}
  async void Download(object s,RoutedEventArgs e)=>await Work("Обновление проекта",()=>Downloader().DownloadProject(settings.Project));
  async void InstallMod(object s,RoutedEventArgs e)=>await Work("Установка мода",async()=>{if(!Paths.Project(settings.Project))await Downloader().DownloadProject(settings.Project);await new Bootstrap(settings,Downloader(),Log).Install();});
  async void HostRoom(object s,RoutedEventArgs e)=>await Work("Комната создана",()=>{RequireProject();Clipboard.SetText(Room.Create(settings.Project,Address.Text.Trim()));Log("Приглашение скопировано. Передай его другу в общей LAN/VPN сети.");return Task.CompletedTask;});
  async void JoinRoom(object s,RoutedEventArgs e)=>await Work("Подключение сохранено",()=>{RequireProject();Room.Join(settings.Project,Invite.Password,settings.Player);Invite.Clear();Log("Режим гостя сохранён для твоего ника: "+settings.Player);return Task.CompletedTask;});
  async void Solo(object s,RoutedEventArgs e)=>await Work("Одиночный режим",()=>{RequireProject();Room.Off(settings.Project);return Task.CompletedTask;});
  void RequireProject(){if(!Paths.Project(settings.Project))throw new InvalidOperationException("Сначала скачай проект в разделе установки.");}
  async void Launch(object s,RoutedEventArgs e)=>await Work("Мост работает",async()=>{RequireProject();if(!File.Exists(Path.Combine(settings.Project,"backups","passthrough-install.json")))throw new InvalidOperationException("Сначала установи мод.");Show("Logs");await new Bootstrap(settings,Downloader(),Log).LaunchRunner().Run("powershell.exe","-NoProfile","-ExecutionPolicy","Bypass","-File",Path.Combine(settings.Project,"Launch-Minecraft.ps1"),"-Game",settings.Game,"-Width",settings.Width.ToString(),"-Height",settings.Height.ToString(),"-Borderless");});
  static void Open(string target)=>Process.Start(new ProcessStartInfo(target){UseShellExecute=true});
  void GitHub(object s,RoutedEventArgs e)=>Open("https://github.com/Rizen1322/l4d2-minecraft");
  void Authoring(object s,RoutedEventArgs e)=>Open("steam://install/563");
  void OpenMinecraft(object s,RoutedEventArgs e){var legacy=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),@".tlauncher\legacy\Minecraft\LL.exe");if(File.Exists(legacy))Open(legacy);else if(Directory.Exists(MinecraftPath.Text))Open(MinecraftPath.Text);else Status.Text="Укажи папку Minecraft в разделе установки.";}
  void OpenLog(object s,RoutedEventArgs e){if(File.Exists(logPath))Open(logPath);}
  void Preview(object s,RoutedEventArgs e){var args=Environment.GetCommandLineArgs();if(args.Length==3&&args[1]=="--preview"){Dispatcher.BeginInvoke(new Action(()=>{UpdateLayout();var visual=(FrameworkElement)Content;var bmp=new RenderTargetBitmap((int)visual.ActualWidth,(int)visual.ActualHeight,96,96,PixelFormats.Pbgra32);bmp.Render(visual);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bmp));using(var stream=File.Create(args[2]))png.Save(stream);Close();}),System.Windows.Threading.DispatcherPriority.ApplicationIdle);}}
 }
}
