using System;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace TurnTabler;

public partial class WidgetWindow
{
    private Window? trayOptionsWindow;
    private Slider? videoOpacitySlider;

    private void ApplyVideoOpacity() => VideoViewbox.Opacity = videoAvailable ? preferences.VideoOpacity / 100 : 0;

    private void ShowTrayOptions()
    {
        if (trayOptionsWindow != null) { trayOptionsWindow.Activate(); return; }

        var window = new Window
        {
            Title = "TurnTabler 옵션", Owner = this, Icon = Icon,
            Width = 300, Height = 170, WindowStyle = WindowStyle.None,
            AllowsTransparency = true, Background = Brushes.Transparent,
            ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false, Topmost = Topmost,
            WindowStartupLocation = WindowStartupLocation.Manual, UseLayoutRounding = true
        };
        var area = WorkArea();
        window.Left = Program.Smoke ? -10000 : area.Left + (area.Width - window.Width) / 2;
        window.Top = Program.Smoke ? -10000 : area.Top + (area.Height - window.Height) / 2;

        var panel = new StackPanel();
        var header = new DockPanel { Height = 28, Margin = new Thickness(0, 0, 0, 15), Background = Brushes.Transparent };
        var close = new Button { Content = "×", Width = 28, Style = (Style)FindResource(typeof(Button)), ToolTip = "닫기" };
        AutomationProperties.SetName(close, "옵션 닫기");
        close.Click += (_, _) => window.Close();
        DockPanel.SetDock(close, System.Windows.Controls.Dock.Right);
        header.Children.Add(close);
        header.Children.Add(new TextBlock { Text = "옵션", Foreground = Brushes.White, FontSize = 13, VerticalAlignment = VerticalAlignment.Center });
        header.MouseLeftButtonDown += (_, e) => { if (e.LeftButton == MouseButtonState.Pressed) window.DragMove(); };
        panel.Children.Add(header);

        var labelRow = new DockPanel { Margin = new Thickness(0, 0, 0, 7) };
        var valueLabel = new TextBlock { Text = $"{preferences.VideoOpacity:0}%", Foreground = Brushes.White, FontSize = 12 };
        DockPanel.SetDock(valueLabel, System.Windows.Controls.Dock.Right);
        labelRow.Children.Add(valueLabel);
        labelRow.Children.Add(new TextBlock { Text = "영상 불투명도", Foreground = Brushes.White, FontSize = 12 });
        panel.Children.Add(labelRow);

        var slider = new Slider
        {
            Minimum = 0, Maximum = 100, Value = preferences.VideoOpacity,
            TickFrequency = 1, IsSnapToTickEnabled = true,
            Style = (Style)FindResource("ChromeFader"), ToolTip = "0%: 투명 · 100%: 불투명"
        };
        AutomationProperties.SetName(slider, "영상 불투명도");
        slider.ValueChanged += (_, _) =>
        {
            preferences.VideoOpacity = Math.Round(slider.Value);
            valueLabel.Text = $"{preferences.VideoOpacity:0}%";
            ApplyVideoOpacity();
            Save();
        };
        panel.Children.Add(slider);
        var endpoints = new DockPanel { Margin = new Thickness(6, 5, 6, 0) };
        var opaque = new TextBlock { Text = "불투명", Foreground = Brushes.LightGray, FontSize = 10 };
        DockPanel.SetDock(opaque, System.Windows.Controls.Dock.Right);
        endpoints.Children.Add(opaque);
        endpoints.Children.Add(new TextBlock { Text = "투명", Foreground = Brushes.LightGray, FontSize = 10 });
        panel.Children.Add(endpoints);

        window.Content = new Border
        {
            Padding = new Thickness(18, 12, 18, 14), CornerRadius = new CornerRadius(12),
            Background = new SolidColorBrush(Color.FromArgb(235, 28, 28, 28)),
            BorderBrush = (Brush)FindResource("ChromeStroke"), BorderThickness = new Thickness(.8), Child = panel
        };
        window.PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { e.Handled = true; window.Close(); } };
        window.Closed += (_, _) => { trayOptionsWindow = null; videoOpacitySlider = null; };
        trayOptionsWindow = window;
        videoOpacitySlider = slider;
        window.Show();
        slider.Focus();
    }
}
