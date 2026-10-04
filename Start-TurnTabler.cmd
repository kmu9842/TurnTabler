@echo off
if not exist "%~dp0release\native\TurnTabler.exe" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
  if errorlevel 1 exit /b 1
)
start "" "%~dp0release\native\TurnTabler.exe" %*
