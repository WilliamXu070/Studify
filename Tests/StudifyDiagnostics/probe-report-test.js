#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");
const childProcess = require("child_process");

const root = path.resolve(__dirname, "../..");
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "studify-probe-report-"));
const probePath = path.join(tempDir, "events.jsonl");
const logPath = path.join(tempDir, "overlay.log");

function writeJsonl(filePath, events) {
  fs.writeFileSync(filePath, `${events.map((event) => JSON.stringify(event)).join("\n")}\n`);
}

writeJsonl(probePath, [
  {
    sequence: 1,
    hook: "offline-playable-spoof",
    phase: "skipped",
    message: "probe mode observe-only",
    data: {},
  },
  {
    sequence: 2,
    hook: "native-method-probe",
    phase: "activated",
    message: "observe-only",
    data: {
      activated: [],
      skipped: ["playback-service.canPlayContent:selector-missing"],
    },
  },
  {
    sequence: 3,
    hook: "uiapplication",
    phase: "sendAction",
    message: "main",
    className: "_TtCCE16Encore_ButtonKitO16EncoreFoundation6Encore6Button8Tertiary",
    selector: "main",
    data: {
      targetClass: "NSBlockOperation",
      senderChain: "ReinventFree_TimeCapUpsellPageImpl.TimeCapUpsellViewController",
    },
  },
]);

fs.writeFileSync(
  logPath,
  "Passive UIControl action route probe labels=Songs play in a random order | get Premium to play any song\n"
);

const output = childProcess.execFileSync(
  "node",
  ["Tools/StudifyLiveContainer/summarize-probe-events.js", probePath, logPath],
  {
    cwd: root,
    encoding: "utf8",
  }
);

function assertIncludes(needle) {
  if (!output.includes(needle)) {
    throw new Error(`Expected report to include ${JSON.stringify(needle)}\n${output}`);
  }
}

assertIncludes("Probe mode is observe-only");
assertIncludes("Spotify free-tier/Premium gate was observed");
assertIncludes("No row-tap/tap/native press-path event was captured");
assertIncludes("Candidate native playability/offline methods did not fire");
assertIncludes("Premium Gate Events");

console.log("probe-report-test: ok");
