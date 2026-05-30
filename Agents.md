# Studify Agent Workflow (iOS LiveContainer Tweak)

This file documents the end-to-end change flow we use for Studify overlay tweaks that touch Spotify/LiveContainer behavior.

## 1) Branch hygiene and target
- Start from `main` and keep changes scoped to the overlay + diagnostics layer.
- Confirm clean working tree before starting.
- Source IPA baseline for rebuilds: `/Users/williamxu/Downloads/EeveeSpotify-6.6.2-9.1.28.ipa`.

## 2) Implement change
- Edit only related files (overlay, diagnostics, bridge, docs).
- Keep row-press simulation and probe logic backward-safe:
  - Keep existing online path untouched.
  - Keep fallback behavior explicit and limited to offline/row-press path.

## 3) Local verification before device push
- Run source-level checks:
  - `node Tests/StudifyDiagnostics/probe-source-test.js`
  - `Tests/StudifyDiagnostics/overlay-artifact-check.sh`
- Commit and push once checks pass.
- This round commit: `2ff1391` (fix offline row tap seeding override + reassertion).

## 4) Build package from IPA
- Rebuild tweak from clean IPA:
  - `./build-studify-overlay.sh /Users/williamxu/Downloads/EeveeSpotify-6.6.2-9.1.28.ipa`
- Output package and files:
  - `Outputs/StudifyOverlay/StudifyOverlayLatest.deb`
  - `Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/StudifyOverlay.dylib`
  - `Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/Orion.framework`

## 5) Push to iPhone (LiveContainer)
- Use repo helper with no server upload:
  - `PROBE_MODE=0 COPY_SERVER_URL=0 Tools/StudifyLiveContainer/restart-test.sh --no-build`
- Script behavior:
  - Verifies overlay symbols locally.
  - Copies `StudifyOverlay.dylib` and `Orion.framework` into `Documents/Tweaks/StudifySpotify/` inside LiveContainer data container.
  - Verifies device-side Mach-O payload hashes match local build.
  - Clears old probe/debug logs.
  - Relaunches LiveContainer.
- Successful run should show:
  - `overlay-artifact-check: ok`
  - matching payload hashes for dylib and Orion
  - `Launched application with com.kdt.livecontainer.25P4CVCPW5`.

## 6) Pull phone logs (local only)
- Pull latest logs and report:
  - `Tools/StudifyLiveContainer/pull-probe-report.sh`
- Expected outputs from script:
  - `/tmp/studify_overlay_debug_latest.log`
  - `/tmp/studify_probe_events_latest.jsonl`
- For row-press offline verification, we expect logs like:
  - `Native playback bridge using seeded track for offline row press ...`
  - `Native playback bridge reasserted fake Spotify state ...`
  - `Native playback bridge holding offline fake state after row press ...`

## 7) What changed and why this avoids regressions
- Keep offline simulation behavior isolated:
  - do not alter app startup risky hooks.
  - no server dependency by default (`COPY_SERVER_URL=0`, probe mode disabled).
- Ensure state hooks remain aligned with Spotify metadata reads:
  - hook overrides now cover `trackTitle`, `artistTitle`, `artistName`, and `URI`.
- Handle tap race with Spotify-native action flow:
  - short grace window and delayed reassertions after row press.
- Compatibility guard:
  - re-run diagnostics + artifact checks after every generation.
  - compare hashes from local vs device copy before launch.

## 8) Notes for future generation handoffs
- If app flow doesn’t report tap/native events after deploy, it usually means the interaction path on iPhone differs from probe assumptions.
- Run once inside Spotify (LiveContainer): open playlist, tap a row, then immediately pull probe report.
- Keep `Docs/GimmeLoveOfflineSimulation.md` updated with timestamped sample outputs for manual recovery.

## 9) Current change summary (this session)
- Row-press offline simulation now reasserts seeded state after tap to match Spotify repaint timing:
  - Added grace-window logic so simulated row-seed state stays active briefly after press.
  - Added delayed reassertions that re-emit fake Spotify state + mini-player visual updates.
- Spotify metadata override coverage was expanded:
  - Added `artistTitle` and `URI` overrides to the existing `trackTitle`/`artistName`/`metadata` coverage.
- Build/deploy reliability hardening:
  - Updated signing flow to stage/copy `Orion.framework` safely when building from the Eevee IPA.
- Git history now includes:
  - `2ff1391` (`Fix offline row tap seeding override and reassert`)
  - `f307480` (`Add Agents.md runbook for Studify tweak change→build→verify→deploy loop`)
- Commit and pushed both the code fix and the runbook updates.

## 10) Exact sequence to run now (no server, local logs on iPhone)
1. Rebuild: `./build-studify-overlay.sh /Users/williamxu/Downloads/EeveeSpotify-6.6.2-9.1.28.ipa`
2. Verify locally:
   - `node Tests/StudifyDiagnostics/probe-source-test.js`
   - `Tests/StudifyDiagnostics/overlay-artifact-check.sh`
3. Deploy to LiveContainer: `PROBE_MODE=0 COPY_SERVER_URL=0 Tools/StudifyLiveContainer/restart-test.sh --no-build`
4. In phone app flow:
   - Open LiveContainer.
   - Open Spotify inside it.
   - Open the target playlist.
   - Tap the song row once.
5. Pull logs immediately:
   - `Tools/StudifyLiveContainer/pull-probe-report.sh`
6. Read latest files:
   - `/tmp/studify_overlay_debug_latest.log`
   - `/tmp/studify_probe_events_latest.jsonl`

## 11) Current breakage checkpoint (2026-05-30)
Latest run still showed an immediate app crash on launch, before any Spotify row press can run.

Repro command sequence:
1. `PROBE_MODE=0 COPY_SERVER_URL=0 Tools/StudifyLiveContainer/restart-test.sh --no-build`
2. Open LiveContainer → open Spotify quickly, then monitor iPhone behavior.
3. `Tools/StudifyLiveContainer/pull-probe-report.sh`

Observed evidence:
- `studify_overlay_debug_latest.log` only had startup lines:
  - `Studify overlay starting`
  - `Studify probe upload enabled=false`
  - `Activated UIControl download hook group`
- No button/track events were produced because process exits before Spotify hooks activate.
- Crash report `LiveContainer-2026-05-30-092952.ips` shows:
  - `EXC_BREAKPOINT` / `SIGTRAP`
  - faulting chain: `studifyActivateSpotifyStateBridge()` → `StudifyOverlay.init()` → `protocol witness for static Tweak.handleError(_:)`
- This is a startup hook-initialization failure path, not an offline-row playback path.

Next safest action before any new change:
1. Do not redeploy blindly while app crashes on open.
2. Pull latest crash and confirm with:
   - `/private/tmp/studify-crash/LiveContainer-2026-05-30-092952.ips`
   - `grep -n "studifyActivateSpotifyStateBridge\\|StudifyOverlay.init\\|EXC_BREAKPOINT" ...`
3. Only when startup is stable, continue to row-press validation and offline seeding checks.

## 12) Startup-crash stabilization
The immediate crash path is guarded by an opt-in file now:
- Default: `Documents/StudifyLibrary/state-bridge.txt = off`
- Debug-only enable: run deploy with `STATE_BRIDGE=1` when specifically testing the state bridge.

Required stable deploy command:
`PROBE_MODE=0 COPY_SERVER_URL=0 STATE_BRIDGE=0 Tools/StudifyLiveContainer/restart-test.sh --no-build`

The deploy script writes `state-bridge.txt` every run, so stale phone state from previous builds cannot silently re-enable the startup-crash hook path. Expected startup logs after this fix:
- `Studify overlay starting`
- `Activated UIControl download hook group`
- `Spotify state bridge skipped; opt-in debug bridge disabled`
- `Studify probe mode disabled`
