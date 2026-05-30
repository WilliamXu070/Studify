#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "../..");

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

const overlayTweak = read("Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifyOverlayTweak.x.swift");
const serverConfig = read("Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifyOverlayServerConfig.swift");
const fakePlayback = read("Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifyFakePlaybackController.swift");
const probeClient = read("Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifyProbeStreamClient.swift");
const methodProbe = read("Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifyOfflinePathwayMethodProbe.x.swift");
const spoof = read("Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifyOfflinePlayableSpoof.x.swift");
const onlineProbe = read("Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifyOnlinePlaybackProbe.x.swift");
const bannerProbe = read("Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifyBannerStateProbe.x.swift");
const promptProbe = read("Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifyPromptPresentationProbe.x.swift");
const restartTest = read("Tools/StudifyLiveContainer/restart-test.sh");

assert(
  serverConfig.includes("StudifyLibrary/probe-mode.txt") &&
    overlayTweak.includes("studifyOverlayProbeModeIsEnabled()"),
  "probe mode must be configurable from Documents/StudifyLibrary/probe-mode.txt"
);

assert(
    probeClient.includes('payload["sequence"]') &&
    probeClient.includes('payload["data"] = data') &&
    probeClient.includes("studify_probe_events.jsonl") &&
    probeClient.includes("appendLocalProbeEvent(payload)") &&
    probeClient.includes("studifyOverlayProbeUploadIsEnabled()") &&
    probeClient.includes("Probe stream local-only mode active; skipping server upload"),
  "probe stream must preserve sequence/structured data and default to local-only JSONL logging"
);

assert(
  fakePlayback.includes('StudifyProbeStreamClient.shared.start(reason: cachedOfflineModeActive ? "row tap" : "online row tap")') &&
    fakePlayback.includes('StudifyProbeStreamClient.shared.start(reason: "generic tap")') &&
    fakePlayback.includes('"uriCandidates": uriCandidates') &&
    fakePlayback.includes('"slots": slotSummary') &&
    fakePlayback.includes("logGenericTapProbe"),
  "row/generic tap probe must start traces and emit slot/URI evidence"
);

assert(
  fakePlayback.includes("cachedOfflineModeActive || studifyOverlayProbeModeEnabled") &&
    fakePlayback.includes('"online row tap"') &&
    onlineProbe.includes("StudifyEnableOnlinePlaybackProbe") &&
    bannerProbe.includes("StudifyEnableBannerStateProbe"),
  "probe mode must capture online row taps without auto-enabling risky online/banner probes"
);

assert(
  fakePlayback.includes('studifySeededGimmeLoveURI = "spotify:track:3CUovld1O1HdAOrkgMlvNx"') &&
    fakePlayback.includes('StudifyFakeTrack(title: "Gimme Love", artist: "Vista Kicks")') &&
    fakePlayback.includes('source == "passive row tap"') &&
    fakePlayback.includes("Native playback bridge using seeded track for offline row press") &&
    fakePlayback.includes("startLocalAudioOrSeededSilence(for: track)") &&
    fakePlayback.includes("Native playback bridge simulating seeded offline playback without local audio") &&
    read("Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifySpotifyStateBridge.x.swift").includes("studify-fake{title="),
  "offline simulation must seed Gimme Love only from an offline row press and publish it through the state bridge"
);

assert(
  !overlayTweak.includes("StudifyPromptPresentationProbe.shared.install()") &&
    promptProbe.includes("typealias Group = StudifyPromptPresentationProbeHookGroup") &&
    overlayTweak.includes("Download signal skipped while probe mode is local-only") &&
    promptProbe.includes('hook: isGate ? "premium-gate" : "prompt"') &&
    promptProbe.includes("premium/song-selection prompt"),
  "prompt/premium gate probe code must not be activated by the core probe group"
);

assert(
  restartTest.includes("StudifyLibrary/probe-mode.txt") &&
    restartTest.includes("StudifyLibrary/probe-upload.txt") &&
    restartTest.includes("server URL copy skipped; probe mode writes local phone logs only") &&
    restartTest.includes("probe mode disabled on phone; cleared stale probe-mode.txt state") &&
    restartTest.includes("pymobiledevice3") &&
    restartTest.includes("processes pgrep Spotify") &&
    restartTest.includes("retrying attempt $attempt/3") &&
    restartTest.includes("/Users/williamxu/Downloads/EeveeSpotify-6.6.2-9.1.28.ipa") &&
    restartTest.includes('run ./build-studify-overlay.sh "$BASE_IPA"'),
  "restart-test must enable local phone probe mode and build overlay against the clean base Eevee IPA"
);

assert(
  methodProbe.includes("Observe-only native method probe") &&
    methodProbe.includes("let result = orig.canPlayContent") &&
    methodProbe.includes("return result") &&
    !methodProbe.includes("return true"),
  "native method probe must observe orig results, not force availability"
);

assert(
  spoof.includes("Unsafe offline playable spoof groups skipped while observe-only probe mode is enabled"),
  "unsafe spoof hooks must be disabled while probe mode is enabled"
);

assert(
  ![
    overlayTweak,
    serverConfig,
    fakePlayback,
    probeClient,
    methodProbe,
    spoof,
  ].some((source) => source.includes("class_copyMethodList") || source.includes("objc_copyClassList")),
  "probe flow must not ship broad Objective-C runtime class/method scans"
);

console.log("probe-source-test: ok");
