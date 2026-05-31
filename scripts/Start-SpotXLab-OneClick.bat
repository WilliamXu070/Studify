@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%Start-SpotXLab-OneClick.ps1"

if not exist "%PS1%" (
  echo Missing launcher: "%PS1%"
  pause
  exit /b 1
)

set "PROFILE=%~1"
set "SOURCE=%~2"
set "MODE=%~3"
if "%PROFILE%"=="" set "PROFILE=default"
if "%SOURCE%"=="" set "SOURCE=%APPDATA%\Spotify"
set "RECREATE="
set "REPATCH="
set "ONLINE="
set "CLEANUP="
set "CLIENT_OFFLINE="

echo [SpotX Lab] One-Click Launcher
echo [SpotX Lab] Profile : %PROFILE%
echo [SpotX Lab] Source  : %SOURCE%

if /I "%MODE%"=="recreate" (
  set "RECREATE=-ForceRecreate"
)
if /I "%MODE%"=="repatch" (
  set "REPATCH=-Repatch"
)
if /I "%MODE%"=="online" (
  set "ONLINE=-Online"
)
if /I "%MODE%"=="offline" (
  set "CLIENT_OFFLINE=-ClientOffline"
)
if /I "%MODE%"=="clientoffline" (
  set "CLIENT_OFFLINE=-ClientOffline"
)
if /I "%MODE%"=="cleanup" (
  set "CLEANUP=-CleanupNetworkRules"
)
echo.
if defined CLEANUP (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" %CLEANUP%
) else if defined ONLINE (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" -OfflineMode %ONLINE%
) else if defined CLIENT_OFFLINE (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" -OfflineMode %CLIENT_OFFLINE%
) else if defined RECREATE (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" -OfflineMode %RECREATE%
) else if defined REPATCH (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" -OfflineMode %REPATCH%
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" -OfflineMode
)
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
    echo [SpotX Lab] Failed with exit code %RC%.
) else (
    echo [SpotX Lab] Done.
)
pause
exit /b %RC%
