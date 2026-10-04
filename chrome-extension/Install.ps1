param([string]$AppPath, [switch]$NoOpen, [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

if (-not $AppPath) {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'TurnTabler.exe (2.1.2+)'
    $dialog.Filter = 'TurnTabler (TurnTabler.exe)|TurnTabler.exe'
    $dialog.CheckFileExists = $true
    # Offer the newest adjacent release (including release/v2.1.4/TurnTabler.exe).
    $releaseDirectory = Split-Path $PSScriptRoot -Parent
    $candidate = Get-ChildItem -Path (Join-Path $releaseDirectory 'v*\TurnTabler.exe') -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.VersionInfo.FileVersion } -Descending | Select-Object -First 1
    if ($candidate) { $dialog.InitialDirectory = $candidate.DirectoryName; $dialog.FileName = $candidate.FullName }
    try {
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }
        $AppPath = $dialog.FileName
    } finally { $dialog.Dispose() }
}
$appExecutable = (Resolve-Path -LiteralPath $AppPath).Path
if ([IO.Path]::GetFileName($appExecutable) -ne 'TurnTabler.exe') { throw 'Select TurnTabler.exe.' }
# Validate metadata through the independent host. Never execute the selected app
# during installation: released EXEs do not implement --browser-bridge-info.
$hostSource = Join-Path $PSScriptRoot 'host\TurnTabler.ChromeHost.exe'
if (-not (Test-Path -LiteralPath $hostSource)) { throw 'The Chrome host is missing. Extract the complete extension ZIP again.' }
$probe = New-Object System.Diagnostics.Process
$probe.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
$probe.StartInfo.FileName = $hostSource
$probe.StartInfo.Arguments = '--validate "' + $appExecutable + '"'
$probe.StartInfo.UseShellExecute = $false
$probe.StartInfo.CreateNoWindow = $true
$probe.StartInfo.RedirectStandardOutput = $true
$probe.StartInfo.RedirectStandardError = $true
$probe.StartInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
$probe.StartInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
try {
    [void]$probe.Start()
    $result = $probe.StandardOutput.ReadToEndAsync()
    $failure = $probe.StandardError.ReadToEndAsync()
    if (-not $probe.WaitForExit(15000)) { $probe.Kill(); throw 'TurnTabler compatibility check timed out.' }
    if ($probe.ExitCode -ne 0) { throw $failure.Result }
    $info = $result.Result | ConvertFrom-Json
} finally { $probe.Dispose() }

$extensionManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'extension\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$sha = [Security.Cryptography.SHA256]::Create()
try { $hash = $sha.ComputeHash([Convert]::FromBase64String($extensionManifest.key)) }
finally { $sha.Dispose() }
$extensionId = -join ($hash[0..15] | ForEach-Object { [char](97 + ($_ -shr 4)); [char](97 + ($_ -band 15)) })
if (-not $info.ok -or $info.protocol -ne 1) { throw 'TurnTabler file validation failed.' }
if ($ValidateOnly) { Write-Output "PASS: TurnTabler $($info.appVersion), file $appExecutable, extension $extensionId"; exit 0 }

$installDirectory = Join-Path $env:LOCALAPPDATA 'TurnTablerChrome'
$extensionDirectory = Join-Path $installDirectory 'extension'
New-Item -ItemType Directory -Path $extensionDirectory -Force | Out-Null
$sourceDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'extension')).TrimEnd('\')
if ($sourceDirectory -ne [IO.Path]::GetFullPath($extensionDirectory).TrimEnd('\')) {
    Get-ChildItem -LiteralPath $sourceDirectory | Copy-Item -Destination $extensionDirectory -Recurse -Force
}
foreach ($name in @('Install.cmd', 'Install.ps1', 'Uninstall.cmd', 'Uninstall.ps1', 'README.txt')) {
    $sourceFile = Join-Path $PSScriptRoot $name
    $targetFile = Join-Path $installDirectory $name
    if ([IO.Path]::GetFullPath($sourceFile) -ne [IO.Path]::GetFullPath($targetFile)) {
        Copy-Item -LiteralPath $sourceFile -Destination $targetFile -Force
    }
}
$hostDirectory = Join-Path $installDirectory 'host'
New-Item -ItemType Directory -Path $hostDirectory -Force | Out-Null
foreach ($name in @('TurnTabler.ChromeHost.exe', 'TurnTabler.ChromeHost.exe.config')) {
    $source = Join-Path $PSScriptRoot "host\$name"
    $target = Join-Path $hostDirectory $name
    if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target)) { Copy-Item -LiteralPath $source -Destination $target -Force }
}
[IO.File]::WriteAllText((Join-Path $hostDirectory 'settings.json'), (@{ appPath = $appExecutable } | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
$nativeManifestPath = Join-Path $installDirectory 'com.turntabler.player.json'
$nativeManifest = [ordered]@{
    name = 'com.turntabler.player'
    description = 'TurnTabler YouTube playback'
    path = Join-Path $hostDirectory 'TurnTabler.ChromeHost.exe'
    type = 'stdio'
    allowed_origins = @("chrome-extension://$extensionId/")
}
[IO.File]::WriteAllText($nativeManifestPath, ($nativeManifest | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
# Register both views because Chrome checks the 32-bit view first. No administrator rights.
foreach ($view in @([Microsoft.Win32.RegistryView]::Registry32, [Microsoft.Win32.RegistryView]::Registry64)) {
    $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, $view)
    try {
        $key = $registry.CreateSubKey('Software\Google\Chrome\NativeMessagingHosts\com.turntabler.player')
        try { $key.SetValue('', $nativeManifestPath, [Microsoft.Win32.RegistryValueKind]::String) }
        finally { $key.Dispose() }
    } finally { $registry.Dispose() }
}
Write-Output "Connected: TurnTabler $($info.appVersion), $appExecutable"
Write-Output "Chrome > chrome://extensions > Developer mode > Load unpacked > $extensionDirectory"
if (-not $NoOpen) {
    $instructions = "TurnTabler $($info.appVersion) 연결이 완료되었습니다.`n$appExecutable`n`n1. Chrome에서 chrome://extensions 를 엽니다.`n2. 오른쪽 위 '개발자 모드'를 켭니다.`n3. '압축해제된 확장 프로그램을 로드합니다'를 누릅니다.`n4. 아래 폴더를 선택합니다(클립보드에 복사됨).`n`n$extensionDirectory`n`nEXE 경로는 확장 프로그램 설정에서 변경할 수 있습니다."
    try { [System.Windows.Forms.Clipboard]::SetText($extensionDirectory) } catch { }
    [void][System.Windows.Forms.MessageBox]::Show($instructions, 'TurnTabler Chrome', 'OK', 'Information')
}
