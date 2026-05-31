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
set "PROBE_MODE="

echo [SpotX Lab] One-Click Launcher
echo [SpotX Lab] Profile : %PROFILE%
echo [SpotX Lab] Source  : %SOURCE%

shift
shift
:parse_modes
if "%~1"=="" goto modes_done
if /I "%~1"=="recreate" set "RECREATE=-ForceRecreate"
if /I "%~1"=="repatch" set "REPATCH=-Repatch"
if /I "%~1"=="online" set "ONLINE=-Online"
if /I "%~1"=="offline" set "CLIENT_OFFLINE=-ClientOffline"
if /I "%~1"=="clientoffline" set "CLIENT_OFFLINE=-ClientOffline"
if /I "%~1"=="cleanup" set "CLEANUP=-CleanupNetworkRules"
if /I "%~1"=="probe" set "PROBE_MODE=-Probe"
if /I "%~1"=="noprobe" set "PROBE_MODE=-NoProbe"
shift
goto parse_modes
:modes_done
echo.
if defined CLEANUP (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" %CLEANUP%
) else if defined ONLINE (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" -OfflineMode %ONLINE% %PROBE_MODE%
) else if defined CLIENT_OFFLINE (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" -OfflineMode %CLIENT_OFFLINE% %PROBE_MODE%
) else if defined RECREATE (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" -OfflineMode %RECREATE% %PROBE_MODE%
) else if defined REPATCH (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" -OfflineMode %REPATCH% %PROBE_MODE%
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%PS1%" -Profile "%PROFILE%" -SpotifySourcePath "%SOURCE%" -OfflineMode %PROBE_MODE%
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
