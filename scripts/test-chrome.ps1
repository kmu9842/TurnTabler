param([string]$AppPath)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot -Parent
if (-not $AppPath) { $AppPath = Join-Path $projectDirectory 'release\single-file\TurnTabler.exe' }
$AppPath = (Resolve-Path -LiteralPath $AppPath).Path
$output = Join-Path $projectDirectory ('artifacts\chrome\run-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
$registryPath = 'Software\Google\Chrome\NativeMessagingHosts\com.turntabler.player'
$backups = @()
# Capture both original views before mutating either (some HKCU keys share views).
foreach ($view in @([Microsoft.Win32.RegistryView]::Registry32, [Microsoft.Win32.RegistryView]::Registry64)) {
    $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, $view)
    try {
        $key = $registry.OpenSubKey($registryPath)
        try { $backups += [pscustomobject]@{ View = $view; Exists = $null -ne $key; Value = $(if ($key) { $key.GetValue('') } else { $null }) } }
        finally { if ($key) { $key.Dispose() } }
    } finally { $registry.Dispose() }
}
$oldLocalAppData = $env:LOCALAPPDATA
$oldArtifacts = $env:TURNTABLER_ARTIFACTS
$oldBrowserSmoke = $env:TURNTABLER_BROWSER_SMOKE
try {
    # Exercise the shipped installer in isolated storage, then restore registration.
    $env:LOCALAPPDATA = Join-Path $output 'local-app-data'
    $env:TURNTABLER_ARTIFACTS = $output
    $env:TURNTABLER_BROWSER_SMOKE = '1'
    & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $projectDirectory 'release\chrome-extension\Install.ps1') -AppPath $AppPath -NoOpen
    if ($LASTEXITCODE -ne 0) { throw 'Isolated extension installation failed.' }
    & node (Join-Path $PSScriptRoot 'test-chrome.mjs') $output (Join-Path $env:LOCALAPPDATA 'TurnTablerChrome\extension')
    if ($LASTEXITCODE -ne 0) { throw 'Chrome integration test failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $env:LOCALAPPDATA 'TurnTablerChrome\Uninstall.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Isolated extension uninstallation failed.' }
    if (-not (Test-Path -LiteralPath $AppPath)) { throw 'Uninstaller removed the app.' }
    foreach ($backup in $backups) {
        $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, $backup.View)
        try {
            $key = $registry.OpenSubKey($registryPath)
            if ($key) { $key.Dispose(); throw 'Uninstaller left native host registration behind.' }
        } finally { $registry.Dispose() }
    }
    Write-Output 'PASS: separate package installation, real Chrome native messaging and uninstallation.'
} finally {
    foreach ($backup in $backups) {
        $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, $backup.View)
        try {
            if ($backup.Exists) {
                $key = $registry.CreateSubKey($registryPath)
                try {
                    if ($null -eq $backup.Value) { $key.DeleteValue('', $false) }
                    else { $key.SetValue('', $backup.Value, [Microsoft.Win32.RegistryValueKind]::String) }
                } finally { $key.Dispose() }
            } else { $registry.DeleteSubKey($registryPath, $false) }
        } finally { $registry.Dispose() }
    }
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:TURNTABLER_ARTIFACTS = $oldArtifacts
    $env:TURNTABLER_BROWSER_SMOKE = $oldBrowserSmoke
}
