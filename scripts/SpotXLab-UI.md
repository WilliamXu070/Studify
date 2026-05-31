# SpotX Lab UI

This repo now has a native Windows UI launcher for the SpotX lab workflow.

## Quick start

- `.\scripts\Start-SpotxLab.UI.bat`
- or
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\SpotXLab.UI.ps1`

From the UI you can:

- pick a profile from `labs/spotx-lab/profiles`
- choose a Spotify install source folder (defaults to `%APPDATA%\Spotify`)
- set options:
  - `Force recreate workspace`
  - `Prepare only`
  - `Start Spotify after patch`
- add extra runtime args
- patch/run Spotify and watch output logs in-session
- open the workspace/profiles folders

Every run writes session logs to:

- `%TEMP%\SpotX-Lab-UI\<timestamp>.out.log`
- `%TEMP%\SpotX-Lab-UI\<timestamp>.err.log`

If you need to test a small UI-visible change first, start with changing
assets in `labs/spotx-lab/helpers` and re-run the profile. The workspace is copied
and patched per run, so your base Spotify install stays safe.

