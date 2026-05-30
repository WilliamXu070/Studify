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
const server = read("Tools/StudifySignalServer/server.js");

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
    server.includes("sequence: Number(payload.sequence || 0)") &&
    server.includes("data: payload.data"),
  "probe stream must preserve sequence/structured data and write local JSONL fallback"
);

assert(
  fakePlayback.includes('StudifyProbeStreamClient.shared.start(reason: "row tap")') &&
    fakePlayback.includes('StudifyProbeStreamClient.shared.start(reason: "generic tap")') &&
    fakePlayback.includes('"uriCandidates": uriCandidates') &&
    fakePlayback.includes('"slots": slotSummary') &&
    fakePlayback.includes("logGenericTapProbe"),
  "row/generic tap probe must start traces and emit slot/URI evidence"
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
