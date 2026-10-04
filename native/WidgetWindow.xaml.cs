using System;
using System.Diagnostics;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Forms = System.Windows.Forms;

namespace TurnTabler;

public partial class WidgetWindow : Window
{
    private sealed class Preferences
    {
        public string Url { get; set; } = "";
        public double Volume { get; set; } = 65;
        public bool Pin { get; set; } = true;
        public bool Rotation { get; set; } = true;
        public bool Effect { get; set; } = true;
        public bool Ambient { get; set; } = true;
        public double LightStrength { get; set; } = 75;
        public int Size { get; set; } = 1;
        public double? Left { get; set; }
        public double? Top { get; set; }
    }

    private readonly Preferences preferences;
    private readonly Forms.NotifyIcon tray;
    private readonly Stopwatch animationClock = Stopwatch.StartNew();
    private readonly DispatcherTimer visualTimer;
    private double previousFrame;
    private bool initialized, browserReady, playing, sampling, closing;
    private bool ambientLayer;
    private int ambientFrames;
    private const double RevolutionSeconds = 24;
    private Window? pageWindow;
    private string lastUrl = "", lastError = "";
    private string currentVideoId = "", currentVideoUrl = "";
    private readonly Stack<string> previousVideos = new();
    private bool navigatingBack;
    private JsonElement lastState;
    private readonly TaskCompletionSource browserInitialized = new();
    private string PreferencesPath => Path.Combine(Program.DataDirectory, "preferences.json");

    public WidgetWindow()
    {
        try { preferences = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(PreferencesPath)) ?? new(); }
        catch { preferences = new(); }
        preferences.Volume = Math.Clamp(preferences.Volume, 0, 100);
        preferences.Size = Math.Clamp(preferences.Size, 0, 2);
        InitializeComponent();
        var artwork = Artwork.Load(); GlassBody.Source = artwork.Body; RecordTexture.Source = artwork.Record; GrooveHighlights.Source = artwork.Highlights;
        Address.Text = preferences.Url;
        Volume.Value = Program.Smoke ? 0 : preferences.Volume;
        PinOption.IsChecked = preferences.Pin; RotationOption.IsChecked = preferences.Rotation;
        EffectOption.IsChecked = preferences.Effect; AmbientOption.IsChecked = preferences.Ambient;
        LightStrength.Value = Math.Clamp(preferences.LightStrength, 0, 100);
        SizeOption.SelectedIndex = preferences.Size;
        initialized = true;
        ApplyOptions(); SetSize();
        if (Program.Smoke) { Left = -10000; Top = -10000; Topmost = false; }
        tray = new Forms.NotifyIcon { Text = "TurnTabler", Icon = System.Drawing.SystemIcons.Application, Visible = true };
        tray.DoubleClick += (_, _) => Dispatcher.Invoke(ShowWidget);
        tray.ContextMenuStrip = new Forms.ContextMenuStrip();
        tray.ContextMenuStrip.Items.Add("위젯 표시", null, (_, _) => Dispatcher.Invoke(ShowWidget));
        tray.ContextMenuStrip.Items.Add("종료", null, (_, _) => Dispatcher.Invoke(Close));
        CompositionTarget.Rendering += Animate;
        visualTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(320) };
        visualTimer.Tick += async (_, _) => await ReflectVideo();
        visualTimer.Start();
        Loaded += async (_, _) =>
        {
            if (!Program.Smoke) Dock();
            if (!Program.Smoke && preferences.Left.HasValue && preferences.Top.HasValue)
            {
                Left = preferences.Left.Value; Top = preferences.Top.Value;
                var area = WorkArea();
                Left = Math.Clamp(Left, area.Left, Math.Max(area.Left, area.Right - Width));
                Top = Math.Clamp(Top, area.Top, Math.Max(area.Top, area.Bottom - Height));
            }
            await InitializeBrowser();
            if (Program.Smoke) await SmokeChecks();
            else
            {
                var link = Program.Arguments.FirstOrDefault(arg => arg.StartsWith("https://", StringComparison.OrdinalIgnoreCase));
                if (link != null) { Address.Text = link; await LoadAddress(); }
            }
        };
        Closed += (_, _) =>
        {
            closing = true; Save(); visualTimer.Stop(); CompositionTarget.Rendering -= Animate;
            pageWindow?.Close(); Browser.Dispose(); tray.Dispose();
        };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) SettingsPanel.Visibility = Visibility.Collapsed; };
    }

    private async Task InitializeBrowser()
    {
        try
        {
            var environment = await CoreWebView2Environment.CreateAsync(null, Path.Combine(Program.DataDirectory, "WebView2"),
                new CoreWebView2EnvironmentOptions("--autoplay-policy=no-user-gesture-required"));
            await Browser.EnsureCoreWebView2Async(environment);
            var core = Browser.CoreWebView2;
            core.Settings.AreDefaultContextMenusEnabled = true;
            core.Settings.AreDevToolsEnabled = Program.Smoke;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.IsZoomControlEnabled = false;
            core.Settings.AreBrowserAcceleratorKeysEnabled = false;
            core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
            core.NewWindowRequested += (_, e) =>
            {
                e.Handled = true;
                if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) && uri.Scheme == "https")
                    Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
            };
            core.NavigationStarting += (_, e) =>
            {
                if (!Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
                    !(uri.Host == "www.youtube.com" || uri.Host == "accounts.google.com" || uri.Host == "consent.youtube.com" || uri.Host == "consent.google.com"))
                    e.Cancel = true;
            };
            core.WebMessageReceived += ReceiveState;
            core.NavigationCompleted += async (_, e) =>
            {
                if (!e.IsSuccess) { playing = false; Notice("유튜브 페이지를 열지 못했습니다: " + e.WebErrorStatus); return; }
                await Execute("window.turntablerNative?.setVolume(" + Volume.Value.ToString(System.Globalization.CultureInfo.InvariantCulture) + "); window.turntablerNative?.setWidgetMode(" + (pageWindow == null ? "true" : "false") + ")");
                if (!YouTubeAddress.IsYouTubePage(core.Source)) Notice("설정의 ‘유튜브 페이지 보기’에서 로그인 또는 동의를 진행하세요.");
            };
            core.ProcessFailed += (_, e) => { playing = false; Notice("재생 프로세스가 종료되었습니다. 링크를 다시 실행해 주세요."); };
            var bridge = BundledAssets.ReadText("YouTubeBridge.js");
            await core.AddScriptToExecuteOnDocumentCreatedAsync("window.__turntablerInitialVolume=" + Volume.Value.ToString(System.Globalization.CultureInfo.InvariantCulture) + ";\n" + bridge);
            browserReady = true; browserInitialized.TrySetResult();
        }
        catch (Exception error) { Notice("영상 엔진을 시작하지 못했습니다: " + error.Message); browserInitialized.TrySetException(error); }
    }

    private void ReceiveState(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        if (!YouTubeAddress.IsYouTubePage(e.Source)) return;
        try
        {
            using var doc = JsonDocument.Parse(e.WebMessageAsJson);
            var state = doc.RootElement;
            string type = state.GetProperty("type").GetString() ?? "";
            if (type == "notice") { Notice(state.GetProperty("message").GetString() ?? ""); return; }
            if (type != "state") return;
            lastState = state.Clone();
            playing = state.GetProperty("playing").GetBoolean();
            bool hasVideo = state.GetProperty("hasVideo").GetBoolean();
            VideoViewbox.Opacity = hasVideo ? (preferences.Effect ? .67 : .85) : 0;
            Play.Content = playing ? "Ⅱ" : "▶";
            TrackTitle.Text = state.GetProperty("title").GetString();
            Previous.IsEnabled = previousVideos.Count > 0 || state.GetProperty("hasPrevious").GetBoolean();
            Next.IsEnabled = state.GetProperty("hasNext").GetBoolean();
            string error = state.GetProperty("error").GetString() ?? "";
            if (error.Length > 0) Notice(error.Length > 180 ? error[..180] : error);
            else if (hasVideo) Notice("");
            else if (state.GetProperty("needsPage").GetBoolean()) Notice("설정의 ‘유튜브 페이지 보기’에서 안내를 확인해 주세요.");
            string url = state.GetProperty("url").GetString() ?? "";
            string videoId = state.GetProperty("videoId").GetString() ?? "";
            if (hasVideo && videoId.Length == 11 && videoId != currentVideoId && url.Contains("v=" + videoId))
            {
                if (currentVideoUrl.Length > 0 && !navigatingBack) previousVideos.Push(currentVideoUrl);
                navigatingBack = false; currentVideoId = videoId; currentVideoUrl = url;
                Previous.IsEnabled = previousVideos.Count > 0 || state.GetProperty("hasPrevious").GetBoolean();
            }
            if (url != lastUrl && YouTubeAddress.IsYouTubePage(url))
            {
                lastUrl = url;
                try { preferences.Url = YouTubeAddress.Parse(url).AbsoluteUri; Save(); } catch (ArgumentException) { }
            }
        }
        catch (JsonException) { }
        catch (InvalidOperationException) { }
    }

    private async Task LoadAddress()
    {
        try
        {
            var uri = YouTubeAddress.Parse(Address.Text);
            Notice("유튜브를 불러오는 중…");
            await browserInitialized.Task;
            playing = false; VideoViewbox.Opacity = 0; Previous.IsEnabled = Next.IsEnabled = false;
            preferences.Url = uri.AbsoluteUri; Save();
            Browser.CoreWebView2.Navigate(uri.AbsoluteUri);
            SettingsPanel.Visibility = Visibility.Collapsed;
        }
        catch (ArgumentException error) { Notice(error.Message); }
        catch (Exception error) { Notice("재생을 시작하지 못했습니다: " + error.Message); }
    }

    private async Task Execute(string script)
    {
        if (!browserReady || closing) return;
        try { await Browser.CoreWebView2.ExecuteScriptAsync(script); }
        catch (Exception error) when (error is InvalidOperationException || error is System.Runtime.InteropServices.COMException) { Notice("재생 페이지가 준비되면 다시 눌러 주세요."); }
    }
    private async void SubmitAddress(object sender, RoutedEventArgs e) => await LoadAddress();
    private async void AddressKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Enter) { e.Handled = true; await LoadAddress(); } }
    private async void TogglePlayback(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (string.IsNullOrEmpty(lastUrl)) { if (Address.Text.Length > 0) await LoadAddress(); return; }
        await Execute("window.turntablerNative?.toggle()");
    }
    private async void PreviousTrack(object sender, RoutedEventArgs e)
    {
        if (previousVideos.TryPop(out string? previous)) { navigatingBack = true; playing = false; Browser.CoreWebView2.Navigate(previous); }
        else await Execute("window.turntablerNative?.previous()");
    }
    private async void NextTrack(object sender, RoutedEventArgs e) => await Execute("window.turntablerNative?.next()");
    private async void ChangeVolume(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!initialized) return;
        preferences.Volume = Volume.Value; Save();
        await Execute("window.turntablerNative?.setVolume(" + Volume.Value.ToString(System.Globalization.CultureInfo.InvariantCulture) + ")");
    }
    private void Notice(string text)
    {
        lastError = text; StatusText.Text = text; StatusBox.Visibility = text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
    }
    private void Animate(object? sender, EventArgs e)
    {
        double now = animationClock.Elapsed.TotalSeconds;
        double elapsed = Math.Min(.1, now - previousFrame); previousFrame = now;
        if (playing && preferences.Rotation && IsVisible)
        {
            RecordRotation.Angle = (RecordRotation.Angle + elapsed * (360 / RevolutionSeconds)) % 360;
            GrooveRotation.Angle = RecordRotation.Angle;
        }
    }
    private async Task ReflectVideo()
    {
        if (!playing || !preferences.Ambient || sampling || !browserReady || !IsVisible || closing || pageWindow != null) return;
        sampling = true;
        try
        {
            using var stream = new MemoryStream();
            await Browser.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, stream);
            stream.Position = 0;
            var image = new BitmapImage(); image.BeginInit(); image.StreamSource = stream; image.CacheOption = BitmapCacheOption.OnLoad; image.DecodePixelWidth = 80; image.EndInit(); image.Freeze();
            var front = ambientLayer ? AmbientA : AmbientB;
            var back = ambientLayer ? AmbientB : AmbientA;
            front.Source = image;
            front.BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(300)));
            back.BeginAnimation(OpacityProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(300)));
            ambientLayer = !ambientLayer; ambientFrames++;
        }
        catch (Exception) when (!closing) { }
        finally { sampling = false; }
    }
    private void ToggleSettings(object sender, RoutedEventArgs e) { e.Handled = true; SettingsPanel.Visibility = SettingsPanel.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible; }
    private void OptionsChanged(object sender, RoutedEventArgs e)
    {
        if (!initialized) return;
        preferences.Pin = PinOption.IsChecked == true; preferences.Rotation = RotationOption.IsChecked == true;
        preferences.Effect = EffectOption.IsChecked == true; preferences.Ambient = AmbientOption.IsChecked == true;
        ApplyOptions(); Save();
    }
    private void ApplyOptions() { Topmost = preferences.Pin; Film.Visibility = preferences.Effect ? Visibility.Visible : Visibility.Collapsed; Ambient.Visibility = preferences.Ambient ? Visibility.Visible : Visibility.Collapsed; Ambient.Opacity = preferences.LightStrength / 100; }
    private void LightStrengthChanged(object sender, RoutedPropertyChangedEventArgs<double> e) { if (!initialized) return; preferences.LightStrength = LightStrength.Value; Ambient.Opacity = preferences.LightStrength / 100; Save(); }
    private void WidgetSizeChanged(object sender, SelectionChangedEventArgs e) { if (!initialized) return; preferences.Size = SizeOption.SelectedIndex; SetSize(); Dock(); Save(); }
    private void SetSize() { double scale = new[] { .8, 1, 1.2 }[preferences.Size]; Width = 460 * scale; Height = 414 * scale; WidgetScale.Width = Width; WidgetScale.Height = Height; }
    private Rect WorkArea()
    {
        var display = Forms.Screen.FromHandle(new WindowInteropHelper(this).Handle).WorkingArea;
        var source = PresentationSource.FromVisual(this);
        var transform = source?.CompositionTarget?.TransformFromDevice ?? Matrix.Identity;
        return new Rect(transform.Transform(new Point(display.Left, display.Top)), transform.Transform(new Point(display.Right, display.Bottom)));
    }
    private void Dock() { var area = WorkArea(); Left = area.Right - Width - 16; Top = Math.Max(area.Top, area.Bottom - Height - 16); }
    private void DockWidget(object sender, RoutedEventArgs e) { Dock(); preferences.Left = Left; preferences.Top = Top; Save(); }
    private void DragWidget(object sender, MouseButtonEventArgs e)
    {
        if (e.Handled || e.ChangedButton != MouseButton.Left) return;
        DependencyObject? target = e.OriginalSource as DependencyObject;
        while (target != null && target != Deck) { if (target is Button || target is Slider) return; target = VisualTreeHelper.GetParent(target); }
        try { DragMove(); preferences.Left = Left; preferences.Top = Top; Save(); } catch (InvalidOperationException) { }
    }
    private void HideWidget(object sender, RoutedEventArgs e) { SettingsPanel.Visibility = Visibility.Collapsed; Hide(); }
    private void ShowWidget() { Show(); WindowState = WindowState.Normal; Activate(); }
    private void CloseWidget(object sender, RoutedEventArgs e) => Close();
    private void Save()
    {
        if (!initialized) return;
        try { File.WriteAllText(PreferencesPath + ".tmp", JsonSerializer.Serialize(preferences)); File.Move(PreferencesPath + ".tmp", PreferencesPath, true); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
    private async void OpenYouTubePage(object sender, RoutedEventArgs e)
    {
        if (pageWindow != null) { pageWindow.Activate(); return; }
        if (!browserReady || string.IsNullOrEmpty(Browser.CoreWebView2.Source) || Browser.CoreWebView2.Source == "about:blank") { Notice("먼저 유튜브 링크를 입력해 주세요."); return; }
        SettingsPanel.Visibility = Visibility.Collapsed;
        await Execute("window.turntablerNative?.setWidgetMode(false)");
        VideoViewbox.Child = null;
        Browser.Width = double.NaN; Browser.Height = double.NaN;
        pageWindow = new Window { Title = "YouTube · TurnTabler", Width = 1100, Height = 760, Content = Browser, WindowStartupLocation = WindowStartupLocation.CenterScreen, Background = Brushes.Black };
        if (Program.Smoke) { pageWindow.WindowStartupLocation = WindowStartupLocation.Manual; pageWindow.Left = -10000; pageWindow.Top = -10000; pageWindow.ShowInTaskbar = false; }
        pageWindow.Closed += async (_, _) =>
        {
            pageWindow.Content = null; pageWindow = null;
            if (closing) return;
            Browser.Width = 960; Browser.Height = 540; VideoViewbox.Child = Browser;
            await Execute("window.turntablerNative?.setWidgetMode(true)");
        };
        pageWindow.Show();
    }

    private void Capture(string name)
    {
        var output = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../artifacts/native"));
        // Smoke output is explicitly supplied by the test runner, outside the user's profile.
        output = Environment.GetEnvironmentVariable("TURNTABLER_ARTIFACTS") ?? output;
        Directory.CreateDirectory(output);
        var image = new RenderTargetBitmap((int)Math.Ceiling(Width), (int)Math.Ceiling(Height), 96, 96, PixelFormats.Pbgra32);
        image.Render(this); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
        using var stream = File.Create(Path.Combine(output, name + ".png")); encoder.Save(stream);
    }
    private async Task Until(Func<bool> condition, string description, int timeout = 45000)
    {
        var timer = Stopwatch.StartNew();
        while (!condition()) { if (timer.ElapsedMilliseconds > timeout) throw new Exception(description + ": " + lastError + "; " + lastState); await Task.Delay(300); }
    }
    private async Task SmokeChecks()
    {
        var output = Environment.GetEnvironmentVariable("TURNTABLER_ARTIFACTS") ?? Path.Combine(Program.DataDirectory, "artifacts");
        Directory.CreateDirectory(output);
        try
        {
            await browserInitialized.Task;
            File.Delete(Path.Combine(output, "failure.json"));
            File.Delete(Path.Combine(output, "verification.json"));
            Capture("idle");
            Background = new SolidColorBrush(Color.FromRgb(65, 79, 95));
            await Task.Delay(150);
            Capture("idle-on-background");
            Background = Brushes.Transparent;
            Address.Text = "https://www.youtube.com/watch?v=2qfoSxRRCJc&list=RD2qfoSxRRCJc&index=1";
            await LoadAddress();
            await Until(() => playing && lastState.GetProperty("videoId").GetString() == "2qfoSxRRCJc", "요청 영상 재생");
            var startedAt = lastState.GetProperty("time").GetDouble();
            await Task.Delay(2300);
            if (lastState.GetProperty("time").GetDouble() <= startedAt + 1) throw new Exception("영상 시간이 진행되지 않음");
            var angle = RecordRotation.Angle; await Task.Delay(250);
            double angleDelta = (RecordRotation.Angle - angle + 360) % 360;
            if (angleDelta < 1 || angleDelta > 8) throw new Exception("느린 레코드 회전 속도 확인 실패: " + angleDelta);
            await Until(() => ambientFrames > 3, "영상 색 퍼짐");
            var recordCenter = Record.TransformToAncestor(Deck).Transform(new Point(Record.ActualWidth / 2, Record.ActualHeight / 2));
            var videoCenter = Browser.TransformToAncestor(Deck).Transform(new Point(Browser.ActualWidth / 2, Browser.ActualHeight / 2));
            double centerOffset = (recordCenter - videoCenter).Length;
            if (centerOffset > .01) throw new Exception("영상/레코드 중심 불일치: " + centerOffset);
            var videoGeometry = await Browser.CoreWebView2.ExecuteScriptAsync("(()=>{const v=document.querySelector('video'),r=v.getBoundingClientRect();return {offsetX:r.x+r.width/2-innerWidth/2,offsetY:r.y+r.height/2-innerHeight/2,position:getComputedStyle(v).objectPosition}})()");
            using (var geometry = JsonDocument.Parse(videoGeometry))
            {
                if (Math.Abs(geometry.RootElement.GetProperty("offsetX").GetDouble()) > 1 || Math.Abs(geometry.RootElement.GetProperty("offsetY").GetDouble()) > 1) throw new Exception("유튜브 영상 중심 불일치: " + videoGeometry);
            }
            var ambientCapture = new RenderTargetBitmap(440, 294, 96, 96, PixelFormats.Pbgra32); ambientCapture.Render(Ambient);
            var ambientPixels = new byte[440 * 294 * 4]; ambientCapture.CopyPixels(ambientPixels, 440 * 4, 0);
            int outsideGlowPixels = 0, insideGlowPixels = 0;
            var edgeTolerance = new Pen(Brushes.White, 2);
            for (int y = 0; y < 294; y++) for (int x = 0; x < 440; x++)
            {
                var point = new Point(x + .5, y + .5);
                if (ambientPixels[(y * 440 + x) * 4 + 3] == 0) continue;
                if (Ambient.Clip.FillContains(point)) insideGlowPixels++;
                else if (!Ambient.Clip.StrokeContains(edgeTolerance, point)) outsideGlowPixels++;
            }
            if (outsideGlowPixels != 0 || insideGlowPixels < 1000) throw new Exception("받침대 반사광 경계 확인 실패: outside=" + outsideGlowPixels + ", inside=" + insideGlowPixels);
            Capture("playing");
            Background = new SolidColorBrush(Color.FromRgb(65, 79, 95));
            await Task.Delay(150);
            Capture("playing-on-background");
            Background = Brushes.Transparent;
            var playback = lastState.Clone();
            await Execute("window.turntablerNative.pause()");
            await Until(() => !playing, "일시정지");
            angle = RecordRotation.Angle; await Task.Delay(250);
            if (angle != RecordRotation.Angle) throw new Exception("일시정지 중 레코드가 회전함");
            Volume.Value = 23;
            await Until(() => lastState.GetProperty("volume").GetInt32() == 23, "볼륨 반영");
            Volume.Value = 0;
            SettingsPanel.Visibility = Visibility.Visible; await Task.Delay(200); Capture("settings");
            SettingsPanel.Visibility = Visibility.Collapsed;
            await Execute("window.turntablerNative.play()"); await Until(() => playing, "재생 재개");
            await Until(() => lastState.GetProperty("playlistCount").GetInt32() > 1 && Next.IsEnabled, "믹스 목록 불러오기");
            await Execute("window.turntablerNative.next()");
            await Until(() => playing && lastState.GetProperty("videoId").GetString() != "2qfoSxRRCJc", "다음 곡");
            PreviousTrack(this, new RoutedEventArgs());
            await Until(() => playing && lastState.GetProperty("videoId").GetString() == "2qfoSxRRCJc", "이전 곡");
            preferences.Rotation = false; angle = RecordRotation.Angle; await Task.Delay(250);
            if (angle != RecordRotation.Angle) throw new Exception("회전 설정 끄기 실패");
            preferences.Rotation = true;
            OpenYouTubePage(this, new RoutedEventArgs());
            await Until(() => pageWindow != null, "원래 유튜브 페이지 보기");
            await Task.Delay(600);
            pageWindow!.Close();
            await Until(() => pageWindow == null && VideoViewbox.Child == Browser, "위젯으로 돌아오기");
            await Execute("window.turntablerNative.play()"); await Until(() => playing, "페이지 복귀 후 재생");
            if (AllowsTransparency != true || WindowStyle != WindowStyle.None || ShowInTaskbar != false) throw new Exception("네이티브 위젯 창 속성 실패");
            var report = new { success = true, engine = "WPF + Windows WebView2", source = Browser.CoreWebView2.Source, playback, nativeRecordRotated = true, pauseStoppedRecord = true, volumeVerified = true, playlistNavigation = true, originalPageRoundTrip = true, rotationOptionVerified = true, projectionCoverage = Projection.Width / Record.Width, projectionOpacity = VideoViewbox.Opacity, ambientFrames, revolutionSeconds = RevolutionSeconds, centerOffset, videoGeometry, outsideGlowPixels, insideGlowPixels };
            File.WriteAllText(Path.Combine(output, "verification.json"), JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
            Application.Current.Shutdown(0);
        }
        catch (Exception error)
        {
            Capture("failure");
            string page = "";
            try { page = await Browser.CoreWebView2.ExecuteScriptAsync("JSON.stringify({url:location.href,title:document.title,text:document.body?.innerText?.slice(0,4000),player:!!document.getElementById('movie_player'),bridge:!!window.turntablerNative})"); } catch { }
            File.WriteAllText(Path.Combine(output, "failure.json"), JsonSerializer.Serialize(new { error = error.ToString(), lastState, page }, new JsonSerializerOptions { WriteIndented = true }));
            Application.Current.Shutdown(1);
        }
    }
}
