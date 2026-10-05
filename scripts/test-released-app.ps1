param([string]$AppPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'release\single-file\TurnTabler.exe'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ReleaseWindow {
    public delegate bool Callback(IntPtr window, IntPtr state);
    [DllImport("user32.dll")] public static extern bool EnumWindows(Callback callback, IntPtr state);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    public static IntPtr Find(int process) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((window, state) => { uint owner; GetWindowThreadProcessId(window, out owner);
            var text = new StringBuilder(256); GetWindowText(window, text, text.Capacity);
            if (owner == process && text.ToString() == "TurnTabler") { found = window; return false; } return true;
        }, IntPtr.Zero); return found;
    }
}
'@
$projectDirectory = Split-Path $PSScriptRoot -Parent
$AppPath = (Resolve-Path -LiteralPath $AppPath).Path
$originalHash = (Get-FileHash -LiteralPath $AppPath).Hash
$output = Join-Path $projectDirectory ('artifacts\released-app\run-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $projectDirectory 'release\chrome-extension\host') -Filter 'TurnTabler.ChromeHost.exe*' | Copy-Item -Destination $output
[IO.File]::WriteAllText((Join-Path $output 'settings.json'), (@{appPath=$AppPath} | ConvertTo-Json))
function Request($request) {
    $process = New-Object Diagnostics.Process
    $process.StartInfo = New-Object Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = Join-Path $output 'TurnTabler.ChromeHost.exe'
    $process.StartInfo.Arguments = 'chrome-extension://ebnjhkdpohpgeipkalbfklpfibjadnhd/'
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardOutput = $true
    try {
        [void]$process.Start()
        $bytes = [Text.Encoding]::UTF8.GetBytes(($request | ConvertTo-Json -Compress))
        $stream = $process.StandardInput.BaseStream
        $stream.Write([BitConverter]::GetBytes($bytes.Length), 0, 4)
        $stream.Write($bytes, 0, $bytes.Length); $stream.Flush(); $stream.Close()
        $buffer = New-Object IO.MemoryStream
        $read = $process.StandardOutput.BaseStream.CopyToAsync($buffer)
        if (-not $process.WaitForExit(45000)) { $process.Kill(); throw 'Host timeout' }
        $read.GetAwaiter().GetResult()
        $replyBytes = $buffer.ToArray()
        $reply = [Text.Encoding]::UTF8.GetString($replyBytes, 4, $replyBytes.Length - 4) | ConvertFrom-Json
        if (-not $reply.ok) { throw $reply.error }
        return $reply
    } finally { $process.Dispose() }
}
function Control($window, $id) {
    return $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)))
}
function WaitPlaying($appId, $url) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt 60000) {
        $handle = [ReleaseWindow]::Find($appId)
        if ($handle -ne [IntPtr]::Zero) {
            $window = [System.Windows.Automation.AutomationElement]::FromHandle($handle)
            $address = Control $window 'Address'; $play = Control $window 'Play'
            if ($address -and $play) {
                $value = $address.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
                if ($value -eq $url -and $play.Current.Name -eq ([char]0x2161).ToString()) { return $window }
            }
        }
        Start-Sleep -Milliseconds 400
    }
    throw "Playback did not start: $url"
}
$existing = Get-Process TurnTabler -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $AppPath } | Select-Object -First 1
$originalUrl = $null
if ($existing) {
    $originalWindow = [System.Windows.Automation.AutomationElement]::FromHandle([ReleaseWindow]::Find($existing.Id))
    $address = Control $originalWindow 'Address'
    if ($address) { $originalUrl = $address.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
}
$firstUrl = 'https://www.youtube.com/watch?v=2qfoSxRRCJc'
$secondUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=43'
try {
    $first = Request @{action='play';url=$firstUrl}
    if ($existing -and $first.processId -ne $existing.Id) { throw 'Existing process was not reused' }
    $window = WaitPlaying $first.processId $firstUrl
    Write-Output "PASS: released EXE playback in process $($first.processId), adapter $($first.adapter)"
    # Use the app's own Hide button, then verify the adapter restores it.
    (Control $window 'SettingsButton').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $hideName = -join ([char[]]@(0xC228,0xAE30,0xAE30))
    $hide = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $hideName)))
    $hide.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 300
    $handle = [ReleaseWindow]::Find($first.processId)
    if ([ReleaseWindow]::IsWindowVisible($handle)) { throw 'App was not hidden' }
    $second = Request @{action='play';url=$secondUrl}
    if ($second.processId -ne $first.processId) { throw 'Hidden process was not reused' }
    $window = WaitPlaying $second.processId $secondUrl
    if (-not [ReleaseWindow]::IsWindowVisible($handle)) { throw 'Hidden window was not restored' }
    Write-Output 'PASS: hidden released widget restored and second video playing'
    # Gracefully close only the selected app, then exercise a real cold start.
    $desktop = Get-Process -Id $second.processId
    $window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    if (-not $desktop.WaitForExit(10000)) { throw 'App did not exit gracefully' }
    $cold = Request @{action='play';url=$firstUrl}
    if ($cold.processId -eq $second.processId) { throw 'Cold start did not create an app process' }
    $null = WaitPlaying $cold.processId $firstUrl
    if ((Get-FileHash -LiteralPath $AppPath).Hash -ne $originalHash) { throw 'Distributed executable was modified' }
    $report = @{success=$true;appPath=$AppPath;version=(Get-Item -LiteralPath $AppPath).VersionInfo.FileVersion;existingProcess=$first.processId;coldProcess=$cold.processId;hiddenRestored=$true;playing=$true;exeUnchanged=$true}
    $report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding UTF8
    Write-Output 'PASS: exact distributed EXE cold start and playback; file hash unchanged'
    Write-Output $output
} finally {
    if ($originalUrl -match '^https://') { $null = Request @{action='play';url=$originalUrl} }
}
