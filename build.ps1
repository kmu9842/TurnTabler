param([switch]$Test)
$ErrorActionPreference = 'Stop'
$projectDirectory = $PSScriptRoot
$localDotnet = Join-Path $projectDirectory '.tools\dotnet\dotnet.exe'
$dotnet = if (Test-Path -LiteralPath $localDotnet) { $localDotnet } else { 'dotnet.exe' }
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
& $dotnet publish (Join-Path $projectDirectory 'native\TurnTabler.csproj') -c Release -r win-x64 --self-contained false -o (Join-Path $projectDirectory 'release\native')
if ($LASTEXITCODE -ne 0) { throw 'Native widget build failed.' }
if ($Test) {
    $testProcess = Start-Process -FilePath (Join-Path $projectDirectory 'release\native\TurnTabler.exe') -ArgumentList '--self-test' -PassThru -Wait -WindowStyle Hidden
    Get-Content -LiteralPath (Join-Path $projectDirectory 'release\native\self-test-result.txt')
    if ($testProcess.ExitCode -ne 0) { throw 'Native tests failed.' }
}
