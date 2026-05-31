(function spotxOfflineFixture() {
  const fixtures = /* SPOTX_OFFLINE_FIXTURES_JSON */ {"enabled":false,"tracks":[]};
  const enabled = Boolean(fixtures && fixtures.enabled);
  const forceOffline = Boolean(fixtures && fixtures.forceOffline);
  const showMarkers = Boolean(fixtures && fixtures.showMarkers);
  const probe = Boolean(fixtures && fixtures.probe);
  const deepElementPatch = Boolean(fixtures && fixtures.deepElementPatch);
  const patchNetworkData = Boolean(fixtures && fixtures.patchNetworkData);
  const tracks = Array.isArray(fixtures && fixtures.tracks) ? fixtures.tracks : [];
  const patchTracks = enabled && tracks.length > 0;

  if ((!forceOffline && !patchTracks) || window.__spotxOfflineFixtureInstalled) {
    return;
  }

  window.__spotxOfflineFixtureInstalled = true;
  window.__spotxOfflineFixtures = fixtures;
  window.__spotxOfflineFixtureReport = window.__spotxOfflineFixtureReport || {
    matchedObjects: [],
    patchedObjects: 0,
    downloadKeys: {},
    discoveredUris: [],
    seenAvailabilityUris: [],
    nativeAvailabilityHits: [],
    nativePatches: [],
    rowPlayabilityPatches: [],
    elementPlayabilityPatches: [],
    rowClickIntercepts: [],
    messages: [],
  };

  function recordMessage(message, payload) {
    if (!probe) return;
    const report = window.__spotxOfflineFixtureReport;
    report.messages.push({
      time: Date.now(),
      message,
      payload,
    });
    if (report.messages.length > 200) report.messages.shift();
  }

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
  const fixtureUris = new Set();
  const nativeServices = new Set();
  const nativeState = {
    yes: "yes",
    updateAvailability: "update_availability",
  };
  const elementPatchCache = new WeakMap();
  let scanScheduled = false;

  function pushUniqueReportList(name, value, limit) {
    if (!probe) return;
    const report = window.__spotxOfflineFixtureReport;
    if (!Array.isArray(report[name])) report[name] = [];
    report[name].push(value);
    while (report[name].length > limit) report[name].shift();
  }

  function getTrackIdFromUri(uri) {
    const text = String(uri || "");
    const spotifyMatch = text.match(/^spotify:track:([^:?/#]+)/i);
    if (spotifyMatch) return spotifyMatch[1];
    const urlMatch = text.match(/\/track\/([^?/#]+)/i);
    if (urlMatch) return urlMatch[1];
    return "";
  }

  function toSpotifyTrackUri(value) {
    const text = String(value || "").trim();
    if (!text) return "";
    if (/^spotify:track:/i.test(text)) return text;
    const id = getTrackIdFromUri(text);
    if (id) return "spotify:track:" + id;
    if (/^[A-Za-z0-9]{16,32}$/.test(text)) return "spotify:track:" + text;
    return text;
  }

  function addFixtureUri(uri, source) {
    const spotifyUri = toSpotifyTrackUri(uri);
    if (!spotifyUri || fixtureUris.has(spotifyUri)) return false;
    fixtureUris.add(spotifyUri);
    pushUniqueReportList("discoveredUris", { time: Date.now(), uri: spotifyUri, source }, 100);
    for (const service of nativeServices) {
      forceServiceAvailability(service, spotifyUri, source || "fixture-uri");
    }
    return true;
  }

  function uriMatchesFixture(uri) {
    const spotifyUri = toSpotifyTrackUri(uri);
    if (spotifyUri && fixtureUris.has(spotifyUri)) return true;
    const id = getTrackIdFromUri(spotifyUri);
    if (!id) return false;
    return compiledTracks.some(function hasMatchingId(track) {
      return track.ids.has(id) || track.uris.has(spotifyUri);
    });
  }

  function getFixtureUriFromText(text) {
    const normalized = normalize(text);
    if (!normalized) return "";
    for (const compiled of compiledTracks) {
      if (!compiled.names.some(function hasName(name) { return textMatches(normalized, name); })) continue;
      if (compiled.artists.length > 0) {
        if (!compiled.artists.some(function hasArtist(artist) { return textMatches(normalized, artist); })) continue;
      }
      for (const uri of compiled.uris) return toSpotifyTrackUri(uri);
      for (const id of compiled.ids) return toSpotifyTrackUri(id);
    }
    return "";
  }

  for (const compiled of compiledTracks) {
    compiled.uris.forEach(function seedUri(uri) { addFixtureUri(uri, "configured-uri"); });
    compiled.ids.forEach(function seedId(id) { addFixtureUri("spotify:track:" + id, "configured-id"); });
  }

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
    const completeStates = ["downloaded", "complete", "completed", "done", "available", "cached"];
    value.downloaded = true;
    value.isDownloaded = true;
    value.is_downloaded = true;
    value.isDownloadedAndPlayable = true;
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
    value.downloadStatus = state;
    value.download_status = state;
    value.downloadedState = state;
    value.downloaded_state = state;
    value.offlineState = state;
    value.offline_state = state;
    value.offlineStatus = state;
    value.offline_status = state;
    value.cacheState = state;
    value.cache_state = state;
    value.cached = true;
    value.inCache = true;
    value.in_cache = true;
    value.locallyAvailable = true;
    value.locally_available = true;
    value.local = true;
    value.isLocal = false;
    value.is_local = false;
    value.availability = value.availability || {};
    if (typeof value.availability === "object") {
      value.availability.available = true;
      value.availability.playable = true;
      value.availability.offline = true;
      value.availability.unavailable = false;
    }
    value.download = value.download || {};
    if (typeof value.download === "object") {
      value.download.state = state;
      value.download.status = state;
      value.download.progress = 1;
      value.download.percent = 100;
      value.download.downloaded = true;
      value.download.complete = true;
      value.download.completed = true;
      value.download.available = true;
    }
    value.offlineAvailability = value.offlineAvailability || {};
    if (typeof value.offlineAvailability === "object") {
      value.offlineAvailability.state = state;
      value.offlineAvailability.status = state;
      value.offlineAvailability.available = true;
      value.offlineAvailability.playable = true;
    }
    value.offlineStorage = value.offlineStorage || {};
    if (typeof value.offlineStorage === "object") {
      value.offlineStorage.state = state;
      value.offlineStorage.status = state;
      value.offlineStorage.cached = true;
      value.offlineStorage.available = true;
    }
    value.progress = typeof value.progress === "number" ? Math.max(value.progress, 1) : value.progress;
    value.downloadProgress = 1;
    value.download_progress = 1;
    value.downloadPercentage = 100;
    value.download_percentage = 100;
    value.downloadStatusCode = 3;
    value.offlineStatusCode = 3;
    value.downloadStates = completeStates;
    value.restrictions = Array.isArray(value.restrictions) ? [] : value.restrictions;
    value.offlineLab = true;
    value.spotxLabOffline = true;

    if (probe) {
      const report = window.__spotxOfflineFixtureReport;
      report.patchedObjects += 1;
      report.matchedObjects.push({
        time: Date.now(),
        name: getObjectName(value),
        artists: getObjectArtists(value),
        uri: getObjectUri(value),
        id: getObjectId(value),
        keys: Object.keys(value).slice(0, 80),
      });
      if (report.matchedObjects.length > 200) report.matchedObjects.shift();
    }

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
    if (!patchTracks || !patchNetworkData) return data;
    try {
      if (probe) collectDownloadKeys(data, 0);
      return walk(data, 0);
    } catch (_) {
      return data;
    }
  }

  function forceServiceAvailability(service, uri, source) {
    if (!service || !uri) return;
    try {
      if (service._cache && typeof service._cache.set === "function") {
        service._cache.set(uri, nativeState.yes);
      }

      const events = typeof service.getEvents === "function" ? service.getEvents() : null;
      if (events && typeof events.emit === "function") {
        events.emit(nativeState.updateAvailability, { uri, availability: nativeState.yes });
      }

      pushUniqueReportList(
        "nativeAvailabilityHits",
        { time: Date.now(), uri, source: source || "native-service" },
        200
      );
    } catch (error) {
      recordMessage("native-availability-error", { message: String(error && error.message || error) });
    }
  }

  function patchOfflineService(service) {
    if (!service || service.__spotxLabOfflinePatched) return service;
    try {
      Object.defineProperty(service, "__spotxLabOfflinePatched", {
        configurable: true,
        value: true,
      });
    } catch (_) {
      service.__spotxLabOfflinePatched = true;
    }

    nativeServices.add(service);

    if (typeof service.getAvailabilitySync === "function") {
      const originalGetAvailabilitySync = service.getAvailabilitySync;
      service.getAvailabilitySync = function spotxLabGetAvailabilitySync(uri) {
        if (uriMatchesFixture(uri)) {
          const spotifyUri = toSpotifyTrackUri(uri);
          forceServiceAvailability(service, spotifyUri, "getAvailabilitySync");
          return nativeState.yes;
        }
        return originalGetAvailabilitySync.apply(this, arguments);
      };
    }

    if (typeof service.getDownloads === "function") {
      const originalGetDownloads = service.getDownloads;
      service.getDownloads = async function spotxLabGetDownloads() {
        const downloads = await originalGetDownloads.apply(this, arguments);
        pushUniqueReportList("nativePatches", { time: Date.now(), target: "getDownloads" }, 50);
        return downloads;
      };
    }

    for (const uri of fixtureUris) {
      forceServiceAvailability(service, uri, "service-patched");
    }

    pushUniqueReportList("nativePatches", { time: Date.now(), target: "OfflineAPI" }, 50);
    return service;
  }

  function patchWebpackRequire(requireFn) {
    if (!patchTracks || typeof requireFn !== "function" || requireFn.__spotxLabOfflinePatched) return;
    try {
      const stateModule = requireFn(32619);
      if (stateModule && stateModule.kw && stateModule.kw.YES) nativeState.yes = stateModule.kw.YES;
      const eventModule = requireFn(67784);
      if (eventModule && eventModule.I && eventModule.I.UPDATE_AVAILABILITY) {
        nativeState.updateAvailability = eventModule.I.UPDATE_AVAILABILITY;
      }

      const offlineModule = requireFn(40908);
      if (offlineModule && typeof offlineModule.B === "function" && !offlineModule.B.__spotxLabOfflinePatched) {
        const originalUseOfflineApi = offlineModule.B;
        offlineModule.B = function spotxLabUseOfflineApi() {
          return patchOfflineService(originalUseOfflineApi.apply(this, arguments));
        };
        try {
          Object.defineProperty(offlineModule.B, "__spotxLabOfflinePatched", {
            configurable: true,
            value: true,
          });
        } catch (_) {
          offlineModule.B.__spotxLabOfflinePatched = true;
        }
        pushUniqueReportList("nativePatches", { time: Date.now(), target: "module:40908.B" }, 50);
      }

      const availabilityModule = requireFn(96882);
      if (availabilityModule && typeof availabilityModule.T === "function" && !availabilityModule.T.__spotxLabOfflinePatched) {
        const originalUseAvailability = availabilityModule.T;
        availabilityModule.T = function spotxLabUseAvailability(uri) {
          const availability = originalUseAvailability.apply(this, arguments);
          if (probe && uri) {
            pushUniqueReportList("seenAvailabilityUris", { time: Date.now(), uri: toSpotifyTrackUri(uri) }, 200);
          }
          if (uriMatchesFixture(uri)) {
            const spotifyUri = toSpotifyTrackUri(uri);
            pushUniqueReportList(
              "nativeAvailabilityHits",
              { time: Date.now(), uri: spotifyUri, source: "module:96882.T" },
              200
            );
            return nativeState.yes;
          }
          return availability;
        };
        try {
          Object.defineProperty(availabilityModule.T, "__spotxLabOfflinePatched", {
            configurable: true,
            value: true,
          });
        } catch (_) {
          availabilityModule.T.__spotxLabOfflinePatched = true;
        }
        pushUniqueReportList("nativePatches", { time: Date.now(), target: "module:96882.T" }, 50);
      }
    } catch (error) {
      recordMessage("webpack-native-patch-error", { message: String(error && error.message || error) });
    }
  }

  function installNativeDownloadHooks() {
    if (!patchTracks) return;

    const existingRequire = window.__spotxWebpackRequire;
    if (existingRequire) patchWebpackRequire(existingRequire);

    const chunk = window.webpackChunkclient_web;
    if (!Array.isArray(chunk) || chunk.__spotxLabOfflinePatched) return;
    try {
      chunk.push([
        ["spotx-lab-offline-fixture-" + Date.now()],
        {},
        function captureWebpackRequire(requireFn) {
          window.__spotxWebpackRequire = requireFn;
          patchWebpackRequire(requireFn);
        },
      ]);
      Object.defineProperty(chunk, "__spotxLabOfflinePatched", {
        configurable: true,
        value: true,
      });
    } catch (error) {
      recordMessage("webpack-hook-error", { message: String(error && error.message || error) });
    }
  }

  function collectDownloadKeys(value, depth) {
    if (!value || depth > 8) return;
    if (Array.isArray(value)) {
      for (const item of value) collectDownloadKeys(item, depth + 1);
      return;
    }
    if (typeof value !== "object") return;
    const report = window.__spotxOfflineFixtureReport;
    for (const key of Object.keys(value)) {
      if (/download|offline|cache|avail|playable/i.test(key)) {
        report.downloadKeys[key] = (report.downloadKeys[key] || 0) + 1;
      }
      const child = value[key];
      if (child && typeof child === "object") collectDownloadKeys(child, depth + 1);
    }
  }

  const originalFetch = window.fetch;
  if (patchTracks && patchNetworkData && typeof originalFetch === "function") {
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

  if (patchTracks && patchNetworkData && window.Response && window.Response.prototype) {
    const originalJson = window.Response.prototype.json;
    if (typeof originalJson === "function") {
      window.Response.prototype.json = function patchedResponseJson() {
        return originalJson.call(this).then(patchData);
      };
    }
  }

  if (patchTracks && patchNetworkData && window.JSON && typeof window.JSON.parse === "function") {
    const originalParse = window.JSON.parse;
    window.JSON.parse = function patchedJsonParse(text, reviver) {
      const data = originalParse.call(this, text, reviver);
      if (typeof text === "string" && text.length < 3000000) patchData(data);
      return data;
    };
  }

  if (patchTracks && patchNetworkData && window.XMLHttpRequest && window.XMLHttpRequest.prototype) {
    const originalOpen = window.XMLHttpRequest.prototype.open;
    const originalSend = window.XMLHttpRequest.prototype.send;
    window.XMLHttpRequest.prototype.open = function patchedXhrOpen(method, url) {
      this.__spotxLabUrl = String(url || "");
      return originalOpen.apply(this, arguments);
    };
    window.XMLHttpRequest.prototype.send = function patchedXhrSend() {
      this.addEventListener("loadend", function onSpotXLabXhrLoadEnd() {
        try {
          const text = this.responseText;
          if (typeof text === "string" && text.length > 0 && text.length < 3000000) {
            const data = JSON.parse(text);
            patchData(data);
            recordMessage("xhr-json", { url: this.__spotxLabUrl, status: this.status });
          }
        } catch (_) {}
      });
      return originalSend.apply(this, arguments);
    };
  }

  if (probe && patchNetworkData && window.WebSocket) {
    const OriginalWebSocket = window.WebSocket;
    window.WebSocket = function SpotXLabWebSocket(url, protocols) {
      const socket = protocols === undefined ? new OriginalWebSocket(url) : new OriginalWebSocket(url, protocols);
      socket.addEventListener("message", function onSpotXLabSocketMessage(event) {
        try {
          if (typeof event.data === "string" && /download|offline|cache|available|playable/i.test(event.data)) {
            recordMessage("websocket-message", { url: String(url), sample: event.data.slice(0, 500) });
          }
        } catch (_) {}
      });
      return socket;
    };
    window.WebSocket.prototype = OriginalWebSocket.prototype;
    Object.assign(window.WebSocket, OriginalWebSocket);
  }

  function rowMatchesFixture(row, compiled) {
    const text = normalize(row && row.textContent);
    if (!text) return false;
    if (!compiled.names.some(function hasName(name) { return textMatches(text, name); })) return false;
    if (compiled.artists.length === 0) return true;
    return compiled.artists.some(function hasArtist(artist) { return textMatches(text, artist); });
  }

  function extractTrackUrisFromRow(row) {
    const uris = [];
    if (!row || !row.querySelectorAll) return uris;
    const links = row.querySelectorAll("a[href]");
    for (const link of links) {
      const href = link.getAttribute("href") || "";
      const uri = toSpotifyTrackUri(href);
      if (/^spotify:track:/i.test(uri)) uris.push(uri);
    }
    const attrs = ["data-uri", "data-testid", "aria-label"];
    for (const attr of attrs) {
      const value = row.getAttribute && row.getAttribute(attr);
      const uri = toSpotifyTrackUri(value);
      if (/^spotify:track:/i.test(uri)) uris.push(uri);
    }
    return uris;
  }

  function getReactFiber(element) {
    if (!element) return null;
    const key = Object.getOwnPropertyNames(element).find(function isFiberKey(name) {
      return name.indexOf("__reactFiber$") === 0;
    });
    return key ? element[key] : null;
  }

  function getFiberUri(fiber) {
    let cursor = fiber;
    for (let i = 0; cursor && i < 28; i += 1, cursor = cursor.return) {
      const props = cursor.memoizedProps || cursor.pendingProps;
      const uri = props && (props.uri || props.trackUri || props.track_uri);
      if (uri && uriMatchesFixture(uri)) return toSpotifyTrackUri(uri);
    }
    return "";
  }

  function patchPropsPlayable(props) {
    if (!props || typeof props !== "object") return false;
    let changed = false;
    const trueKeys = [
      "isPlayable",
      "playable",
      "isLocallyPlayable",
      "isAvailable",
      "available",
      "isDownloaded",
      "downloaded",
      "availableOffline",
      "isAvailableOffline",
      "offlinePlayable",
      "playableOffline",
    ];
    const falseKeys = [
      "isLocked",
      "locked",
      "disabled",
      "isDisabled",
      "isUnavailable",
      "unavailable",
      "isBannedInContext",
      "isArtistBanned",
    ];
    for (const key of trueKeys) {
      if (key in props && props[key] !== true) {
        try { props[key] = true; changed = true; } catch (_) {}
      }
    }
    for (const key of falseKeys) {
      if (key in props && props[key] !== false) {
        try { props[key] = false; changed = true; } catch (_) {}
      }
    }
    if ("playabilityRestriction" in props) {
      try { props.playabilityRestriction = 0; changed = true; } catch (_) {}
    }
    if ("availability" in props && props.availability !== nativeState.yes) {
      try { props.availability = nativeState.yes; changed = true; } catch (_) {}
    }
    if ("downloadState" in props && props.downloadState !== nativeState.yes) {
      try { props.downloadState = nativeState.yes; changed = true; } catch (_) {}
    }
    return changed;
  }

  function walkFiberForPlayable(fiber, uri, stats, depth) {
    if (!fiber || depth > 12 || stats.props > 24) return;
    const propsList = [fiber.memoizedProps, fiber.pendingProps].filter(Boolean);
    for (const props of propsList) {
      if (patchPropsPlayable(props)) {
        stats.props += 1;
      }
      if (props && typeof props === "object" && props.uri && uriMatchesFixture(props.uri)) {
        props.uri = uri || toSpotifyTrackUri(props.uri);
      }
    }
    if (fiber.child) walkFiberForPlayable(fiber.child, uri, stats, depth + 1);
  }

  function patchRowDom(row, uri) {
    row.setAttribute("data-spotx-lab-playable", "true");
    row.setAttribute("data-spotx-lab-uri", uri || "");
    row.removeAttribute("aria-disabled");
    patchElementDom(row, uri, "row-dom");
  }

  function patchElementDom(element, uri, reason) {
    if (!element || element.nodeType !== 1) return;
    const now = Date.now();
    const cacheKey = (uri || "") + "|" + (reason || "");
    const cached = elementPatchCache.get(element);
    if (cached && cached.key === cacheKey && now - cached.time < 5000) return;
    elementPatchCache.set(element, { key: cacheKey, time: now });

    element.setAttribute("data-spotx-lab-playable", "true");
    if (uri) element.setAttribute("data-spotx-lab-uri", uri);
    element.removeAttribute("disabled");
    element.setAttribute("aria-disabled", "false");
    element.setAttribute("data-disabled", "false");

    const disabledNodes = element.querySelectorAll("[disabled], [aria-disabled='true'], [data-disabled='true']");
    for (const node of disabledNodes) {
      node.removeAttribute("disabled");
      node.setAttribute("aria-disabled", "false");
      node.setAttribute("data-disabled", "false");
    }

    const buttons = element.matches("button, [role='button'], a")
      ? [element]
      : Array.from(element.querySelectorAll("button, [role='button'], a")).slice(0, 8);
    for (const button of buttons) {
      button.removeAttribute("disabled");
      button.setAttribute("aria-disabled", "false");
      button.setAttribute("data-spotx-lab-playable", "true");
      if (uri) button.setAttribute("data-spotx-lab-uri", uri);
      const label = button.getAttribute("aria-label") || "";
      if (/not available|unavailable|disabled/i.test(label)) {
        button.setAttribute("aria-label", label.replace(/not available|unavailable|disabled/gi, "playable"));
      }
    }

    if (reason !== "element-parent-loop") {
      pushUniqueReportList(
        "elementPlayabilityPatches",
        {
          time: now,
          uri: uri || "",
          reason: reason || "element-dom",
          tag: element.tagName,
          testid: element.getAttribute("data-testid") || "",
          text: normalize(element.textContent).slice(0, 120),
        },
        80
      );
    }
  }

  function patchTrackRowPlayable(row, reason) {
    if (!row) return false;
    const fiber = getReactFiber(row);
    const textUri = getFixtureUriFromText(row.textContent || "");
    const fiberUri = getFiberUri(fiber);
    const attrUris = extractTrackUrisFromRow(row);
    const uri = fiberUri || textUri || attrUris.find(uriMatchesFixture) || "";
    if (!uri || !uriMatchesFixture(uri)) return false;

    addFixtureUri(uri, reason || "row-playability");
    patchRowDom(row, uri);

    const stats = { props: 0 };
    walkFiberForPlayable(fiber, uri, stats, 0);
    pushUniqueReportList(
      "rowPlayabilityPatches",
      {
        time: Date.now(),
        uri,
        reason: reason || "row-loop",
        text: normalize(row.textContent).slice(0, 120),
        props: stats.props,
      },
      200
    );
    return true;
  }

  function getElementFixtureUri(element) {
    if (!element || element.nodeType !== 1) return "";
    const directUri =
      element.getAttribute("data-spotx-lab-uri") ||
      element.getAttribute("data-uri") ||
      element.getAttribute("href") ||
      element.getAttribute("aria-label") ||
      "";
    const normalizedDirect = toSpotifyTrackUri(directUri);
    if (normalizedDirect && uriMatchesFixture(normalizedDirect)) return normalizedDirect;

    const fiberUri = getFiberUri(getReactFiber(element));
    if (fiberUri && uriMatchesFixture(fiberUri)) return fiberUri;

    const textUri = getFixtureUriFromText(element.textContent || "");
    if (textUri && uriMatchesFixture(textUri)) return textUri;

    return "";
  }

  function patchFixtureElement(element, reason) {
    const uri = getElementFixtureUri(element);
    if (!uri) return false;
    if (!isFixtureRelevantElement(element)) return false;
    addFixtureUri(uri, reason || "element-playability");
    patchElementDom(element, uri, reason || "element-playability");
    const fiber = getReactFiber(element);
    const stats = { props: 0 };
    walkFiberForPlayable(fiber, uri, stats, 0);
    if (stats.props > 0) {
      pushUniqueReportList(
        "rowPlayabilityPatches",
        {
          time: Date.now(),
          uri,
          reason: reason || "element-fiber",
          text: normalize(element.textContent).slice(0, 120),
          props: stats.props,
        },
        300
      );
    }
    return true;
  }

  function isFixtureRelevantElement(element) {
    if (!element || element.nodeType !== 1) return false;
    const testid = element.getAttribute("data-testid") || "";
    const role = element.getAttribute("role") || "";
    const text = normalize(element.textContent || "");
    const aria = normalize(element.getAttribute("aria-label") || "");
    const href = element.getAttribute("href") || "";
    if (testid === "root" || element.id === "main" || element.tagName === "HTML" || element.tagName === "BODY") {
      return false;
    }
    if (/volume|queue|lyrics|fullscreen|pip|language|location|search|friend|whats-new/i.test(testid)) {
      return false;
    }
    if (/volume|queue|lyrics|fullscreen|picture in picture|language|location|search/i.test(aria)) {
      return false;
    }
    if (href && !/\/(track|album|artist)\//i.test(href)) return false;
    if (element.matches("[data-testid='tracklist-row'], [data-testid='now-playing-widget'], [data-testid='context-item-info-title'], [data-testid='context-item-link']")) {
      return true;
    }
    if (element.matches("[role='row'], [role='gridcell']")) {
      return compiledTracks.some(function hasTrackText(compiled) {
        return compiled.names.some(function hasName(name) { return textMatches(text, name); });
      });
    }
    if (element.matches("button, [role='button'], a")) {
      return compiledTracks.some(function hasTrackSignal(compiled) {
        return compiled.names.some(function hasName(name) {
          return textMatches(text, name) || textMatches(aria, name);
        });
      }) || /^spotify:track:/i.test(element.getAttribute("data-spotx-lab-uri") || "");
    }
    return compiledTracks.some(function hasRelevantText(compiled) {
      return compiled.names.some(function hasName(name) { return textMatches(text, name); });
    });
  }

  function shouldPatchParentElement(parent) {
    if (!parent || parent.nodeType !== 1) return false;
    const testid = parent.getAttribute("data-testid") || "";
    if (testid === "root" || parent.id === "main" || parent.tagName === "HTML" || parent.tagName === "BODY") return false;
    if (/volume|queue|lyrics|fullscreen|pip|language|location|search|friend|whats-new/i.test(testid)) return false;
    return true;
  }

  function scanFixtureElements() {
    if (!patchTracks || !document.body) return;
    const selectors = [
      "[data-testid='tracklist-row']",
      "[data-testid='now-playing-widget']",
      "[data-testid='context-item-info-title']",
      "[data-testid='context-item-link']",
      "[data-testid*='play']",
      "a[href*='/track/']",
    ];
    const elements = new Set();
    for (const selector of selectors) {
      try {
        document.querySelectorAll(selector).forEach(function addElement(element) {
          if (elements.size < 80) elements.add(element);
        });
      } catch (_) {}
    }

    for (const element of elements) {
      if (patchFixtureElement(element, "element-loop")) {
        let parent = element.parentElement;
        for (let i = 0; parent && i < 2 && shouldPatchParentElement(parent); i += 1, parent = parent.parentElement) {
          patchElementDom(parent, element.getAttribute("data-spotx-lab-uri") || "", "element-parent-loop");
        }
      }
    }
  }

  function installRowClickInterceptor() {
    if (window.__spotxLabRowClickInterceptorInstalled) return;
    window.__spotxLabRowClickInterceptorInstalled = true;
    document.addEventListener(
      "click",
      function onSpotXLabRowClick(event) {
        const row = event.target && event.target.closest && event.target.closest("[data-testid='tracklist-row']");
        const fixtureElement =
          row ||
          (event.target && event.target.closest && event.target.closest("[data-spotx-lab-playable], [data-testid*='play'], [data-testid='now-playing-widget']"));
        if (!fixtureElement) return;
        const patched = row
          ? patchTrackRowPlayable(row, "click-capture")
          : patchFixtureElement(fixtureElement, "click-capture");
        if (!patched) return;
        pushUniqueReportList(
          "rowClickIntercepts",
          {
            time: Date.now(),
            uri: fixtureElement.getAttribute("data-spotx-lab-uri") || "",
            target: event.target && event.target.tagName,
          },
          100
        );
      },
      true
    );
  }

  function ensureStyle() {
    if (document.getElementById("spotx-lab-offline-fixture-style")) return;
    const style = document.createElement("style");
    style.id = "spotx-lab-offline-fixture-style";
    style.textContent = [
      "[data-spotx-lab-playable='true']{opacity:1!important;filter:none!important;}",
      "[data-spotx-lab-playable='true'] *{opacity:1!important;filter:none!important;}",
      "[data-spotx-lab-playable='true'] button,[data-spotx-lab-playable='true'][role='button']{pointer-events:auto!important;cursor:pointer!important;}",
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
    if (!patchTracks || !document.body) return;
    ensureStyle();
    installRowClickInterceptor();

    const trackRows = document.querySelectorAll("[data-testid='tracklist-row']");
    for (const row of trackRows) {
      patchTrackRowPlayable(row, "tracklist-row-loop");
      if (showMarkers) {
        for (const compiled of compiledTracks) {
          if (rowMatchesFixture(row, compiled)) {
            addMarker(row);
            break;
          }
        }
      }
    }
    if (deepElementPatch || showMarkers) {
      scanFixtureElements();
    }
  }

  function scheduleScanDom() {
    if (scanScheduled) return;
    scanScheduled = true;
    const runScheduledScan = function runScheduledScan() {
      scanScheduled = false;
      scanDom();
    };
    if (window.requestIdleCallback) {
      window.requestIdleCallback(runScheduledScan, { timeout: 1000 });
    } else if (window.requestAnimationFrame) {
      window.requestAnimationFrame(runScheduledScan);
    } else {
      window.setTimeout(runScheduledScan, 250);
    }
  }

  installNativeDownloadHooks();
  if (patchTracks) {
    window.setInterval(scanDom, deepElementPatch ? 3000 : 6000);
    window.setInterval(installNativeDownloadHooks, 5000);
    const observer = new MutationObserver(scheduleScanDom);
    window.setTimeout(function startObserver() {
      if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true });
        scheduleScanDom();
      }
    }, 500);
  }

  console.info("[SpotX Lab] Offline fixture hook enabled", {
    forceOffline,
    showMarkers,
    probe,
    deepElementPatch,
    patchNetworkData,
    tracks,
  });
  console.info("[SpotX Lab] Inspect native patch report with window.__spotxOfflineFixtureReport");
})();
