using System;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using Microsoft.Web.WebView2.Core;

namespace TurnTabler;

public partial class WidgetWindow
{
    private async Task ObsSmokeChecks()
    {
        string output = Environment.GetEnvironmentVariable("TURNTABLER_ARTIFACTS") ?? Path.Combine(Program.DataDirectory, "artifacts");
        Directory.CreateDirectory(output);
        string statePath = Path.Combine(output, "player-state.json");
        void State(string phase) => File.WriteAllText(statePath, JsonSerializer.Serialize(new { phase, time = DateTime.UtcNow }));
        try
        {
            using var wav = new MemoryStream();
            using (var writer = new BinaryWriter(wav, Encoding.ASCII, true))
            {
                const int rate = 48000;
                writer.Write(Encoding.ASCII.GetBytes("RIFF")); writer.Write(36 + rate * 2);
                writer.Write(Encoding.ASCII.GetBytes("WAVEfmt ")); writer.Write(16); writer.Write((short)1); writer.Write((short)1);
                writer.Write(rate); writer.Write(rate * 2); writer.Write((short)2); writer.Write((short)16);
                writer.Write(Encoding.ASCII.GetBytes("data")); writer.Write(rate * 2);
                for (int i = 0; i < rate; i++) writer.Write((short)(3276 * Math.Sin(2 * Math.PI * 440 * i / rate)));
            }
            const string fixture = "https://www.youtube.com/turntabler-audio-fixture";
            var core = Browser.CoreWebView2;
            core.AddWebResourceRequestedFilter(fixture, CoreWebView2WebResourceContext.Document);
            core.WebResourceRequested += (_, e) =>
            {
                if (e.Request.Uri != fixture) return;
                string html = "<!doctype html><html><body><video loop src='data:audio/wav;base64," + Convert.ToBase64String(wav.ToArray()) + "'></video></body></html>";
                e.Response = core.Environment.CreateWebResourceResponse(new MemoryStream(Encoding.UTF8.GetBytes(html)), 200, "OK", "Content-Type: text/html; charset=utf-8");
            };
            core.Navigate(fixture);
            await WaitScript("document.querySelector('video')?.readyState>=2");
            await Execute("window.turntablerNative.setAudioOutput('')");
            preferences.ObsEnabled = true; UpdateObsOutput();
            if (obsAudio == null) throw new Exception(obsStatus);
            File.WriteAllText(Path.Combine(output, "endpoint.json"), JsonSerializer.Serialize(new { url = obsAudio.Url }));
            State("ready");
            await Until(() => File.Exists(Path.Combine(output, "start-audio")), "OBS 준비", 60000);
            await Execute("window.turntablerNative.setVolume(20);window.turntablerNative.play()"); State("tone");
            await Task.Delay(1000);
            File.WriteAllText(Path.Combine(output, "media-state.json"), await core.ExecuteScriptAsync("(()=>{const v=document.querySelector('video');return {paused:v.paused,volume:v.volume,muted:v.muted,time:v.currentTime,readyState:v.readyState,sinkId:v.sinkId,error:v.error?.message}})()"));
            await Task.Delay(9000);
            await Execute("window.turntablerNative.pause()"); State("silence");
            await Task.Delay(6000);
            await Execute("window.turntablerNative.play()"); State("resumed");
            await Task.Delay(10000);
            await Execute("window.turntablerNative.pause()"); State("complete");
            await Task.Delay(3000);
            closing = true; Application.Current.Shutdown(0);
        }
        catch (Exception error)
        {
            File.WriteAllText(statePath, JsonSerializer.Serialize(new { phase = "error", error = error.Message }));
            closing = true; Application.Current.Shutdown(1);
        }
    }
}
