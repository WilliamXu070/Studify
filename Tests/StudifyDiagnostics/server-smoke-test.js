#!/usr/bin/env node

const http = require("http");
const path = require("path");
const { spawn } = require("child_process");

const root = path.resolve(__dirname, "../..");
const port = 18787;
const host = "127.0.0.1";

function request(method, route, body) {
  return new Promise((resolve, reject) => {
    const payload = body ? Buffer.from(JSON.stringify(body)) : null;
    const req = http.request(
      {
        host,
        port,
        method,
        path: route,
        headers: payload
          ? {
              "Content-Type": "application/json",
              "Content-Length": payload.length,
            }
          : undefined,
      },
      (res) => {
        let data = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          data += chunk;
        });
        res.on("end", () => {
          let json = null;
          try {
            json = data ? JSON.parse(data) : null;
          } catch {
            // Keep raw body for debugging.
          }
          resolve({ status: res.statusCode, data, json });
        });
      }
    );
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function waitForServer() {
  const startedAt = Date.now();
  while (Date.now() - startedAt < 8000) {
    try {
      const res = await request("GET", "/v1/health");
      if (res.status === 200 && res.json?.ok) return;
    } catch {
      // Retry until timeout.
    }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  throw new Error("Timed out waiting for Studify signal server health endpoint");
}

async function main() {
  const report = [];
  const child = spawn(process.execPath, ["Tools/StudifySignalServer/server.js"], {
    cwd: root,
    env: {
      ...process.env,
      HOST: host,
      PORT: String(port),
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  let output = "";
  child.stdout.on("data", (chunk) => {
    output += chunk.toString();
  });
  child.stderr.on("data", (chunk) => {
    output += chunk.toString();
  });

  try {
    await waitForServer();

    const post = await request("POST", "/v1/jobs/playlist", {
      playlistUri: "spotify:playlist:diagnostic",
      playlistUrl: "https://open.spotify.com/playlist/diagnostic",
      deviceId: "diagnostic-node",
      deviceName: "Mac diagnostic",
      clientVersion: "studify-diagnostics-0.1",
      spotifyVersion: "diagnostic",
      sentAt: new Date().toISOString(),
      bundleIdentifier: "com.studify.diagnostic",
    });

    if (post.status !== 202 || !post.json?.ok || !post.json?.jobId) {
      throw new Error(`Expected 202 job creation, got ${post.status}: ${post.data}`);
    }

    const jobs = await request("GET", "/v1/jobs");
    if (jobs.status !== 200 || !Array.isArray(jobs.json?.jobs)) {
      throw new Error(`Expected jobs array, got ${jobs.status}: ${jobs.data}`);
    }

    if (!jobs.json.jobs.some((job) => job.id === post.json.jobId)) {
      throw new Error("Created job was not present in /v1/jobs");
    }

    const probePost = await request("POST", "/v1/probe/events", {
      deviceId: "diagnostic-node",
      sessionId: "diagnostic-probe-session",
      sequence: 7,
      hook: "row-identity",
      phase: "tap",
      message: "diagnostic row tap",
      className: "DiagnosticRow",
      selector: "layoutSubviews",
      spotifyVersion: "diagnostic",
      data: {
        uriCandidates: ["spotify:track:diagnostic"],
        slots: ["0:DiagnosticRow{trackURI=spotify:track:diagnostic}"],
      },
    });

    if (probePost.status !== 202 || !probePost.json?.ok || !probePost.json?.eventId) {
      throw new Error(`Expected 202 probe event creation, got ${probePost.status}: ${probePost.data}`);
    }

    const probes = await request("GET", "/v1/probe/events");
    if (probes.status !== 200 || !Array.isArray(probes.json?.events)) {
      throw new Error(`Expected probe events array, got ${probes.status}: ${probes.data}`);
    }

    const probe = probes.json.events.find((event) => event.id === probePost.json.eventId);
    if (!probe) {
      throw new Error("Created probe event was not present in /v1/probe/events");
    }

    if (probe.sequence !== 7 || probe.data?.uriCandidates?.[0] !== "spotify:track:diagnostic") {
      throw new Error(`Probe event lost structured trace data: ${JSON.stringify(probe)}`);
    }

    report.push("server-smoke-test: ok");
    report.push(`jobId=${post.json.jobId}`);
    report.push(`probeEventId=${probePost.json.eventId}`);
  } finally {
    const childExit = child.exitCode === null
      ? new Promise((resolve) => child.once("exit", resolve))
      : Promise.resolve();

    if (child.exitCode === null) {
      child.kill("SIGTERM");
    }

    await childExit;

    if (process.env.STUDIFY_DIAGNOSTICS_VERBOSE) {
      report.push(output.trim());
    }
  }

  process.stdout.write(report.filter(Boolean).join("\n") + "\n");
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
