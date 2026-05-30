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
    onlineProbe.includes("studifyOverlayProbeModeEnabled") &&
    bannerProbe.includes("studifyOverlayProbeModeEnabled"),
  "probe mode must capture online row taps and enable online/banner probes"
);

assert(
  overlayTweak.includes("StudifyPromptPresentationProbe.shared.install()") &&
    overlayTweak.includes("Download signal skipped while probe mode is local-only") &&
    promptProbe.includes('hook: isGate ? "premium-gate" : "prompt"') &&
    promptProbe.includes("premium/song-selection prompt"),
  "prompt/premium gate probe must be installed and emit structured gate evidence"
);

assert(
  restartTest.includes("StudifyLibrary/probe-mode.txt") &&
    restartTest.includes("StudifyLibrary/probe-upload.txt") &&
    restartTest.includes("server URL copy skipped; probe mode writes local phone logs only") &&
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
