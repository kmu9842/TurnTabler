using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls.Primitives;
using ToolStripMenuItem = System.Windows.Forms.ToolStripMenuItem;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace TurnTabler;

public partial class WidgetWindow
{
    private async Task CheckTrayOpacity(bool hasVideo)
    {
        var legacy = JsonSerializer.Deserialize<Preferences>("{\"Volume\":65}")!;
        if (legacy.VideoOpacity != 58) throw new Exception("기존 설정에 불투명도 58% 기본값 적용 실패");
        var menu = tray.ContextMenuStrip!.Items.OfType<ToolStripMenuItem>().Single(item => item.Text == "설정");
        menu.PerformClick();
        var options = settingsWindow ?? throw new Exception("트레이 설정을 열지 못함");
        SettingsButton.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
        if (options != settingsWindow) throw new Exception("트레이와 위젯 버튼이 서로 다른 설정 창을 엶");

        foreach (double opacity in new[] { 0d, 37d, 100d, 58d })
        {
            options.VideoOpacity.Value = opacity;
            await Task.Delay(300);
            if (Math.Abs(VideoViewbox.Opacity - (hasVideo ? opacity / 100 : 0)) > .001)
                throw new Exception("영상 불투명도 즉시 적용 실패: " + opacity);
            var saved = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(PreferencesPath))!;
            if (saved.VideoOpacity != opacity) throw new Exception("영상 불투명도 저장 실패");
        }
        bool effect = preferences.Effect;
        options.EffectOption.IsChecked = !effect;
        options.EffectOption.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
        await Task.Delay(300);
        if (hasVideo && Math.Abs(VideoViewbox.Opacity - .58) > .001) throw new Exception("프로젝터 효과가 불투명도를 덮어씀");
        options.EffectOption.IsChecked = effect;
        options.EffectOption.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
        double light = preferences.LightStrength;
        options.LightStrength.Value = 31;
        if (Math.Abs(Ambient.Opacity - .31) > .001) throw new Exception("통합 설정 빛 퍼짐 적용 실패");
        options.LightStrength.Value = light;
        int size = preferences.Size;
        options.SmallSize.IsChecked = true;
        if (Width != 368) throw new Exception("통합 설정 크기 변경 실패");
        new[] { options.SmallSize, options.NormalSize, options.LargeSize }[size].IsChecked = true;

        if (hasVideo)
        {
            var image = new RenderTargetBitmap((int)options.Width, (int)options.Height, 96, 96, PixelFormats.Pbgra32);
            image.Render(options);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
            var output = Environment.GetEnvironmentVariable("TURNTABLER_ARTIFACTS") ?? Program.DataDirectory;
            using var stream = File.Create(Path.Combine(output, "tray-options.png")); encoder.Save(stream);
        }
        options.Close();
        SettingsButton.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
        if (settingsWindow!.VideoOpacity.Value != 58 || settingsWindow.LightStrength.Value != light)
            throw new Exception("위젯 버튼으로 재진입 후 설정 복원 실패");
        menu.PerformClick();
        settingsWindow.Close();
        Hide(); menu.PerformClick();
        if (settingsWindow?.IsVisible != true) throw new Exception("위젯을 숨긴 상태에서 트레이 설정 열기 실패");
        settingsWindow.Close(); Show();
    }
}
