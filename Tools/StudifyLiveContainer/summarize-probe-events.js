#!/usr/bin/env node

const fs = require("fs");

const probePath = process.argv[2] || "/private/tmp/studify_probe_events_latest.jsonl";
const overlayLogPath = process.argv[3] || "/private/tmp/studify_overlay_debug_latest.log";

function readText(filePath) {
  try {
    return fs.readFileSync(filePath, "utf8");
  } catch {
    return "";
  }
}

function parseJsonl(filePath) {
  const text = readText(filePath).trim();
  if (!text) return [];

  const events = [];
  for (const [index, line] of text.split(/\n/).entries()) {
    if (!line.trim()) continue;
    try {
      events.push(JSON.parse(line));
    } catch (error) {
      events.push({
        sequence: index + 1,
        hook: "parse-error",
        phase: "invalid-json",
        message: error.message,
        data: { line: line.slice(0, 240) },
      });
    }
  }
  return events;
}

function compact(value) {
  if (value === undefined || value === null) return "";
  const text = typeof value === "string" ? value : JSON.stringify(value);
  return text.replace(/\s+/g, " ").trim().slice(0, 220);
}

function eventText(event) {
  return JSON.stringify(event).toLowerCase();
}

function eventLine(event) {
  const seq = String(event.sequence || "-").padStart(3, " ");
  const hook = event.hook || "-";
  const phase = event.phase || "-";
  const cls = event.className || "";
  const selector = event.selector || "";
  const message = compact(event.message || "");
  const suffix = compact(event.data || "");
  return `#${seq} ${hook}/${phase} ${selector} ${cls} ${message} ${suffix}`.replace(/\s+/g, " ").trim();
}

function uniq(values) {
  return [...new Set(values.filter(Boolean))];
}

function printSection(title, lines) {
  console.log("");
  console.log(`== ${title} ==`);
  if (!lines.length) {
    console.log("(none)");
    return;
  }
  for (const line of lines) console.log(line);
}

const events = parseJsonl(probePath);
const overlayLog = readText(overlayLogPath);

const premiumPattern = /(timecap|upsell|premium|random order|song selection|freetier|free tier|get premium)/i;
const premiumEvents = events.filter((event) => premiumPattern.test(JSON.stringify(event)));
const rowEvents = events.filter((event) => event.hook === "row-tap" || event.hook === "tap" || (event.hook === "native-playback" && event.phase === "press-path"));
const nativeMethodEvents = events.filter((event) => event.hook === "native-method");
const nativeProbeEvents = events.filter((event) => event.hook === "native-method-probe");
const spoofEvents = events.filter((event) => event.hook === "offline-playable-spoof");
const routeEvents = events.filter((event) => event.hook === "uicontrol" || event.hook === "uiapplication");
const rowCellEvents = events.filter((event) => event.hook === "offline-ui-mutator" || event.hook === "playlist-cell");
const parseErrors = events.filter((event) => event.hook === "parse-error");

console.log("Studify probe report");
console.log(`probe file: ${probePath}`);
console.log(`overlay log: ${overlayLogPath}`);
console.log(`events: ${events.length}`);

if (parseErrors.length) {
  console.log(`jsonl parse errors: ${parseErrors.length}`);
}

console.log("");
console.log("Diagnosis:");
if (spoofEvents.some((event) => /observe-only|skipped/i.test(`${event.phase} ${event.message}`))) {
  console.log("- Probe mode is observe-only; offline/playability spoof hooks were not forcing results.");
}
if (premiumEvents.length || premiumPattern.test(overlayLog)) {
  console.log("- Spotify free-tier/Premium gate was observed in this run.");
  const gateClasses = uniq(premiumEvents.map((event) => event.className).concat(
    [...overlayLog.matchAll(/([A-Za-z0-9_]+\.)*[A-Za-z0-9_]*TimeCap[A-Za-z0-9_.]*/g)].map((match) => match[0])
  ));
  if (gateClasses.length) console.log(`- Gate class/path evidence: ${gateClasses.slice(0, 6).join(" | ")}`);
}
if (!rowEvents.length) {
  console.log("- No row-tap/tap/native press-path event was captured; the active path is still above our row gesture probe.");
} else {
  console.log(`- Row/tap path captured: ${rowEvents.length} event(s).`);
}
if (!nativeMethodEvents.length) {
  console.log("- Candidate native playability/offline methods did not fire after the tap.");
} else {
  console.log(`- Native method return probes fired: ${nativeMethodEvents.length} event(s).`);
}
if (nativeProbeEvents.length) {
  const activated = nativeProbeEvents.flatMap((event) => event.data?.activated || []);
  const skipped = nativeProbeEvents.flatMap((event) => event.data?.skipped || []);
  console.log(`- Native method probe activation: ${activated.length} activated, ${skipped.length} skipped.`);
}

printSection("Premium Gate Events", premiumEvents.map(eventLine).slice(-12));
printSection("Row Or Tap Events", rowEvents.map(eventLine).slice(-16));
printSection("Native Method Events", nativeMethodEvents.map(eventLine).slice(-16));
printSection("UIApplication/UIControl Route Events", routeEvents.map(eventLine).slice(-20));
printSection("Visible Row/Cell Events", rowCellEvents.map(eventLine).slice(-20));

const overlayGateLines = overlayLog
  .split(/\n/)
  .map((line, index) => ({ line, index: index + 1 }))
  .filter(({ line }) => premiumPattern.test(line))
  .slice(-12)
  .map(({ line, index }) => `${index}: ${line.slice(0, 360)}`);
printSection("Overlay Gate Log Lines", overlayGateLines);
