#!/usr/bin/env node

const http = require("http");
const crypto = require("crypto");
const os = require("os");

const port = Number(process.env.PORT || 8787);
const host = process.env.HOST || "0.0.0.0";

const jobs = new Map();
const clients = new Set();
const probeEvents = [];
const maxProbeEvents = Number(process.env.MAX_PROBE_EVENTS || 500);

function nowISO() {
  return new Date().toISOString();
}

function makeJobId() {
  if (typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `job_${Date.now()}_${Math.random().toString(36).slice(2)}`;
}

function publicBaseUrl() {
  const interfaces = os.networkInterfaces();
  for (const entries of Object.values(interfaces)) {
    for (const entry of entries || []) {
      if (entry.family === "IPv4" && !entry.internal) {
        return `http://${entry.address}:${port}`;
      }
    }
  }
  return `http://127.0.0.1:${port}`;
}

function sendJson(res, status, body) {
  const payload = JSON.stringify(body, null, 2);
  res.writeHead(status, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

function sendText(res, status, body, contentType = "text/plain; charset=utf-8") {
  res.writeHead(status, {
    "Access-Control-Allow-Origin": "*",
    "Content-Type": contentType,
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1024 * 1024) {
        reject(new Error("Request body too large"));
        req.destroy();
      }
    });
    req.on("end", () => {
      if (!body.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch (error) {
        reject(new Error(`Invalid JSON: ${error.message}`));
      }
    });
    req.on("error", reject);
  });
}

function broadcast(event, payload) {
  const body = `event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`;
  for (const client of clients) {
    client.write(body);
  }
}

function recordProbeEvent(payload, req) {
  const event = {
    id: makeJobId(),
    at: nowISO(),
    remoteAddress: req.socket.remoteAddress,
    deviceId: String(payload.deviceId || "unknown-device"),
    sessionId: String(payload.sessionId || "default"),
    hook: String(payload.hook || "unknown-hook"),
    phase: String(payload.phase || "hit"),
    message: String(payload.message || ""),
    className: String(payload.className || ""),
    selector: String(payload.selector || ""),
    spotifyVersion: String(payload.spotifyVersion || "unknown"),
    data: payload.data && typeof payload.data === "object" ? payload.data : {},
  };

  probeEvents.push(event);
  while (probeEvents.length > maxProbeEvents) {
    probeEvents.shift();
  }

  broadcast("probe.event", event);
  return event;
}

function updateJob(jobId, patch) {
  const job = jobs.get(jobId);
  if (!job) {
    return;
  }

  Object.assign(job, patch, { updatedAt: nowISO() });
  job.timeline.push({
    at: job.updatedAt,
    state: job.state,
    message: patch.message || `State changed to ${job.state}`,
  });

  broadcast("job.updated", job);
}

function simulateJob(jobId) {
  const steps = [
    [750, { state: "resolving_playlist", progress: 20, message: "Resolving playlist metadata" }],
    [1750, { state: "manifest_ready", progress: 45, message: "Generated simulated track manifest" }],
    [3000, { state: "searching_sources", progress: 65, message: "Simulating source lookup queue" }],
    [4300, { state: "ready_to_download", progress: 90, message: "Files are ready for device download" }],
    [5600, { state: "completed", progress: 100, message: "Demo job complete" }],
  ];

  for (const [delay, patch] of steps) {
    setTimeout(() => updateJob(jobId, patch), delay);
  }
}

function createJob(payload, req) {
  const jobId = makeJobId();
  const playlistUri = String(payload.playlistUri || "");
  const playlistUrl = String(payload.playlistUrl || "");

  const job = {
    id: jobId,
    state: "queued",
    progress: 5,
    playlistUri,
    playlistUrl,
    deviceId: String(payload.deviceId || "unknown-device"),
    clientVersion: String(payload.clientVersion || "unknown-client"),
    remoteAddress: req.socket.remoteAddress,
    createdAt: nowISO(),
    updatedAt: nowISO(),
    message: "Job queued",
    tracks: [
      {
        index: 1,
        title: "Demo Track One",
        artist: "Studify Local",
        status: "matched",
        sizeBytes: 7340032,
      },
      {
        index: 2,
        title: "Demo Track Two",
        artist: "Studify Local",
        status: "matched",
        sizeBytes: 6815744,
      },
      {
        index: 3,
        title: "Demo Track Three",
        artist: "Studify Local",
        status: "pending",
        sizeBytes: 0,
      },
    ],
    timeline: [],
  };

  job.timeline.push({
    at: job.createdAt,
    state: job.state,
    message: job.message,
  });

  jobs.set(jobId, job);
  broadcast("job.created", job);
  simulateJob(jobId);

  return job;
}

function csvEscape(value) {
  const text = String(value ?? "");
  if (/[",\n]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

function manifestCsv(job) {
  const rows = [["index", "title", "artist", "status", "sizeBytes"]];
  for (const track of job.tracks) {
    rows.push([
      track.index,
      track.title,
      track.artist,
      track.status,
      track.sizeBytes,
    ]);
  }
  return rows.map((row) => row.map(csvEscape).join(",")).join("\n") + "\n";
}

function dashboardHtml() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Studify Signal Server</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #101214;
      --panel: #171a1d;
      --panel-2: #202428;
      --text: #f3f5f7;
      --muted: #9aa4ad;
      --line: #30363d;
      --accent: #1ed760;
      --warning: #f5c451;
      --danger: #ff6b6b;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--text);
    }
    main {
      width: min(1180px, calc(100vw - 32px));
      margin: 0 auto;
      padding: 28px 0 40px;
    }
    header {
      display: flex;
      align-items: flex-end;
      justify-content: space-between;
      gap: 20px;
      margin-bottom: 24px;
    }
    h1 {
      margin: 0 0 6px;
      font-size: 28px;
      line-height: 1.1;
      letter-spacing: 0;
    }
    p {
      margin: 0;
      color: var(--muted);
      line-height: 1.5;
    }
    code {
      padding: 2px 6px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel-2);
      color: var(--text);
    }
    .status {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      white-space: nowrap;
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 8px 12px;
      color: var(--muted);
      background: var(--panel);
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 999px;
      background: var(--accent);
    }
    .grid {
      display: grid;
      grid-template-columns: minmax(0, 1.6fr) minmax(320px, 0.8fr);
      gap: 16px;
    }
    .full {
      margin-top: 16px;
    }
    section {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      overflow: hidden;
    }
    section h2 {
      margin: 0;
      padding: 14px 16px;
      border-bottom: 1px solid var(--line);
      font-size: 15px;
      letter-spacing: 0;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      table-layout: fixed;
    }
    th, td {
      padding: 12px 14px;
      border-bottom: 1px solid var(--line);
      text-align: left;
      vertical-align: top;
      font-size: 13px;
    }
    th {
      color: var(--muted);
      font-weight: 600;
    }
    td {
      overflow-wrap: anywhere;
    }
    .chip {
      display: inline-flex;
      border-radius: 999px;
      padding: 3px 8px;
      background: #193625;
      color: #8ff0b2;
      font-size: 12px;
      white-space: nowrap;
    }
    .chip.progress { background: #332c18; color: var(--warning); }
    .chip.fail { background: #3a1f24; color: var(--danger); }
    .empty {
      padding: 28px 16px;
      color: var(--muted);
    }
    .events {
      height: 420px;
      overflow: auto;
      padding: 12px;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 12px;
      line-height: 1.5;
      color: #d8dee5;
    }
    .probe-events {
      height: 520px;
    }
    .event {
      padding: 8px;
      margin-bottom: 8px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: #121518;
    }
    .event.probe {
      border-left: 3px solid var(--accent);
    }
    .event strong {
      color: var(--text);
    }
    .event .meta {
      color: var(--muted);
      margin-top: 4px;
      overflow-wrap: anywhere;
    }
    pre {
      overflow-x: auto;
      margin: 0;
      padding: 14px 16px;
      color: #d8dee5;
      font-size: 12px;
      line-height: 1.5;
    }
    @media (max-width: 820px) {
      header { display: block; }
      .status { margin-top: 14px; }
      .grid { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>Studify Signal Server</h1>
        <p>Waiting for playlist download signals from the tweak. Local URL: <code>${publicBaseUrl()}</code></p>
      </div>
      <div class="status"><span class="dot"></span><span id="connection">connected</span></div>
    </header>

    <div class="grid">
      <section>
        <h2>Jobs</h2>
        <div id="jobs"></div>
      </section>
      <section>
        <h2>Live Events</h2>
        <div id="events" class="events"></div>
      </section>
    </div>

    <section class="full">
      <h2>Probe Stream</h2>
      <div id="probeEvents" class="events probe-events"></div>
    </section>

    <section style="margin-top: 16px;">
      <h2>Manual Test</h2>
      <pre>curl -X POST ${publicBaseUrl()}/v1/jobs/playlist \\
  -H 'Content-Type: application/json' \\
  -d '{"playlistUri":"spotify:playlist:demo","playlistUrl":"https://open.spotify.com/playlist/demo","deviceId":"mac-manual-test","clientVersion":"studify-ios-0.1"}'</pre>
    </section>
  </main>

  <script>
    const jobs = new Map();
    const jobsEl = document.getElementById("jobs");
    const eventsEl = document.getElementById("events");
    const probeEventsEl = document.getElementById("probeEvents");
    const connectionEl = document.getElementById("connection");

    function chipClass(state) {
      if (state === "failed" || state === "partial") return "chip fail";
      if (state === "completed" || state === "ready_to_download") return "chip";
      return "chip progress";
    }

    function renderJobs() {
      const list = Array.from(jobs.values()).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
      if (list.length === 0) {
        jobsEl.innerHTML = '<div class="empty">No jobs yet. Tap the playlist download button in Spotify or run the curl command below.</div>';
        return;
      }

      jobsEl.innerHTML = '<table><thead><tr><th>State</th><th>Playlist</th><th>Device</th><th>Progress</th><th>Updated</th></tr></thead><tbody>' +
        list.map((job) => {
          const playlist = job.playlistUrl || job.playlistUri || "(missing playlist)";
          return '<tr>' +
            '<td><span class="' + chipClass(job.state) + '">' + job.state + '</span></td>' +
            '<td>' + escapeHtml(playlist) + '<br><code>' + escapeHtml(job.id) + '</code></td>' +
            '<td>' + escapeHtml(job.deviceId) + '<br><span style="color:var(--muted)">' + escapeHtml(job.clientVersion) + '</span></td>' +
            '<td>' + Number(job.progress || 0) + '%</td>' +
            '<td>' + escapeHtml(job.updatedAt) + '</td>' +
          '</tr>';
        }).join("") +
        '</tbody></table>';
    }

    function addEvent(name, job) {
      const div = document.createElement("div");
      div.className = "event";
      div.textContent = new Date().toISOString() + " " + name + " " + job.id + " " + job.state + " " + (job.message || "");
      eventsEl.prepend(div);
    }

    function addProbeEvent(probe) {
      const div = document.createElement("div");
      div.className = "event probe";

      const title = document.createElement("div");
      title.innerHTML = '<strong>' + escapeHtml(probe.hook) + '</strong> ' +
        '<span style="color:var(--accent)">' + escapeHtml(probe.phase) + '</span> ' +
        escapeHtml(probe.message || "");

      const meta = document.createElement("div");
      meta.className = "meta";
      meta.textContent = probe.at + " | " + probe.deviceId + " | " +
        (probe.className || "-") + " | " + (probe.selector || "-") +
        " | " + JSON.stringify(probe.data || {});

      div.appendChild(title);
      div.appendChild(meta);
      probeEventsEl.prepend(div);

      while (probeEventsEl.children.length > 200) {
        probeEventsEl.lastElementChild.remove();
      }
    }

    function escapeHtml(value) {
      return String(value).replace(/[&<>"']/g, (char) => ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#039;",
      }[char]));
    }

    async function loadJobs() {
      const response = await fetch("/v1/jobs");
      const data = await response.json();
      jobs.clear();
      for (const job of data.jobs) jobs.set(job.id, job);
      renderJobs();
    }

    async function loadProbeEvents() {
      const response = await fetch("/v1/probe/events");
      const data = await response.json();
      probeEventsEl.innerHTML = "";
      for (const probe of data.events.slice().reverse()) addProbeEvent(probe);
    }

    function startEvents() {
      const events = new EventSource("/events");
      events.onopen = () => { connectionEl.textContent = "connected"; };
      events.onerror = () => { connectionEl.textContent = "reconnecting"; };
      events.addEventListener("job.created", (event) => {
        const job = JSON.parse(event.data);
        jobs.set(job.id, job);
        addEvent("created", job);
        renderJobs();
      });
      events.addEventListener("job.updated", (event) => {
        const job = JSON.parse(event.data);
        jobs.set(job.id, job);
        addEvent("updated", job);
        renderJobs();
      });
      events.addEventListener("probe.event", (event) => {
        addProbeEvent(JSON.parse(event.data));
      });
    }

    loadJobs();
    loadProbeEvents();
    startEvents();
  </script>
</body>
</html>`;
}

function route(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type,Authorization",
    });
    res.end();
    return;
  }

  if (req.method === "GET" && url.pathname === "/") {
    sendText(res, 200, dashboardHtml(), "text/html; charset=utf-8");
    return;
  }

  if (req.method === "GET" && url.pathname === "/events") {
    res.writeHead(200, {
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
      "Content-Type": "text/event-stream",
    });
    res.write(`event: connected\ndata: ${JSON.stringify({ at: nowISO() })}\n\n`);
    clients.add(res);
    req.on("close", () => clients.delete(res));
    return;
  }

  if (req.method === "GET" && url.pathname === "/v1/health") {
    sendJson(res, 200, {
      ok: true,
      at: nowISO(),
      jobs: jobs.size,
      probeEvents: probeEvents.length,
      publicBaseUrl: publicBaseUrl(),
    });
    return;
  }

  if (req.method === "GET" && url.pathname === "/v1/jobs") {
    sendJson(res, 200, {
      jobs: Array.from(jobs.values()),
    });
    return;
  }

  if (req.method === "GET" && url.pathname === "/v1/probe/events") {
    sendJson(res, 200, {
      ok: true,
      events: probeEvents.slice(-maxProbeEvents),
    });
    return;
  }

  if (req.method === "POST" && url.pathname === "/v1/probe/events") {
    readJsonBody(req)
      .then((payload) => {
        const event = recordProbeEvent(payload, req);
        sendJson(res, 202, {
          ok: true,
          eventId: event.id,
        });
      })
      .catch((error) => {
        sendJson(res, 400, {
          ok: false,
          error: error.message,
        });
      });
    return;
  }

  if (req.method === "POST" && url.pathname === "/v1/jobs/playlist") {
    readJsonBody(req)
      .then((payload) => {
        const job = createJob(payload, req);
        sendJson(res, 202, {
          ok: true,
          jobId: job.id,
          state: job.state,
          statusUrl: `/v1/jobs/${job.id}`,
          manifestUrl: `/v1/jobs/${job.id}/manifest.csv`,
        });
      })
      .catch((error) => {
        sendJson(res, 400, {
          ok: false,
          error: error.message,
        });
      });
    return;
  }

  const jobMatch = url.pathname.match(/^\/v1\/jobs\/([^/]+)$/);
  if (req.method === "GET" && jobMatch) {
    const job = jobs.get(jobMatch[1]);
    if (!job) {
      sendJson(res, 404, { ok: false, error: "Job not found" });
      return;
    }
    sendJson(res, 200, { ok: true, job });
    return;
  }

  const manifestMatch = url.pathname.match(/^\/v1\/jobs\/([^/]+)\/manifest\.csv$/);
  if (req.method === "GET" && manifestMatch) {
    const job = jobs.get(manifestMatch[1]);
    if (!job) {
      sendJson(res, 404, { ok: false, error: "Job not found" });
      return;
    }
    sendText(res, 200, manifestCsv(job), "text/csv; charset=utf-8");
    return;
  }

  sendJson(res, 404, {
    ok: false,
    error: "Not found",
  });
}

const server = http.createServer(route);

server.listen(port, host, () => {
  console.log(`Studify signal server listening on ${publicBaseUrl()}`);
  console.log(`Dashboard: ${publicBaseUrl()}/`);
});
