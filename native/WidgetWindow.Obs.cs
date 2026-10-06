using System;
using System.IO;
using System.Text.Json;
using System.Windows;

namespace TurnTabler;

public partial class WidgetWindow
{
    private ObsAudioServer? obsAudio;
    private string obsStatus = "OBS에 TurnTabler 소리만 직접 전달합니다.";
    private void UpdateObsOutput()
    {
        obsAudio?.Dispose(); obsAudio = null;
        if (preferences.ObsEnabled && browserReady)
        {
            try
            {
                if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 20348))
                    throw new NotSupportedException("OBS 직접 연결은 Windows 11 이상에서 지원합니다.");
                if (string.IsNullOrEmpty(preferences.ObsToken)) { preferences.ObsToken = Guid.NewGuid().ToString("N"); Save(); }
                obsAudio = new ObsAudioServer((int)Browser.CoreWebView2.BrowserProcessId, Program.Smoke ? 0 : 18743, preferences.ObsToken,
                    error => Dispatcher.BeginInvoke(new Action(() => { obsStatus = "OBS 출력 오류: " + error.Split('\n')[0]; LogPlayback("obs-audio", error); RefreshObsSettings(); })));
                File.WriteAllText(Path.Combine(Program.DataDirectory, "obs-endpoint.json"), JsonSerializer.Serialize(new { url = obsAudio.Url }));
                obsStatus = "OBS 미디어 소스에 연결하세요. 스피커 출력은 그대로 유지됩니다.";
            }
            catch (Exception error) { obsStatus = "OBS 연결을 시작하지 못했습니다: " + error.Message; LogPlayback("obs-start", error.Message); }
        }
        RefreshObsSettings();
    }
    private void RefreshObsSettings()
    {
        if (settingsWindow == null) return;
        settingsWindow.CopyObsAddress.IsEnabled = obsAudio?.IsRunning == true && preferences.ObsEnabled;
        settingsWindow.ObsStatus.Text = obsStatus;
    }
    private void CopyObsAddress()
    {
        if (obsAudio == null) return;
        try { Clipboard.SetText(obsAudio.Url); settingsWindow!.ObsStatus.Text = "복사했습니다. OBS 미디어 소스 → 로컬 파일 해제 → 입력에 붙여넣으세요."; }
        catch (Exception) { settingsWindow!.ObsStatus.Text = "클립보드가 사용 중입니다. 다시 눌러 주세요."; }
    }
}
