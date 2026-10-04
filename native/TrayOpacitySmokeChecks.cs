using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace TurnTabler;

public partial class WidgetWindow
{
    private async Task CheckTrayOpacity(bool hasVideo)
    {
        var legacy = JsonSerializer.Deserialize<Preferences>("{\"Volume\":65}")!;
        if (legacy.VideoOpacity != 58) throw new Exception("기존 설정에 불투명도 58% 기본값 적용 실패");
        var menu = tray.ContextMenuStrip!.Items.OfType<ToolStripMenuItem>().Single(item => item.Text == "옵션");
        menu.PerformClick();
        var options = trayOptionsWindow ?? throw new Exception("트레이 옵션을 열지 못함");
        menu.PerformClick();
        if (options != trayOptionsWindow) throw new Exception("트레이 옵션 중복 창");

        foreach (double opacity in new[] { 0d, 37d, 100d, 58d })
        {
            videoOpacitySlider!.Value = opacity;
            await Task.Delay(300);
            if (Math.Abs(VideoViewbox.Opacity - (hasVideo ? opacity / 100 : 0)) > .001)
                throw new Exception("영상 불투명도 즉시 적용 실패: " + opacity);
            var saved = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(PreferencesPath))!;
            if (saved.VideoOpacity != opacity) throw new Exception("영상 불투명도 저장 실패");
        }
        bool effect = preferences.Effect;
        preferences.Effect = !effect; ApplyOptions();
        await Task.Delay(300);
        if (hasVideo && Math.Abs(VideoViewbox.Opacity - .58) > .001) throw new Exception("프로젝터 효과가 불투명도를 덮어씀");
        preferences.Effect = effect; ApplyOptions();

        if (hasVideo)
        {
            var image = new RenderTargetBitmap((int)options.Width, (int)options.Height, 96, 96, PixelFormats.Pbgra32);
            image.Render(options);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
            var output = Environment.GetEnvironmentVariable("TURNTABLER_ARTIFACTS") ?? Program.DataDirectory;
            using var stream = File.Create(Path.Combine(output, "tray-options.png")); encoder.Save(stream);
        }
        options.Close();
        menu.PerformClick();
        if (videoOpacitySlider!.Value != 58) throw new Exception("옵션 재진입 후 불투명도 값 복원 실패");
        trayOptionsWindow!.Close();
    }
}
