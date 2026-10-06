using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;

namespace TurnTabler;

public partial class WidgetWindow
{
    public sealed record AudioOutputDevice(string Id, string Name);
    private List<AudioOutputDevice> audioOutputs = new() { new("", "시스템 기본 장치") };
    private bool updatingOutputs, outputSelectionAvailable, skipInputPending;
    private string outputStatus = "TurnTabler 소리에만 적용됩니다.";

    private async Task RefreshAudioOutputs()
    {
        if (!browserReady) return;
        if (string.IsNullOrEmpty(Browser.CoreWebView2.Source) || Browser.CoreWebView2.Source == "about:blank")
        {
            Browser.CoreWebView2.Navigate("https://www.youtube.com/");
            return;
        }
        await Execute("window.turntablerNative?.listAudioOutputs()");
    }
    private void UpdateAudioOutputList()
    {
        if (settingsWindow == null) return;
        updatingOutputs = true;
        try
        {
            settingsWindow.AudioOutput.ItemsSource = audioOutputs;
            settingsWindow.AudioOutput.SelectedValue = audioOutputs.Any(d => d.Id == preferences.OutputDevice) ? preferences.OutputDevice : "";
            settingsWindow.AudioOutput.IsEnabled = outputSelectionAvailable;
            settingsWindow.AudioOutputStatus.Text = outputSelectionAvailable ? outputStatus : "출력 장치 선택을 준비할 수 없습니다. 앱을 다시 실행해 주세요.";
        }
        finally { updatingOutputs = false; }
    }
    private void ReceiveAudioState(JsonElement state)
    {
        switch (state.GetProperty("type").GetString())
        {
            case "audio-devices":
                var devices = new List<AudioOutputDevice> { new("", "시스템 기본 장치") };
                foreach (var entry in state.GetProperty("devices").EnumerateArray())
                {
                    string id = entry.GetProperty("id").GetString() ?? "";
                    if (id.Length > 0 && id != "default" && id != "communications" && !devices.Any(d => d.Id == id))
                        devices.Add(new(id, entry.GetProperty("name").GetString() ?? "오디오 출력 장치"));
                }
                audioOutputs = devices;
                UpdateAudioOutputList();
                break;
            case "audio-output":
                if (!state.GetProperty("ok").GetBoolean()) break;
                preferences.OutputDevice = state.GetProperty("deviceId").GetString() ?? "";
                Save();
                outputStatus = state.TryGetProperty("fallback", out var fallback) && fallback.GetBoolean()
                    ? "선택한 장치가 없어 시스템 기본 장치로 전환했습니다."
                    : "TurnTabler 소리에만 적용됩니다.";
                UpdateAudioOutputList();
                break;
            case "audio-error":
                outputStatus = state.GetProperty("message").GetString() ?? "출력 장치를 변경하지 못했습니다.";
                LogPlayback("audio-error", outputStatus);
                UpdateAudioOutputList();
                break;
        }
    }
    private async Task SkipAdWithInput()
    {
        if (skipInputPending || closing || !browserReady) return;
        skipInputPending = true;
        try
        {
            // Revalidate the actual live ad button; never accept coordinates from a page message.
            using var target = JsonDocument.Parse(await Browser.CoreWebView2.ExecuteScriptAsync("window.turntablerNative?.skipTarget() || null"));
            if (target.RootElement.ValueKind != JsonValueKind.Object) return;
            double x = target.RootElement.GetProperty("x").GetDouble(), y = target.RootElement.GetProperty("y").GetDouble();
            if (!double.IsFinite(x) || !double.IsFinite(y) || x < 0 || y < 0 || x > Browser.ActualWidth || y > Browser.ActualHeight) return;
            foreach (string type in new[] { "mousePressed", "mouseReleased" })
                await Browser.CoreWebView2.CallDevToolsProtocolMethodAsync("Input.dispatchMouseEvent", JsonSerializer.Serialize(new { type, x, y, button = "left", clickCount = 1 }));
            LogPlayback("ad-native-click", "sent");
        }
        catch (Exception error) { LogPlayback("ad-native-click", error.Message); }
        finally { skipInputPending = false; }
    }
    private static void LogPlayback(string kind, string message)
    {
        try
        {
            string path = Path.Combine(Program.DataDirectory, "playback.log");
            if (File.Exists(path) && new FileInfo(path).Length > 262144) File.Move(path, path + ".previous", true);
            File.AppendAllText(path, JsonSerializer.Serialize(new { time = DateTime.UtcNow, kind, message = message.Length > 1500 ? message[..1500] : message }) + Environment.NewLine);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
