using System;
using System.Collections.Generic;
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
  readonly Dictionary<DependencyObject,string> originalText=new Dictionary<DependencyObject,string>();
  void Localize(DependencyObject node){
   if(node is TextBlock text && text.Name!="Health" && text.Name!="RoomState" && text.Name!="Status"){
    if(!originalText.ContainsKey(text))originalText[text]=text.Text;
    text.Text=Localization.Text(originalText[text]);
   }else if(node is Button button && button.Content is string caption){
    if(!originalText.ContainsKey(button))originalText[button]=caption;
    button.Content=Localization.Text(originalText[button]);
   }
   foreach(var child in LogicalTreeHelper.GetChildren(node))if(child is DependencyObject element)Localize(element);
  }
  void ApplyLanguage(string language){Localization.Language=language=="en"?"en":"ru";Localize(this);Status.Text=Localization.Text(Status.Text);RefreshHealth();Russian.Background=Localization.Language=="ru"?(Brush)FindResource("Accent"):new SolidColorBrush(Color.FromRgb(40,48,61));English.Background=Localization.Language=="en"?(Brush)FindResource("Accent"):new SolidColorBrush(Color.FromRgb(40,48,61));Russian.Foreground=Localization.Language=="ru"?Brushes.Black:Brushes.White;English.Foreground=Localization.Language=="en"?Brushes.Black:Brushes.White;}
  void ChangeLanguage(object s,RoutedEventArgs e){settings.Language=(string)((Button)s).Tag;settings.Save();ApplyLanguage(settings.Language);}
  public MainWindow(){InitializeComponent(); settings=Settings.Load();Paths.Detect(settings);Directory.CreateDirectory(Settings.Data);logPath=Path.Combine(Settings.Data,"companion.log");Fill();ApplyLanguage(settings.Language);Closing+=(s,e)=>{if(busy){e.Cancel=true;Status.Text=Localization.Text("Дождись завершения операции. Окно можно свернуть.");}};Loaded+=Preview;}
  void Fill(){ProjectPath.Text=settings.Project;GamePath.Text=settings.Game;MinecraftPath.Text=settings.Minecraft;Player.Text=settings.Player;MapName.Text=settings.Map;ViewWidth.Text=settings.Width.ToString();ViewHeight.Text=settings.Height.ToString();Address.ItemsSource=Paths.Addresses();if(Address.Items.Count>0)Address.SelectedIndex=0;}
  void Save(){settings.Project=ProjectPath.Text.Trim();settings.Game=GamePath.Text.Trim();settings.Minecraft=MinecraftPath.Text.Trim();settings.Player=Player.Text.Trim();settings.Map=MapName.Text.Trim();if(!Settings.ValidMap(settings.Map))throw new ArgumentException(Localization.Text("Имя карты: только буквы, цифры и подчёркивание."));if(!Path.IsPathRooted(settings.Project))throw new ArgumentException(Localization.Text("Укажи полный путь к папке проекта."));if(!int.TryParse(ViewWidth.Text,out var w)||w<320||w>3840||!int.TryParse(ViewHeight.Text,out var h)||h<240||h>2160)throw new ArgumentException(Localization.Text("Разрешение: от 320×240 до 3840×2160."));settings.Width=w;settings.Height=h;settings.Save();}
  void Log(string line){Dispatcher.Invoke(()=>{LogText.AppendText(line+Environment.NewLine);LogText.ScrollToEnd();File.AppendAllText(logPath,DateTime.Now.ToString("HH:mm:ss ")+line+Environment.NewLine);});}
  Downloads Downloader()=>new Downloads(Path.Combine(Settings.Data,"downloads"),Log,v=>Dispatcher.Invoke(()=>Progress.Value=v));
  async Task Work(string title,Func<Task> action){if(busy)return;busy=true;Status.Text=title;Progress.Value=0;try{Save();await action();Status.Text=Localization.Text("Готово • ")+Localization.Text(title);Progress.Value=100;}catch(Exception e){Status.Text=e.Message;Log(Localization.Text("Ошибка: ")+e.Message);Show("Logs");}finally{busy=false;RefreshHealth();}}
  void Show(string page){foreach(var p in new[]{Home,Install,Coop,Play,Logs})p.Visibility=p.Name==page?Visibility.Visible:Visibility.Collapsed;}
  void Navigate(object s,RoutedEventArgs e)=>Show((string)((Button)s).Tag);
  void RefreshHealth(){Health.Text=(Paths.Project(settings.Project)?Localization.Text("✓ Проект найден"):Localization.Text("○ Проект ещё не скачан"))+"\n"+(Paths.Game(settings.Game)?Localization.Text("✓ Left 4 Dead 2 найден"):Localization.Text("○ Укажи папку Left 4 Dead 2"))+"\n"+(Paths.Minecraft(settings.Minecraft)?Localization.Text("✓ Minecraft найден"):Localization.Text("○ Укажи папку Minecraft"))+"\n"+(File.Exists(Path.Combine(settings.Game??"","bin","studiomdl.exe"))?Localization.Text("✓ Authoring Tools установлены"):Localization.Text("○ Нужны Steam Authoring Tools"))+"\n"+(File.Exists(Path.Combine(settings.Project,"backups","passthrough-install.json"))?Localization.Text("✓ Мод установлен"):Localization.Text("○ Мод ещё не установлен"));RoomState.Text=Room.Describe(settings.Project);}
  void Refresh(object s,RoutedEventArgs e){if(busy)return;try{Save();RefreshHealth();}catch(Exception ex){Status.Text=ex.Message;}}
  void Detect(object s,RoutedEventArgs e){if(busy)return;Paths.Detect(settings);Fill();RefreshHealth();}
  void Browse(object s,RoutedEventArgs e){if(busy)return;using(var dialog=new System.Windows.Forms.FolderBrowserDialog()){dialog.Description=Localization.Text("Выбери папку");if(dialog.ShowDialog()==System.Windows.Forms.DialogResult.OK){var tag=(string)((Button)s).Tag;(tag=="Project"?ProjectPath:tag=="Game"?GamePath:MinecraftPath).Text=dialog.SelectedPath;}}}
  async void Download(object s,RoutedEventArgs e)=>await Work(Localization.Text("Обновление проекта"),async()=>{RuntimeGuard.RequireClosedGames();await Downloader().DownloadProject(settings.Project);});
  async void InstallMod(object s,RoutedEventArgs e)=>await Work(Localization.Text("Установка мода"),async()=>{RuntimeGuard.RequireClosedGames();await Downloader().DownloadProject(settings.Project);await new Bootstrap(settings,Downloader(),Log).Install();});
  async void HostRoom(object s,RoutedEventArgs e)=>await Work(Localization.Text("Комната создана"),()=>{RequireProject();Clipboard.SetText(Room.Create(settings.Project,Address.Text.Trim()));Log(Localization.Text("Приглашение скопировано. Передай его другу в общей LAN/VPN сети."));return Task.CompletedTask;});
  async void JoinRoom(object s,RoutedEventArgs e)=>await Work(Localization.Text("Подключение сохранено"),()=>{RequireProject();Room.Join(settings.Project,Invite.Password,settings.Player);Invite.Clear();Log(Localization.Text("Режим гостя сохранён для твоего ника: ")+settings.Player);return Task.CompletedTask;});
  async void Solo(object s,RoutedEventArgs e)=>await Work(Localization.Text("Одиночный режим"),()=>{RequireProject();Room.Off(settings.Project);return Task.CompletedTask;});
  void RequireProject(){if(!Paths.Project(settings.Project))throw new InvalidOperationException(Localization.Text("Сначала скачай проект в разделе установки."));}
  async void Launch(object s,RoutedEventArgs e)=>await Work(Localization.Text("Мост работает"),async()=>{RequireProject();if(!File.Exists(Path.Combine(settings.Project,"backups","passthrough-install.json")))throw new InvalidOperationException(Localization.Text("Сначала установи мод."));Show("Logs");await new Bootstrap(settings,Downloader(),Log).LaunchRunner().Run("powershell.exe","-NoProfile","-ExecutionPolicy","Bypass","-File",Path.Combine(settings.Project,"Launch-Minecraft.ps1"),"-Game",settings.Game,"-Map",settings.Map,"-Width",settings.Width.ToString(),"-Height",settings.Height.ToString(),"-Borderless");});
  static void Open(string target)=>Process.Start(new ProcessStartInfo(target){UseShellExecute=true});
  void GitHub(object s,RoutedEventArgs e)=>Open("https://github.com/Rizen1322/l4d2-minecraft");
  void Authoring(object s,RoutedEventArgs e)=>Open("steam://install/563");
  void OpenMinecraft(object s,RoutedEventArgs e){var legacy=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),@".tlauncher\legacy\Minecraft\LL.exe");if(File.Exists(legacy))Open(legacy);else if(Directory.Exists(MinecraftPath.Text))Open(MinecraftPath.Text);else Status.Text=Localization.Text("Укажи папку Minecraft в разделе установки.");}
  void OpenLog(object s,RoutedEventArgs e){if(File.Exists(logPath))Open(logPath);}
  void Preview(object s,RoutedEventArgs e){var args=Environment.GetCommandLineArgs();if(args.Length>=3&&args[1]=="--preview"){if(args.Length>=4)ApplyLanguage(args[3]);if(args.Length>=5)Show(args[4]);Dispatcher.BeginInvoke(new Action(()=>{UpdateLayout();var visual=(FrameworkElement)Content;var bmp=new RenderTargetBitmap((int)visual.ActualWidth,(int)visual.ActualHeight,96,96,PixelFormats.Pbgra32);bmp.Render(visual);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bmp));using(var stream=File.Create(args[2]))png.Save(stream);Close();}),System.Windows.Threading.DispatcherPriority.ApplicationIdle);}}
 }
}
