using System;
using System.Net;
using System.Windows;
namespace L4D2MC.Companion {
    public partial class App : Application {
        protected override void OnStartup(StartupEventArgs e) {
            ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
            DispatcherUnhandledException+=(s,a)=>{MessageBox.Show(a.Exception.Message,"L4D2MC",MessageBoxButton.OK,MessageBoxImage.Error);a.Handled=true;};
            base.OnStartup(e);
        }
    }
}
