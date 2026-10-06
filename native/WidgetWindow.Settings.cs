using System;
using System.Windows;

namespace TurnTabler;

public partial class WidgetWindow
{
    private SettingsWindow? settingsWindow;
    private void ApplyVideoOpacity() => VideoViewbox.Opacity = videoAvailable ? preferences.VideoOpacity / 100 : 0;

    private void OpenSettings(object sender, RoutedEventArgs e) { e.Handled = true; ShowSettings(); }

    private void ShowSettings()
    {
        if (settingsWindow != null) { settingsWindow.Activate(); return; }
        PlaylistPanel.Visibility = Visibility.Collapsed;
        var window = new SettingsWindow { Owner = this, Icon = Icon, Topmost = Topmost };
        var area = WorkArea();
        window.Height = Math.Min(window.Height, Math.Max(250, area.Height - 24));
        window.Left = Program.Smoke ? -10000 : area.Left + (area.Width - window.Width) / 2;
        window.Top = Program.Smoke ? -10000 : area.Top + (area.Height - window.Height) / 2;
        window.PinOption.IsChecked = preferences.Pin;
        window.RotationOption.IsChecked = preferences.Rotation;
        window.EffectOption.IsChecked = preferences.Effect;
        window.AmbientOption.IsChecked = preferences.Ambient;
        window.VideoOpacity.Value = preferences.VideoOpacity;
        window.OpacityValue.Text = $"{preferences.VideoOpacity:0}%";
        window.LightStrength.Value = preferences.LightStrength;
        window.LightValue.Text = $"{preferences.LightStrength:0}%";
        var sizes = new[] { window.SmallSize, window.NormalSize, window.LargeSize };
        sizes[preferences.Size].IsChecked = true;

        foreach (var toggle in new[] { window.PinOption, window.RotationOption, window.EffectOption, window.AmbientOption })
            toggle.Click += (_, _) =>
            {
                preferences.Pin = window.PinOption.IsChecked == true;
                preferences.Rotation = window.RotationOption.IsChecked == true;
                preferences.Effect = window.EffectOption.IsChecked == true;
                preferences.Ambient = window.AmbientOption.IsChecked == true;
                ApplyOptions(); Save();
            };
        window.VideoOpacity.ValueChanged += (_, _) =>
        {
            preferences.VideoOpacity = Math.Round(window.VideoOpacity.Value);
            window.OpacityValue.Text = $"{preferences.VideoOpacity:0}%";
            ApplyVideoOpacity(); Save();
        };
        window.LightStrength.ValueChanged += (_, _) =>
        {
            preferences.LightStrength = Math.Round(window.LightStrength.Value);
            window.LightValue.Text = $"{preferences.LightStrength:0}%";
            Ambient.Opacity = preferences.LightStrength / 100; Save();
        };
        for (int i = 0; i < sizes.Length; i++)
        {
            int size = i;
            sizes[i].Checked += (_, _) => { preferences.Size = size; SetSize(); if (!Program.Smoke) Dock(); Save(); };
        }
        window.YouTubePageButton.Click += OpenYouTubePage;
        window.DockButton.Click += DockWidget;
        window.HideButton.Click += HideWidget;
        window.ExitButton.Click += CloseWidget;
        window.Closed += (_, _) => settingsWindow = null;
        settingsWindow = window;
        window.ObsOption.IsChecked = preferences.ObsEnabled;
        window.ObsOption.Click += (_, _) => { preferences.ObsEnabled = window.ObsOption.IsChecked == true; Save(); UpdateObsOutput(); };
        window.CopyObsAddress.Click += (_, _) => CopyObsAddress();
        RefreshObsSettings();
        window.AudioOutput.SelectionChanged += async (_, _) =>
        {
            if (updatingOutputs || window.AudioOutput.SelectedItem is not AudioOutputDevice device) return;
            window.AudioOutputStatus.Text = "출력 장치를 적용하는 중…";
            await Execute("window.turntablerNative?.setAudioOutput(" + System.Text.Json.JsonSerializer.Serialize(device.Id) + ")");
        };
        window.RefreshOutputsButton.Click += async (_, _) => await RefreshAudioOutputs();
        UpdateAudioOutputList();
        window.Show();
        _ = RefreshAudioOutputs();
        window.VideoOpacity.Focus();
    }
}
