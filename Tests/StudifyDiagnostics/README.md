# Studify Diagnostics

This folder isolates Studify regressions into layers:

1. Source regression checks
   - v91 fallback must activate even when Spotify's offline helper class is missing.
   - UIControl fallback must use the real UIKit selector `sendAction:to:forEvent:`.
   - UIControl fallback must pass through to the original action after sending the Studify signal.
   - UIControl fallback must show a one-time probe banner so phone tests can prove the hook loaded.
   - LiveContainer bundle lookup must remain present.

2. Server smoke checks
   - Starts the local Studify signal server on `127.0.0.1:18787`.
   - Verifies `/v1/health`.
   - Posts a playlist job to `/v1/jobs/playlist`.
   - Verifies `/v1/jobs` shows the job.

3. Build and artifact checks
   - Verifies the built dylib contains Studify visual markers.
   - Verifies the correct UIKit selector is present in the built dylib and patched IPA.
   - Verifies the input IPA is actually clean and not already injected.
   - Verifies the LiveContainer export contains raw `.dylib` / `.framework` files and no stale `/private/tmp` dependency path.

## Commands

Run source and server checks:

```bash
Tests/StudifyDiagnostics/run-all.sh
```

Inventory candidate IPAs and flag already-tweaked inputs:

```bash
Tests/StudifyDiagnostics/ipa-inventory.sh
```

Run a full local pass, including rebuilding the tweak and LiveContainer export:

```bash
Tests/StudifyDiagnostics/run-all.sh --build
```

When the only available input IPA is already injected and you still want to verify the produced artifacts:

```bash
STUDIFY_ALLOW_CONTAMINATED_INPUT=1 Tests/StudifyDiagnostics/artifact-check.sh
```

## Phone-Side Isolation Matrix

Use these as separate tests, not all mixed together:

1. Blank IPA only
   - Expected: launches and POST button reaches server.
   - Failure means LiveContainer/network/server, not Spotify tweak code.

2. Clean Spotify IPA only
   - Expected: original Spotify behavior, no Studify banners.
   - Failure means the base IPA or LiveContainer setup is bad.

3. Patched Spotify IPA only
   - Expected: Studify premium branding and banners.
   - Failure means IPA injection/loading.

4. Clean Spotify IPA plus LiveContainer tweak folder
   - Expected: same runtime behavior as patched IPA.
   - Failure here but not patched IPA means LiveContainer tweak loading or dependency placement.

5. Download button test
   - No `STUDIFY UICONTROL HOOK ACTIVE` after tapping anything: tweak loading, hook activation, or selector issue.
   - Probe banner appears, but no `STUDIFY HOOK FIRED` on download: the fallback hook loaded, but the download button detector did not match that UI.
   - Yellow banner only: hook fires but request did not start.
   - Yellow then blue, server sees nothing: device-to-server networking.
   - Green: server accepted job.
   - Red: request reached a failure path; read the popup/error string.
