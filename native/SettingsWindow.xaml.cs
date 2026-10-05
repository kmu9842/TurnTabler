using System.Windows;
using System.Windows.Input;

namespace TurnTabler;

public partial class SettingsWindow : Window
{
    public SettingsWindow()
    {
        InitializeComponent();
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { e.Handled = true; Close(); } };
    }

    private void CloseSettings(object sender, RoutedEventArgs e) => Close();
    private void DragHeader(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }
}
