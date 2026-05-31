(function spotxOfflineFixture() {
  const fixtures = /* SPOTX_OFFLINE_FIXTURES_JSON */ {"enabled":false,"tracks":[]};
  const enabled = Boolean(fixtures && fixtures.enabled);
  const forceOffline = Boolean(fixtures && fixtures.forceOffline);
  const showMarkers = fixtures && fixtures.showMarkers !== false;
  const tracks = Array.isArray(fixtures && fixtures.tracks) ? fixtures.tracks : [];
  const patchTracks = enabled && tracks.length > 0;

  if ((!forceOffline && !patchTracks) || window.__spotxOfflineFixtureInstalled) {
    return;
  }

  window.__spotxOfflineFixtureInstalled = true;
  window.__spotxOfflineFixtures = fixtures;

  function normalize(value) {
    return String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  }

  function toArray(value) {
    if (!value) return [];
    return Array.isArray(value) ? value : [value];
  }

  function readNameList(value) {
    if (!value) return [];
    if (Array.isArray(value)) {
      return value
        .map(function mapArtist(item) {
          if (!item) return "";
          return typeof item === "string" ? item : item.name || item.title || "";
        })
        .filter(Boolean);
    }
    if (typeof value === "string") return [value];
    return [value.name || value.title || ""].filter(Boolean);
  }

  const compiledTracks = tracks
    .map(function compileTrack(track) {
      const names = toArray(track && (track.title || track.name)).map(normalize).filter(Boolean);
      const artists = toArray(track && (track.artist || track.artists)).map(normalize).filter(Boolean);
      const albums = toArray(track && track.album).map(normalize).filter(Boolean);
      return {
        raw: track,
        ids: new Set(toArray(track && (track.id || track.gid || track.uid)).map(String).filter(Boolean)),
        uris: new Set(toArray(track && (track.uri || track.link || track.context_uri)).map(String).filter(Boolean)),
        isrcs: new Set(toArray(track && track.isrc).map(String).filter(Boolean)),
        names,
        artists,
        albums,
      };
    })
    .filter(function keepTrack(track) {
      return (
        track.ids.size > 0 ||
        track.uris.size > 0 ||
        track.isrcs.size > 0 ||
        track.names.length > 0
      );
    });

  function installOfflineSignals() {
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
        if (type === "online") return undefined;
        return originalAddEventListener.call(this, type, listener, options);
      };
    }

    window.setTimeout(function announceSpotXLabOffline() {
      try {
        window.dispatchEvent(new Event("offline"));
      } catch (_) {}
    }, 250);
  }

  if (forceOffline) {
    installOfflineSignals();
  }

  function getObjectUri(value) {
    return value && (value.uri || value.link || value.context_uri || value.track_uri || value.trackUri);
  }

  function getObjectId(value) {
    return value && (value.id || value.gid || value.uid || value.track_id || value.trackId);
  }

  function getObjectIsrc(value) {
    return (
      value &&
      (value.isrc ||
        (value.external_ids && value.external_ids.isrc) ||
        (value.externalIds && value.externalIds.isrc))
    );
  }

  function getObjectName(value) {
    return value && (value.name || value.title || value.trackName || value.track_name);
  }

  function getObjectAlbum(value) {
    if (!value) return "";
    const album = value.album || value.albumOfTrack || value.release;
    if (!album) return "";
    return typeof album === "string" ? album : album.name || album.title || "";
  }

  function getObjectArtists(value) {
    if (!value) return [];
    return readNameList(value.artists || value.artist || value.artistName || value.artist_names);
  }

  function textMatches(haystack, needle) {
    return Boolean(haystack && needle && (haystack === needle || haystack.includes(needle)));
  }

  function matchesCompiledTrack(value, compiled) {
    if (!value || typeof value !== "object") return false;

    const uri = getObjectUri(value);
    if (uri && compiled.uris.has(String(uri))) return true;

    const id = getObjectId(value);
    if (id && compiled.ids.has(String(id))) return true;

    const isrc = getObjectIsrc(value);
    if (isrc && compiled.isrcs.has(String(isrc))) return true;

    const objectName = normalize(getObjectName(value));
    if (!compiled.names.some(function hasName(name) { return textMatches(objectName, name); })) {
      return false;
    }

    if (compiled.artists.length > 0) {
      const objectArtists = getObjectArtists(value).map(normalize).join(" ");
      if (!compiled.artists.some(function hasArtist(artist) { return textMatches(objectArtists, artist); })) {
        return false;
      }
    }

    if (compiled.albums.length > 0) {
      const objectAlbum = normalize(getObjectAlbum(value));
      if (!compiled.albums.some(function hasAlbum(album) { return textMatches(objectAlbum, album); })) {
        return false;
      }
    }

    return true;
  }

  function getMatchedFixture(value) {
    if (!value || typeof value !== "object") return null;
    for (const compiled of compiledTracks) {
      if (matchesCompiledTrack(value, compiled)) return compiled.raw || {};
    }
    return null;
  }

  function markDownloaded(value, fixture) {
    if (!value || typeof value !== "object") return value;

    const state = (fixture && fixture.downloadState) || "downloaded";
    value.downloaded = true;
    value.isDownloaded = true;
    value.is_downloaded = true;
    value.isAvailableOffline = true;
    value.is_available_offline = true;
    value.availableOffline = true;
    value.available_offline = true;
    value.offline = true;
    value.offlinePlayable = true;
    value.offline_playable = true;
    value.playableOffline = true;
    value.playable_offline = true;
    value.playable = true;
    value.isPlayable = true;
    value.is_playable = true;
    value.available = true;
    value.isAvailable = true;
    value.is_available = true;
    value.unavailable = false;
    value.isUnavailable = false;
    value.is_unavailable = false;
    value.downloadState = state;
    value.download_state = state;
    value.offlineState = state;
    value.offline_state = state;
    value.availability = value.availability || {};
    if (typeof value.availability === "object") {
      value.availability.available = true;
      value.availability.playable = true;
      value.availability.offline = true;
      value.availability.unavailable = false;
    }
    value.restrictions = Array.isArray(value.restrictions) ? [] : value.restrictions;
    value.offlineLab = true;
    value.spotxLabOffline = true;

    return value;
  }

  function walk(value, depth) {
    if (!value || depth > 10) return value;
    if (Array.isArray(value)) {
      for (const item of value) walk(item, depth + 1);
      return value;
    }
    if (typeof value !== "object") return value;

    const fixture = getMatchedFixture(value);
    if (fixture) markDownloaded(value, fixture);

    if (value.track && typeof value.track === "object") {
      const trackFixture = getMatchedFixture(value.track);
      if (trackFixture) {
        markDownloaded(value.track, trackFixture);
        markDownloaded(value, trackFixture);
      }
    }
    if (value.item && typeof value.item === "object") {
      const itemFixture = getMatchedFixture(value.item);
      if (itemFixture) {
        markDownloaded(value.item, itemFixture);
        markDownloaded(value, itemFixture);
      }
    }

    for (const key of Object.keys(value)) {
      const child = value[key];
      if (child && typeof child === "object") walk(child, depth + 1);
    }
    return value;
  }

  function patchData(data) {
    if (!patchTracks) return data;
    try {
      return walk(data, 0);
    } catch (_) {
      return data;
    }
  }

  const originalFetch = window.fetch;
  if (patchTracks && typeof originalFetch === "function") {
    window.fetch = async function patchedFetch(input, init) {
      const response = await originalFetch.call(this, input, init);
      const contentType = response.headers && response.headers.get && response.headers.get("content-type");
      if (!contentType || !contentType.includes("application/json")) return response;

      try {
        const data = patchData(await response.clone().json());
        const headers = new Headers(response.headers);
        headers.set("content-type", "application/json");
        return new Response(JSON.stringify(data), {
          status: response.status,
          statusText: response.statusText,
          headers,
        });
      } catch (_) {
        return response;
      }
    };
  }

  if (patchTracks && window.Response && window.Response.prototype) {
    const originalJson = window.Response.prototype.json;
    if (typeof originalJson === "function") {
      window.Response.prototype.json = function patchedResponseJson() {
        return originalJson.call(this).then(patchData);
      };
    }
  }

  if (patchTracks && window.JSON && typeof window.JSON.parse === "function") {
    const originalParse = window.JSON.parse;
    window.JSON.parse = function patchedJsonParse(text, reviver) {
      const data = originalParse.call(this, text, reviver);
      if (typeof text === "string" && text.length < 3000000) patchData(data);
      return data;
    };
  }

  function rowMatchesFixture(row, compiled) {
    const text = normalize(row && row.textContent);
    if (!text) return false;
    if (!compiled.names.some(function hasName(name) { return textMatches(text, name); })) return false;
    if (compiled.artists.length === 0) return true;
    return compiled.artists.some(function hasArtist(artist) { return textMatches(text, artist); });
  }

  function ensureStyle() {
    if (document.getElementById("spotx-lab-offline-fixture-style")) return;
    const style = document.createElement("style");
    style.id = "spotx-lab-offline-fixture-style";
    style.textContent = [
      "[data-spotx-lab-offline-row='true']{outline:1px solid rgba(30,215,96,.35);outline-offset:-1px;}",
      "[data-spotx-lab-download-marker]{display:inline-flex;align-items:center;gap:6px;margin-left:8px;padding:2px 7px;border-radius:999px;background:rgba(30,215,96,.16);color:#1ed760;font-size:11px;font-weight:700;line-height:16px;vertical-align:middle;}",
      "[data-spotx-lab-download-marker]::before{content:'';width:6px;height:6px;border-radius:50%;background:#1ed760;display:inline-block;}",
    ].join("");
    document.documentElement.appendChild(style);
  }

  function addMarker(row) {
    if (!row || row.querySelector("[data-spotx-lab-download-marker]")) return;
    row.setAttribute("data-spotx-lab-offline-row", "true");
    const marker = document.createElement("span");
    marker.setAttribute("data-spotx-lab-download-marker", "true");
    marker.textContent = "Offline lab";
    const target =
      row.querySelector("[data-testid='internal-track-link']") ||
      row.querySelector("a[href*='track']") ||
      row.querySelector("[dir='auto']") ||
      row;
    target.appendChild(marker);
  }

  function scanDom() {
    if (!showMarkers || !patchTracks || !document.body) return;
    ensureStyle();
    const selector = [
      "[data-testid='tracklist-row']",
      "[role='row']",
      "[aria-rowindex]",
      "[data-testid='now-playing-widget']",
      "[data-testid='context-item-info-title']",
    ].join(",");
    const rows = document.querySelectorAll(selector);
    for (const row of rows) {
      for (const compiled of compiledTracks) {
        if (rowMatchesFixture(row, compiled)) {
          addMarker(row);
          break;
        }
      }
    }
  }

  if (showMarkers && patchTracks) {
    window.setInterval(scanDom, 1500);
    const observer = new MutationObserver(scanDom);
    window.setTimeout(function startObserver() {
      if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true, characterData: true });
        scanDom();
      }
    }, 500);
  }

  console.info("[SpotX Lab] Offline fixture hook enabled", {
    forceOffline,
    showMarkers,
    tracks,
  });
})();
