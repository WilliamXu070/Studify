# One-Click SpotX Launcher

Use this command:

- `.\scripts\Start-SpotXLab-OneClick.bat [profile] [spotify-source] [mode]`

Example:

- `.\scripts\Start-SpotXLab-OneClick.bat default "%APPDATA%\Spotify"`
- `.\scripts\Start-SpotXLab-OneClick.bat default "%APPDATA%\Spotify" repatch`
- `.\scripts\Start-SpotXLab-OneClick.bat default "%APPDATA%\Spotify" recreate`
- `.\scripts\Start-SpotXLab-OneClick.bat default "%APPDATA%\Spotify" online`
- `.\scripts\Start-SpotXLab-OneClick.bat default "%APPDATA%\Spotify" cleanup`

What it does:

1. Uses a persistent lab workspace at `labs\spotx-lab\workspace\<profile>\spotify`.
2. Runs the SpotX patcher only when needed (first run or missing workspace), or when `repatch` / `recreate` is used.
3. Blocks network access for only the lab `Spotify.exe` with temporary Windows Firewall rules.
4. Launches `Spotify.exe` from the workspace with lab-local app data.

Modes:

- `repatch`: re-run SpotX patching against the existing workspace.
- `recreate`: delete and recreate the workspace from source.
- `online`: launch the lab without firewall isolation.
- `cleanup`: remove the lab firewall rules for the profile.

Offline behavior:

- Default launch requires an elevated terminal because Windows Firewall rules need admin rights.
- Firewall rules are scoped to `labs\spotx-lab\workspace\<profile>\spotify\Spotify.exe`.
- Use `cleanup` from an elevated terminal to remove stale lab firewall rules.

Offline fixtures:

- Edit `labs\spotx-lab\workspace\<profile>\offline-fixtures.json`.
- Set `enabled` to `true` and add track `uri` / `id` values.
- Run `repatch` so the fixture config is baked into the injected lab helper.
- Fixtures are UI-state only; they do not download, decrypt, or bypass Spotify playback.

Do not run `SpotxLab.ps1` directly from prompt unless you intend to call the underlying runner manually.

If you want one physical icon, create a shortcut to:

- `%USERPROFILE%\Desktop\Projects\Studify_App\scripts\Start-SpotXLab-OneClick.bat`
