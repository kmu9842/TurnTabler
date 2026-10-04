param([switch]$Test)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot -Parent
$sourceDirectory = Join-Path $projectDirectory 'chrome-extension'
$iconDirectory = Join-Path $sourceDirectory 'extension\icons'
New-Item -ItemType Directory -Path $iconDirectory -Force | Out-Null

# Extract the exact PNG frames from the existing app icon; do not regenerate artwork.
$iconBytes = [IO.File]::ReadAllBytes((Join-Path $projectDirectory 'native\Assets\Icon\TurnTabler.ico'))
$count = [BitConverter]::ToUInt16($iconBytes, 4)
foreach ($size in @(16, 32, 48, 128)) {
    $found = $false
    for ($i = 0; $i -lt $count; $i++) {
        $entry = 6 + $i * 16
        if ($iconBytes[$entry] -ne $size) { continue }
        $length = [BitConverter]::ToInt32($iconBytes, $entry + 8)
        $offset = [BitConverter]::ToInt32($iconBytes, $entry + 12)
        $frame = New-Object byte[] $length
        [Array]::Copy($iconBytes, $offset, $frame, 0, $length)
        if ([BitConverter]::ToString($frame, 0, 8) -ne '89-50-4E-47-0D-0A-1A-0A') { throw "App icon frame $size is not PNG." }
        [IO.File]::WriteAllBytes((Join-Path $iconDirectory "$size.png"), $frame)
        $found = $true
        break
    }
    if (-not $found) { throw "Missing app icon frame: $size" }
}

if ($Test) {
    & node --test (Join-Path $projectDirectory 'test\chrome-extension.test.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Chrome extension tests failed.' }
}
$packageDirectory = Join-Path $projectDirectory 'release\chrome-extension'
New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
Get-ChildItem -LiteralPath $sourceDirectory | Copy-Item -Destination $packageDirectory -Recurse -Force
# The independent host uses Windows' .NET Framework, so the app EXE stays untouched.
$hostDirectory = Join-Path $packageDirectory 'host'
New-Item -ItemType Directory -Path $hostDirectory -Force | Out-Null
$frameworkDirectory = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$references = @('System.dll', 'System.Core.dll', 'System.Web.dll', 'System.Web.Extensions.dll', 'System.Windows.Forms.dll', 'WPF\UIAutomationClient.dll', 'WPF\UIAutomationTypes.dll', 'WPF\WindowsBase.dll')
$compilerArguments = @('/nologo', '/target:winexe', '/platform:x64', '/optimize+', ('/out:' + (Join-Path $hostDirectory 'TurnTabler.ChromeHost.exe')), ('/win32icon:' + (Join-Path $projectDirectory 'native\Assets\Icon\TurnTabler.ico')))
$compilerArguments += $references | ForEach-Object { '/reference:' + (Join-Path $frameworkDirectory $_) }
$compilerArguments += Join-Path $projectDirectory 'chrome-native-host\NativeHost.cs'
& (Join-Path $frameworkDirectory 'csc.exe') $compilerArguments
if ($LASTEXITCODE -ne 0) { throw 'Chrome native host build failed.' }
[IO.File]::WriteAllText((Join-Path $hostDirectory 'TurnTabler.ChromeHost.exe.config'), '<configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8"/></startup></configuration>')
# Windows PowerShell 5.1 requires a BOM for Korean strings in scripts.
foreach ($script in @('Install.ps1', 'Uninstall.ps1')) {
    $scriptPath = Join-Path $packageDirectory $script
    $scriptText = [IO.File]::ReadAllText($scriptPath)
    [IO.File]::WriteAllText($scriptPath, $scriptText, (New-Object Text.UTF8Encoding($true)))
}
$extensionVersion = (Get-Content -LiteralPath (Join-Path $sourceDirectory 'extension\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
$zipPath = Join-Path $projectDirectory "release\TurnTabler-Chrome-$extensionVersion.zip"
Compress-Archive -Path (Join-Path $packageDirectory '*') -DestinationPath $zipPath -Force
Get-Item -LiteralPath $zipPath | Select-Object FullName, Length
