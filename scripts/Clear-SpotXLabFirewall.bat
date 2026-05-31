@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PROFILE=%~1"
if "%PROFILE%"=="" set "PROFILE=default"

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%SCRIPT_DIR%Clear-SpotXLabFirewall.ps1" -Profile "%PROFILE%"
exit /b %ERRORLEVEL%
