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

function section(source, startNeedle, endNeedle) {
  const start = source.indexOf(startNeedle);
  assert(start >= 0, `Missing section start: ${startNeedle}`);
  const end = source.indexOf(endNeedle, start + startNeedle.length);
  assert(end >= 0, `Missing section end: ${endNeedle}`);
  return source.slice(start, end);
}

const tweak = read("Sources/EeveeSpotify/Tweak.x.swift");
const serverSidedReminder = read("Sources/EeveeSpotify/Premium/ServerSidedReminder.x.swift");
const bundleHelper = read("Sources/EeveeSpotify/Premium/Helpers/BundleHelper.swift");
const signalClient = read("Sources/EeveeSpotify/Studify/StudifyDownloadSignalClient.swift");

const activator = section(
  tweak,
  "func activateV91StudifyDownloadSignalGroup()",
  "func activatePremiumPatchingGroup()"
);

assert(
  activator.includes("Offline helper hook target missing") &&
    activator.includes("V91StudifyDownloadButtonFallbackGroup().activate()"),
  "v91 fallback must activate even when the offline helper class is missing"
);

const fallbackHook = section(
  serverSidedReminder,
  "class V91StudifyDownloadButtonFallbackHook",
  "\n}"
);

assert(
  fallbackHook.includes("@objc(sendAction:to:forEvent:)"),
  "UIControl fallback must hook the real UIKit selector sendAction:to:forEvent:"
);

assert(
  fallbackHook.indexOf("sendStudifyFallbackDownloadSignal(from: target)") >= 0 &&
    fallbackHook.indexOf("orig.sendAction(action, to: receiver, for: event)", fallbackHook.indexOf("sendStudifyFallbackDownloadSignal(from: target)")) >= 0,
  "UIControl fallback must pass through to the original action after sending the Studify signal"
);

assert(
  fallbackHook.includes("StudifyDebugVisualAid.controlHookActive") &&
    serverSidedReminder.includes("didShowStudifyFallbackProbe"),
  "UIControl fallback must show a one-time probe banner so device tests can prove the hook loaded"
);

assert(
  bundleHelper.includes("liveContainerBundlePath") &&
    bundleHelper.includes("_dyld_get_image_name") &&
    bundleHelper.includes("EeveeSpotify.dylib"),
  "BundleHelper must include LiveContainer bundle lookup beside EeveeSpotify.dylib"
);

assert(
  signalClient.includes("v1/jobs/playlist") &&
    signalClient.includes("URLSession.shared.dataTask"),
  "Studify signal client must still POST to the playlist job endpoint"
);

const studifyReferences = [];
for (const file of [
  "Sources/EeveeSpotify/Tweak.x.swift",
  "Sources/EeveeSpotify/Premium/ServerSidedReminder.x.swift",
  "Sources/EeveeSpotify/Premium/DynamicPremium+PremiumPlanRow.swift",
  "Sources/EeveeSpotify/Premium/Helpers/BundleHelper.swift",
  "Sources/EeveeSpotify/Studify/StudifyDownloadSignalClient.swift",
  "Sources/EeveeSpotify/Studify/StudifyDebugVisualAid.swift",
]) {
  if (read(file).includes("Studify") || read(file).includes("STUDIFY")) {
    studifyReferences.push(file);
  }
}

console.log("source-regression-test: ok");
console.log(`Studify source touchpoints (${studifyReferences.length}):`);
for (const file of studifyReferences) {
  console.log(`- ${file}`);
}
