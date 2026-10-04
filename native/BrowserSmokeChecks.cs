using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;

namespace TurnTabler;

public partial class WidgetWindow
{
    private async Task BrowserSmokeChecks()
    {
        var output = Environment.GetEnvironmentVariable("TURNTABLER_ARTIFACTS") ?? Path.Combine(Program.DataDirectory, "artifacts");
        Directory.CreateDirectory(output);
        try
        {
            await Until(() => playing && currentVideoId == "2qfoSxRRCJc", "확장 프로그램 요청으로 앱 실행 및 재생", 60000);
            double firstTime = lastState.GetProperty("time").GetDouble();
            await Until(() => playing && currentVideoId == "2qfoSxRRCJc" && lastState.GetProperty("time").GetDouble() > firstTime + .5,
                "첫 영상 재생 시간 진행", 45000);
            Hide();
            File.WriteAllText(Path.Combine(output, "browser-ready.json"), JsonSerializer.Serialize(new { processId = Environment.ProcessId, hidden = !IsVisible }));
            await Until(() => playing && currentVideoId == "dQw4w9WgXcQ", "실행 중인 앱에 두 번째 재생 요청", 60000);
            if (!IsVisible) throw new Exception("숨겨진 위젯이 복원되지 않았습니다.");
            double secondTime = lastState.GetProperty("time").GetDouble();
            await Until(() => playing && lastState.GetProperty("time").GetDouble() > secondTime + .5, "두 번째 영상 재생 시간 진행");
            Capture("browser-playing");
            File.WriteAllText(Path.Combine(output, "browser-verification.json"), JsonSerializer.Serialize(new {
                success = true, processId = Environment.ProcessId, coldStart = true, existingInstance = true,
                hiddenWidgetRestored = true, playing, url = Browser.CoreWebView2.Source
            }, new JsonSerializerOptions { WriteIndented = true }));
            await Task.Delay(1000);
            Application.Current.Shutdown(0);
        }
        catch (Exception error)
        {
            File.WriteAllText(Path.Combine(output, "browser-failure.json"), error.ToString());
            Application.Current.Shutdown(1);
        }
    }
}
