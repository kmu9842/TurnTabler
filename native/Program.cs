using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows;

namespace TurnTabler;

internal static class Program
{
    internal static string DataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TurnTablerNative");
    internal static string[] Arguments = Array.Empty<string>();
    internal static bool Smoke => Arguments.Contains("--smoke");

    [STAThread]
    public static int Main(string[] args)
    {
        Arguments = args;
        if (args.Contains("--self-test")) return SelfTests.Run();
        if (Smoke) DataDirectory = Path.Combine(Path.GetTempPath(), "TurnTablerNative-Smoke");
        Directory.CreateDirectory(DataDirectory);
        using var instance = new Mutex(true, Smoke ? "Local\\TurnTablerNative-Smoke" : "Local\\TurnTablerNative", out bool first);
        if (!first) return 0;
        var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
        app.DispatcherUnhandledException += (_, e) =>
        {
            File.AppendAllText(Path.Combine(DataDirectory, "error.log"), DateTime.Now + " " + e.Exception + Environment.NewLine);
        };
        try { return app.Run(new WidgetWindow()); }
        catch (Exception error)
        {
            File.AppendAllText(Path.Combine(DataDirectory, "error.log"), error + Environment.NewLine);
            MessageBox.Show("위젯을 시작하지 못했습니다.\n" + error.Message, "TurnTabler");
            return 1;
        }
    }
}
