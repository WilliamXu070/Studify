#!/usr/bin/env node

const fs = require("fs");

const overlayLogPath = process.argv[2] || "/private/tmp/studify_overlay_debug_latest.log";
const probePath = process.argv[3] || "/private/tmp/studify_probe_events_latest.jsonl";

function readText(filePath) {
  try {
    return fs.readFileSync(filePath, "utf8");
  } catch {
    return "";
  }
}

function fail(message, details = []) {
  console.error(`verify-offline-seed-log: FAIL: ${message}`);
  for (const detail of details) {
    console.error(`  ${detail}`);
  }
  process.exit(1);
}

function pass(message) {
  console.log(`verify-offline-seed-log: ok: ${message}`);
}

const overlayLog = readText(overlayLogPath);
const probeText = readText(probePath);
const combined = `${overlayLog}\n${probeText}`;

if (!combined.trim()) {
  fail("pulled logs are empty", [
    `overlay log: ${overlayLogPath}`,
    `probe events: ${probePath}`,
    "Open Spotify through the deployed target, tap a playlist row while offline, then pull logs again.",
  ]);
}

const requirements = [
  {
    label: "overlay loaded",
    ok: /Studify overlay starting|Studify native playback bridge installed/.test(combined),
  },
  {
    label: "explicit offline user intent was captured",
    ok: /Native playback bridge using seeded track for offline row press|Native playback bridge using seeded fallback for offline row press without readable row track|Native playback bridge seeded offline user intent/.test(combined),
  },
  {
    label: "Gimme Love state was published",
    ok: /Gimme Love/.test(combined) && /Vista Kicks/.test(combined),
  },
  {
    label: "seeded Spotify URI was used",
    ok: /spotify:track:3CUovld1O1HdAOrkgMlvNx/.test(combined),
  },
  {
    label: "playback state became playing",
    ok: /Native playback bridge started title=Gimme Love artist=Vista Kicks .*isPlaying=true|STUDIFY AUDIO PLAYING|Native playback bridge simulating seeded offline playback without local audio/.test(combined),
  },
  {
    label: "fake state was protected after tap",
    ok: /Native playback bridge reasserted fake Spotify state|Native playback bridge holding offline fake state after row press/.test(combined),
  },
];

const missing = requirements.filter((requirement) => !requirement.ok);
if (missing.length) {
  fail("offline seeded playback proof is incomplete", missing.map((requirement) => `missing: ${requirement.label}`));
}

const relevantLines = overlayLog
  .split(/\n/)
  .filter((line) => /Gimme Love|seeded|reasserted|holding offline|STUDIFY AUDIO PLAYING|simulating seeded offline playback/.test(line))
  .slice(-16);

pass("offline row/control intent produced fake playing state for Gimme Love");
if (relevantLines.length) {
  console.log("");
  console.log("Relevant overlay lines:");
  for (const line of relevantLines) {
    console.log(line);
  }
}
