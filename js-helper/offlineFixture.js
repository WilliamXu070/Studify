(function spotxOfflineFixture() {
  const fixtures = /* SPOTX_OFFLINE_FIXTURES_JSON */ {"enabled":false,"tracks":[]};
  const enabled = Boolean(fixtures && fixtures.enabled);
  const forceOffline = Boolean(fixtures && fixtures.forceOffline);
  const tracks = Array.isArray(fixtures && fixtures.tracks) ? fixtures.tracks : [];
  const patchTracks = enabled && tracks.length > 0;

  if ((!forceOffline && !patchTracks) || window.__spotxOfflineFixtureInstalled) {
    return;
  }

  window.__spotxOfflineFixtureInstalled = true;
  window.__spotxOfflineFixtures = fixtures;

  if (forceOffline) {
    try {
      Object.defineProperty(Navigator.prototype, "onLine", {
        configurable: true,
        get: function getSpotXLabOnlineState() {
          return false;
        },
      });
    } catch (error) {
      try {
        Object.defineProperty(window.navigator, "onLine", {
          configurable: true,
          get: function getSpotXLabOnlineState() {
            return false;
          },
        });
      } catch (_) {}
    }

    const originalAddEventListener = window.addEventListener;
    if (typeof originalAddEventListener === "function") {
      window.addEventListener = function patchedAddEventListener(type, listener, options) {
        if (type === "online") {
          return undefined;
        }
        return originalAddEventListener.call(this, type, listener, options);
      };
    }

    window.setTimeout(function announceSpotXLabOffline() {
      try {
        window.dispatchEvent(new Event("offline"));
      } catch (_) {}
    }, 250);
  }

  const ids = new Set();
  const uris = new Set();

  for (const track of tracks) {
    if (track && track.id) ids.add(String(track.id));
    if (track && track.uri) uris.add(String(track.uri));
    if (track && track.gid) ids.add(String(track.gid));
  }

  function getIdentity(value) {
    if (!value || typeof value !== "object") return null;
    const uri = value.uri || value.link || value.context_uri;
    const id = value.id || value.gid || value.uid;
    if (uri && uris.has(String(uri))) return String(uri);
    if (id && ids.has(String(id))) return String(id);
    return null;
  }

  function markDownloaded(value) {
    if (!value || typeof value !== "object") return value;

    if (getIdentity(value)) {
      value.downloaded = true;
      value.isDownloaded = true;
      value.is_downloaded = true;
      value.isAvailableOffline = true;
      value.is_available_offline = true;
      value.offline = true;
      value.offlinePlayable = true;
      value.offline_playable = true;
      value.downloadState = "downloaded";
      value.download_state = "downloaded";
      value.availability = value.availability || {};
      if (typeof value.availability === "object") {
        value.availability.available = true;
        value.availability.offline = true;
      }
    }

    if (value.track && typeof value.track === "object") {
      markDownloaded(value.track);
    }
    if (value.item && typeof value.item === "object") {
      markDownloaded(value.item);
    }

    return value;
  }

  function walk(value, depth) {
    if (!value || depth > 8) return value;
    if (Array.isArray(value)) {
      for (const item of value) walk(item, depth + 1);
      return value;
    }
    if (typeof value !== "object") return value;

    markDownloaded(value);
    for (const key of Object.keys(value)) {
      const child = value[key];
      if (child && typeof child === "object") walk(child, depth + 1);
    }
    return value;
  }

  const originalFetch = window.fetch;
  if (patchTracks && typeof originalFetch === "function") {
    window.fetch = async function patchedFetch(input, init) {
      const response = await originalFetch.call(this, input, init);
      const contentType = response.headers && response.headers.get && response.headers.get("content-type");
      if (!contentType || !contentType.includes("application/json")) {
        return response;
      }

      try {
        const data = await response.clone().json();
        walk(data, 0);
        const headers = new Headers(response.headers);
        headers.set("content-type", "application/json");
        return new Response(JSON.stringify(data), {
          status: response.status,
          statusText: response.statusText,
          headers,
        });
      } catch (error) {
        return response;
      }
    };
  }

  console.info("[SpotX Lab] Offline fixture hook enabled", {
    forceOffline,
    tracks,
  });
})();
