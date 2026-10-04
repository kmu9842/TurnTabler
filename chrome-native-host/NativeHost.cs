using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web;
using System.Web.Script.Serialization;
using System.Windows.Automation;
using System.Windows.Forms;

[assembly: AssemblyTitle("TurnTabler Chrome Host")]
[assembly: AssemblyProduct("TurnTabler Chrome Host")]
[assembly: AssemblyVersion("1.2.0.0")]
internal static class NativeHost
{
    internal const string ExtensionId = "ebnjhkdpohpgeipkalbfklpfibjadnhd";
    const string Origin = "chrome-extension://" + ExtensionId + "/";
    const int Limit = 16384;
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = Limit, RecursionLimit = 12 };
    static readonly string Config = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "settings.json");
    static bool Smoke { get { return Environment.GetEnvironmentVariable("TURNTABLER_BROWSER_SMOKE") == "1"; } }
    static string PipeName { get { return "TurnTabler.Browser." + WindowsIdentity.GetCurrent().User.Value + "." + Process.GetCurrentProcess().SessionId + (Smoke ? ".BrowserSmoke" : ""); } }

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--validate")
        {
            try { WritePlain(Console.OpenStandardOutput(), Json.Serialize(ValidatePath(args[1]))); return 0; }
            catch (Exception e) { WritePlain(Console.OpenStandardError(), e.Message); return 1; }
        }
        object reply;
        try
        {
            if (args.Length == 0 || args[0] != Origin) throw new ArgumentException("허용되지 않은 확장 프로그램입니다.");
            var read = Task.Run(() => Read(Console.OpenStandardInput()));
            if (!read.Wait(10000)) throw new IOException("요청을 읽는 시간이 초과되었습니다.");
            var request = read.Result;
            string action = Text(request, "action");
            switch (action)
            {
                case "ping": case "getSettings": reply = Settings(); break;
                case "setPath": reply = SavePath(Text(request, "appPath")); break;
                case "choosePath":
                    using (var dialog = new OpenFileDialog())
                    {
                        dialog.Title = "TurnTabler.exe 선택 (2.1.2 이상)";
                        dialog.Filter = "TurnTabler (TurnTabler.exe)|TurnTabler.exe";
                        string previous = ConfiguredPath();
                        if (File.Exists(previous)) { dialog.InitialDirectory = Path.GetDirectoryName(previous); dialog.FileName = previous; }
                        long parent = 0;
                        foreach (string arg in args.Skip(1))
                            if (arg.StartsWith("--parent-window=")) long.TryParse(arg.Substring(16), out parent);
                        reply = dialog.ShowDialog(new Owner(new IntPtr(parent))) == DialogResult.OK
                            ? SavePath(dialog.FileName) : new Dictionary<string, object> { { "ok", true }, { "cancelled", true }, { "protocol", 1 } };
                    }
                    break;
                case "play": reply = Play(Normalize(Text(request, "url"))); break;
                default: throw new ArgumentException("지원하지 않는 요청입니다.");
            }
        }
        catch (Exception e)
        {
            while (e is AggregateException && e.InnerException != null) e = e.InnerException;
            reply = new { ok = false, protocol = 1, error = e.Message };
        }
        try { Write(Console.OpenStandardOutput(), reply); return 0; }
        catch (IOException) { return 1; }
    }

    sealed class Owner : IWin32Window
    {
        public IntPtr Handle { get; private set; }
        internal Owner(IntPtr handle) { Handle = handle; }
    }
    static string Text(Dictionary<string, object> request, string key)
    {
        object value;
        return request != null && request.TryGetValue(key, out value) ? value as string : null;
    }
    static string ConfiguredPath()
    {
        if (!File.Exists(Config)) return "";
        return Text(Json.Deserialize<Dictionary<string, object>>(File.ReadAllText(Config, Encoding.UTF8)), "appPath") ?? "";
    }
    static Dictionary<string, object> ValidatePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) throw new ArgumentException("TurnTabler.exe 경로를 지정해 주세요.");
        path = path.Trim().Trim('"');
        if (!Path.IsPathRooted(path)) throw new ArgumentException("TurnTabler.exe의 전체 경로를 입력해 주세요.");
        path = Path.GetFullPath(path);
        if (!File.Exists(path)) throw new FileNotFoundException("EXE를 찾을 수 없습니다. 설정에서 경로를 다시 지정해 주세요.", path);
        if (!string.Equals(Path.GetFileName(path), "TurnTabler.exe", StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("TurnTabler.exe를 선택해 주세요.");
        var info = FileVersionInfo.GetVersionInfo(path);
        var version = new Version(info.FileMajorPart, info.FileMinorPart, info.FileBuildPart, info.FilePrivatePart);
        if (info.ProductName != "TurnTabler" || info.OriginalFilename != "TurnTabler.dll") throw new ArgumentException("TurnTabler 배포 EXE가 아닙니다.");
        if (version < new Version(2, 1, 2, 0)) throw new ArgumentException("TurnTabler 2.1.2 이상이 필요합니다. 선택한 파일: " + version);
        return new Dictionary<string, object> { { "ok", true }, { "protocol", 1 }, { "appPath", path }, { "appVersion", version.ToString() }, { "available", true } };
    }
    static object Settings()
    {
        string path = ConfiguredPath();
        try { return ValidatePath(path); }
        catch (Exception e) { return new { ok = true, protocol = 1, appPath = path, available = false, error = e.Message }; }
    }
    static object SavePath(string path)
    {
        var info = ValidatePath(path);
        string temporary = Config + "." + Guid.NewGuid().ToString("N") + ".tmp";
        File.WriteAllText(temporary, Json.Serialize(new { appPath = info["appPath"] }), new UTF8Encoding(false));
        try
        {
            if (File.Exists(Config)) File.Replace(temporary, Config, null);
            else File.Move(temporary, Config);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
        return info;
    }

    static object Play(string url)
    {
        var info = ValidatePath(ConfiguredPath());
        string executable = (string)info["appPath"];
        // Serialize simultaneous clicks without changing another process's input midway.
        using (var mutex = new Mutex(false, "Local\\" + PipeName + ".ChromeRequests"))
        {
            bool acquired;
            try { acquired = mutex.WaitOne(45000); }
            catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) throw new IOException("이전 재생 요청이 진행 중입니다. 잠시 후 다시 시도해 주세요.");
            try
            {
                var running = FindApp(executable);
                if (running == null)
                {
                    var start = new ProcessStartInfo(executable) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(executable) };
                    if (Smoke) start.Arguments = "--browser-smoke";
                    using (var launched = Process.Start(start)) { }
                }
                var watch = Stopwatch.StartNew();
                bool restoreRequested = false;
                while (watch.ElapsedMilliseconds < 35000)
                {
                    if (running == null) running = FindApp(executable);
                    if (running != null)
                    {
                        using (var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut, PipeOptions.Asynchronous))
                        {
                            bool connected = false;
                            try { pipe.Connect(150); connected = true; } catch (TimeoutException) { }
                            if (connected)
                            {
                                // New apps expose a pipe. Released 2.1.2–2.1.4 use the UI adapter below.
                                Write(pipe, new { action = "play", url = url });
                                var read = Task.Run(() => Read(pipe));
                                if (!read.Wait(30000)) throw new IOException("TurnTabler가 응답하지 않습니다.");
                                return read.Result;
                            }
                        }
                        IntPtr handle = FindWindow(running.Id);
                        if (handle != IntPtr.Zero)
                        {
                            if (!restoreRequested)
                            {
                                RestoreWidget(running.Id);
                                ShowWindowAsync(handle, 9);
                                restoreRequested = true;
                                Thread.Sleep(150);
                            }
                            var window = AutomationElement.FromHandle(handle);
                            var address = window.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.AutomationIdProperty, "Address"));
                            var submit = window.FindFirst(TreeScope.Descendants, new AndCondition(
                                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button),
                                new PropertyCondition(AutomationElement.NameProperty, "↵")));
                            object value, invoke;
                            if (address != null && submit != null && address.Current.IsEnabled && submit.Current.IsEnabled &&
                                address.TryGetCurrentPattern(ValuePattern.Pattern, out value) && submit.TryGetCurrentPattern(InvokePattern.Pattern, out invoke))
                            {
                                ((ValuePattern)value).SetValue(url);
                                ((InvokePattern)invoke).Invoke();
                                SetForegroundWindow(handle);
                                return new { ok = true, protocol = 1, url = url, processId = running.Id, appPath = executable, adapter = "windows-automation" };
                            }
                        }
                        if (running.HasExited) { running.Dispose(); running = null; }
                    }
                    Thread.Sleep(200);
                }
                if (running != null) running.Dispose();
                throw new IOException("TurnTabler에 연결하지 못했습니다. 다른 폴더의 TurnTabler가 실행 중이면 종료하거나 확장 설정에서 해당 EXE를 선택해 주세요.");
            }
            finally { mutex.ReleaseMutex(); }
        }
    }
    static Process FindApp(string path)
    {
        foreach (var process in Process.GetProcessesByName("TurnTabler"))
        {
            try
            {
                if (process.SessionId == Process.GetCurrentProcess().SessionId &&
                    string.Equals(process.MainModule.FileName, path, StringComparison.OrdinalIgnoreCase)) return process;
            }
            catch (System.ComponentModel.Win32Exception) { }
            catch (InvalidOperationException) { }
            process.Dispose();
        }
        return null;
    }
    static IntPtr FindWindow(int processId)
    {
        IntPtr result = IntPtr.Zero;
        EnumWindows((handle, state) => {
            uint owner; GetWindowThreadProcessId(handle, out owner);
            if (owner != processId) return true;
            var title = new StringBuilder(256); GetWindowText(handle, title, title.Capacity);
            if (title.ToString() != "TurnTabler") return true;
            result = handle; return false;
        }, IntPtr.Zero);
        return result;
    }
    delegate bool EnumCallback(IntPtr handle, IntPtr state);
    static void RestoreWidget(int processId)
    {
        // WPF Hide() also collapses the managed visual tree. ShowWindow alone
        // cannot restore it. Invoke the released app's existing NotifyIcon
        // double-click callback, which calls ShowWidget on its UI thread.
        // .NET 8 NotifyIcon uses WM_USER + 1024 (0x800); no mouse/keyboard input
        // is injected into other apps, and no clipboard content is changed.
        EnumWindows((handle, state) => {
            uint owner; GetWindowThreadProcessId(handle, out owner);
            if (owner != processId) return true;
            var name = new StringBuilder(256); GetClassName(handle, name, name.Capacity);
            var title = new StringBuilder(256); GetWindowText(handle, title, title.Capacity);
            if (name.ToString().StartsWith("WindowsForms10.Window.0.", StringComparison.Ordinal) && title.Length == 0)
            {
                PostMessage(handle, 0x800, new IntPtr(1), new IntPtr(0x203));
                PostMessage(handle, 0x800, new IntPtr(1), new IntPtr(0x202));
            }
            return true;
        }, IntPtr.Zero);
    }
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumCallback callback, IntPtr state);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr handle, StringBuilder title, int count);
    [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr handle, int command);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr handle);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr handle, StringBuilder name, int count);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);

    static string Normalize(string value)
    {
        Uri uri;
        if (string.IsNullOrWhiteSpace(value) || value.Length > 4096 || !Uri.TryCreate(value, UriKind.Absolute, out uri) ||
            (uri.Scheme != "https" && uri.Scheme != "http") || uri.UserInfo.Length > 0 ||
            !new[] { "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be" }.Contains(uri.Host.ToLowerInvariant()))
            throw new ArgumentException("올바른 유튜브 영상 또는 재생목록 주소를 입력해 주세요.");
        var query = HttpUtility.ParseQueryString(uri.Query);
        var segments = uri.AbsolutePath.Split(new[] { '/' }, StringSplitOptions.RemoveEmptyEntries);
        string video = query["v"], list = query["list"];
        if (uri.Host.EndsWith("youtu.be", StringComparison.OrdinalIgnoreCase)) video = segments.FirstOrDefault();
        else if (segments.Length > 1 && new[] { "shorts", "live", "embed" }.Contains(segments[0])) video = segments[1];
        if ((video != null && !Regex.IsMatch(video, "^[a-zA-Z0-9_-]{11}$")) ||
            (list != null && !Regex.IsMatch(list, "^[a-zA-Z0-9_-]{10,150}$")) || (video == null && list == null)) throw new ArgumentException("영상 또는 재생목록 주소를 확인해 주세요.");
        var parts = new List<string>();
        if (video != null) parts.Add("v=" + video);
        if (list != null) parts.Add("list=" + list);
        int index;
        if (int.TryParse(query["index"], out index) && index > 0) parts.Add("index=" + index);
        string time = query["t"] ?? query["start"];
        if (!string.IsNullOrEmpty(time) && Regex.IsMatch(time, "^(?:[0-9]+|(?:[0-9]+h)?(?:[0-9]+m)?(?:[0-9]+s)?)$")) parts.Add("t=" + time);
        return "https://www.youtube.com/" + (video == null ? "playlist" : "watch") + "?" + string.Join("&", parts);
    }
    static byte[] Exact(Stream stream, int size)
    {
        var bytes = new byte[size];
        for (int count = 0; count < size;)
        {
            int read = stream.Read(bytes, count, size - count);
            if (read == 0) throw new EndOfStreamException("메시지가 중간에 끊어졌습니다.");
            count += read;
        }
        return bytes;
    }
    static Dictionary<string, object> Read(Stream stream)
    {
        int length = BitConverter.ToInt32(Exact(stream, 4), 0);
        if (length <= 0 || length > Limit) throw new InvalidDataException("잘못된 메시지 크기입니다.");
        return Json.Deserialize<Dictionary<string, object>>(new UTF8Encoding(false, true).GetString(Exact(stream, length)));
    }
    static void Write(Stream stream, object reply)
    {
        byte[] body = Encoding.UTF8.GetBytes(Json.Serialize(reply));
        stream.Write(BitConverter.GetBytes(body.Length), 0, 4);
        stream.Write(body, 0, body.Length); stream.Flush();
    }
    static void WritePlain(Stream stream, string value)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(value + Environment.NewLine);
        stream.Write(bytes, 0, bytes.Length); stream.Flush();
    }
}
