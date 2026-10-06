using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using Microsoft.Web.WebView2.Core;

namespace TurnTabler;

public partial class WidgetWindow
{
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
    [DllImport("user32.dll")] private static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X, Y; }

    private async Task InteractionSmokeChecks()
    {
        string output = Environment.GetEnvironmentVariable("TURNTABLER_ARTIFACTS") ?? Path.Combine(Program.DataDirectory, "artifacts");
        Directory.CreateDirectory(output);
        GetCursorPos(out var cursor);
        IntPtr previousForeground = GetForegroundWindow();
        string inputDebug = "";
        int mouseDowns = 0, mouseMoves = 0;
        try
        {
            const string fixture = "https://www.youtube.com/turntabler-input-fixture";
            var core = Browser.CoreWebView2;
            core.AddWebResourceRequestedFilter(fixture, CoreWebView2WebResourceContext.Document);
            core.WebResourceRequested += (_, e) =>
            {
                if (e.Request.Uri != fixture) return;
                const string html = "<!doctype html><html><body style='background:#eee;padding:40px'><button id='probe' style='width:180px;height:60px'>Click test</button><input id='typing' style='display:block;margin-top:40px;width:200px;height:40px'><video></video><script>window.nativeClicks=0;document.querySelector('#probe').onclick=e=>{if(e.isTrusted)window.nativeClicks++};</script></body></html>";
                e.Response = core.Environment.CreateWebResourceResponse(new MemoryStream(Encoding.UTF8.GetBytes(html)), 200, "OK", "Content-Type: text/html; charset=utf-8");
            };
            core.Navigate(fixture);
            await WaitScript("!!document.querySelector('#probe')");
            var handle = new WindowInteropHelper(this).Handle;
            OpenYouTubePage(this, new RoutedEventArgs());
            await Until(() => pageOpen && !openingPage, "브라우저 모드 전환");
            Left = 40; Top = 40; Topmost = true; Show(); Activate(); SetForegroundWindow(handle);
            await Task.Delay(700);
            Browser.PreviewMouseDown += (_, _) => mouseDowns++;
            Browser.PreviewMouseMove += (_, _) => mouseMoves++;
            await core.ExecuteScriptAsync("document.addEventListener('click',e=>window.lastClick={id:e.target.id,x:e.clientX,y:e.clientY,trusted:e.isTrusted},true)");
            if (new WindowInteropHelper(this).Handle != handle) throw new Exception("브라우저 전환으로 HWND가 변경됨");
            await NativeClick("#probe");
            await Task.Delay(200);
            inputDebug = JsonSerializer.Serialize(new { Browser.IsHitTestVisible, Browser.IsVisible, Browser.ActualWidth, Browser.ActualHeight, foreground = GetForegroundWindow().ToInt64(), handle = handle.ToInt64(), mouseDowns, mouseMoves, dom = await core.ExecuteScriptAsync("JSON.stringify({click:window.lastClick,dpi:devicePixelRatio,width:innerWidth})") });
            await WaitScript("window.nativeClicks===1");
            await NativeClick("#typing");
            await core.ExecuteScriptAsync("document.querySelector('#typing').addEventListener('keydown',e=>{if(e.isTrusted&&e.code==='KeyA')window.trustedKey=true})");
            keybd_event(0x41, 0, 0, UIntPtr.Zero); keybd_event(0x41, 0, 2, UIntPtr.Zero);
            await WaitScript("window.trustedKey===true && document.querySelector('#typing').value.length>0");
            string devicesBefore = await core.ExecuteScriptAsync("JSON.stringify({setSinkId:typeof HTMLMediaElement.prototype.setSinkId,selectAudioOutput:typeof navigator.mediaDevices.selectAudioOutput})");
            string permission;
            try
            {
                await core.CallDevToolsProtocolMethodAsync("Browser.setPermission", "{\"permission\":{\"name\":\"speaker-selection\"},\"setting\":\"granted\",\"origin\":\"https://www.youtube.com\"}");
                permission = "granted";
            }
            catch (Exception error) { permission = error.Message; }
            await core.ExecuteScriptAsync("navigator.mediaDevices.enumerateDevices().then(d=>window.outputDevices=d.filter(x=>x.kind==='audiooutput').map(x=>({id:x.deviceId,label:x.label})))");
            await WaitScript("Array.isArray(window.outputDevices)");
            string devices = await core.ExecuteScriptAsync("JSON.stringify(window.outputDevices)");
            CloseYouTubePage(this, new RoutedEventArgs());
            await Task.Delay(500);
            await Execute("window.turntablerNative.listAudioOutputs()");
            await Until(() => audioOutputs.Count > 1, "출력 장치 목록");
            ShowSettings();
            string selectedOutput = audioOutputs[1].Id;
            settingsWindow!.AudioOutput.SelectedValue = selectedOutput;
            await Until(() => preferences.OutputDevice == selectedOutput, "설정에서 출력 장치 적용");
            await WaitScript("document.querySelector('video').sinkId===" + JsonSerializer.Serialize(selectedOutput));
            using (var saved = JsonDocument.Parse(File.ReadAllText(PreferencesPath)))
                if (saved.RootElement.GetProperty("OutputDevice").GetString() != selectedOutput) throw new Exception("출력 장치 저장 실패");
            settingsWindow.Close();
            core.Navigate(fixture);
            await WaitScript("!!document.querySelector('#probe') && document.querySelector('video').sinkId===" + JsonSerializer.Serialize(selectedOutput));
            OpenYouTubePage(this, new RoutedEventArgs());
            await Until(() => pageOpen && !openingPage, "ブラウザ再表示");
            Left = 40; Top = 40; Activate(); SetForegroundWindow(handle);
            await Task.Delay(500); await NativeClick("#probe"); await WaitScript("window.nativeClicks===1");
            Capture("browser-input");
            File.WriteAllText(Path.Combine(output, "interaction-result.json"), JsonSerializer.Serialize(new { success = true, trustedMouseClick = true, keyboardInput = true, repeatedRoundTrip = true, sameWindowHandle = true, outputSelection = true, outputSaved = true, outputAfterNavigation = true, devicesBefore, permission, devices }, new JsonSerializerOptions { WriteIndented = true }));
            closing = true; Application.Current.Shutdown(0);
        }
        catch (Exception error)
        {
            Capture("input-failure");
            File.WriteAllText(Path.Combine(output, "interaction-result.json"), JsonSerializer.Serialize(new { success = false, error = error.ToString(), inputDebug }, new JsonSerializerOptions { WriteIndented = true }));
            closing = true; Application.Current.Shutdown(1);
        }
        finally { SetCursorPos(cursor.X, cursor.Y); SetForegroundWindow(previousForeground); }
    }

    private async Task WaitScript(string expression)
    {
        for (int i = 0; i < 40; i++)
        {
            if (await Browser.CoreWebView2.ExecuteScriptAsync(expression) == "true") return;
            await Task.Delay(150);
        }
        throw new Exception("브라우저 확인 실패: " + expression);
    }
    private async Task NativeClick(string selector)
    {
        string result = await Browser.CoreWebView2.ExecuteScriptAsync("(()=>{const r=document.querySelector(" + JsonSerializer.Serialize(selector) + ").getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()");
        using var data = JsonDocument.Parse(result);
        var point = Browser.PointToScreen(new Point(data.RootElement.GetProperty("x").GetDouble(), data.RootElement.GetProperty("y").GetDouble()));
        SetCursorPos((int)point.X, (int)point.Y); await Task.Delay(80);
        mouse_event(2, 0, 0, 0, UIntPtr.Zero); mouse_event(4, 0, 0, 0, UIntPtr.Zero);
    }
}
