param([switch]$Test)
$ErrorActionPreference = 'Stop'
$projectDirectory = $PSScriptRoot
$localDotnet = Join-Path $projectDirectory '.tools\dotnet\dotnet.exe'
$dotnet = if (Test-Path -LiteralPath $localDotnet) { $localDotnet } else { 'dotnet.exe' }
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$outputDirectory = Join-Path $projectDirectory 'release\single-file'
& $dotnet publish (Join-Path $projectDirectory 'native\TurnTabler.csproj') -c Release -p:PublishProfile=SingleFile -o $outputDirectory
if ($LASTEXITCODE -ne 0) { throw 'Single EXE publish failed.' }
$executable = Join-Path $outputDirectory 'TurnTabler.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Published EXE was not produced.' }
if ($Test) {
    # Verify a fresh directory containing only the EXE, outside the project and its assets.
    $isolatedDirectory = Join-Path $env:TEMP ('TurnTabler-ReleaseCheck-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $isolatedDirectory | Out-Null
    $isolatedExecutable = Join-Path $isolatedDirectory 'TurnTabler.exe'
    Copy-Item -LiteralPath $executable -Destination $isolatedExecutable
    $testProcess = Start-Process -FilePath $isolatedExecutable -WorkingDirectory $isolatedDirectory -ArgumentList '--self-test' -PassThru -WindowStyle Hidden
    if (-not $testProcess.WaitForExit(30000)) { Stop-Process -Id $testProcess.Id; throw 'Single EXE self-test timed out.' }
    if ($testProcess.ExitCode -ne 0) { throw "Single EXE self-test failed ($($testProcess.ExitCode))." }
    Get-Content -LiteralPath (Join-Path $isolatedDirectory 'self-test-result.txt')
    $env:TURNTABLER_ARTIFACTS = Join-Path $projectDirectory 'artifacts\single-file'
    New-Item -ItemType Directory -Path $env:TURNTABLER_ARTIFACTS -Force | Out-Null
    $testProcess = Start-Process -FilePath $isolatedExecutable -WorkingDirectory $isolatedDirectory -ArgumentList '--smoke' -PassThru -WindowStyle Hidden
    if (-not $testProcess.WaitForExit(180000)) { Stop-Process -Id $testProcess.Id; throw 'Single EXE playback test timed out.' }
    if ($testProcess.ExitCode -ne 0) {
        $failurePath = Join-Path $env:TURNTABLER_ARTIFACTS 'failure.json'
        if (Test-Path -LiteralPath $failurePath) { Get-Content -LiteralPath $failurePath -Encoding UTF8 }
        throw "Single EXE playback test failed ($($testProcess.ExitCode))."
    }
    Get-Content -LiteralPath (Join-Path $env:TURNTABLER_ARTIFACTS 'verification.json') -Encoding UTF8
}
Get-Item -LiteralPath $executable | Select-Object FullName,Length
Get-FileHash -LiteralPath $executable -Algorithm SHA256 | Select-Object Algorithm,Hash
