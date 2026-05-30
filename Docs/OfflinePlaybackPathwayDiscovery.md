# Studify Offline Playback Pathway Discovery

Date: 2026-05-28

## Current Architecture Hypothesis

The best path is not to fully replace Spotify's UI with our own overlay. The cleaner path is:

1. Intercept Spotify's playlist download/offline button.
2. Send the playlist URI to the Studify server.
3. Server resolves/downloader prepares local files and a manifest.
4. Tweak maps Spotify track URIs to local file paths.
5. When Spotify is offline, intercept the row/playability path so available Studify files look playable.
6. On row tap/play/next/previous, route playback to Studify local audio while keeping Spotify's UI state in sync.

This keeps Spotify as the visual shell and replaces the content availability/playback backend.

## Known Download Entry Point

Existing Eevee/Studify code already has a download interception path:

- `Sources/EeveeSpotify/Premium/ServerSidedReminder.x.swift`
- `Sources/EeveeSpotify/Tweak.x.swift`

Known direct helper:

```text
Offline_ContentOffliningUIImpl.ContentOffliningUIHelperImplementation
downloadToggledWithCurrentAvailability:addAction:removeAction:pageIdentifier:pageURI:
downloadToggledWithCurrentAvailability:addAction:removeAction:pageIdentifier:pageURI:interactionID:
```

For Spotify 9.1.x, this class may be missing or renamed, so the current code also uses a `UIControl.sendAction:to:forEvent:` fallback.

## Known UI Row Class

Runtime logs have confirmed the visible playlist track cell class:

```text
ListUXPlatform_FreeTierPlaylistImpl.LegacySwipableElementTableViewCell
```

This is why generic window scanning may miss rows while the cell hook still sees them.

## Static Binary Findings

The patched Spotify binary contains these likely pathway classes:

### Playlist Row / Tap Pipeline

```text
ListUXPlatform_FreeTierPlaylistImpl.FTPTrackRowEventHandler
ListUXPlatform_FreeTierPlaylistImpl.FTPPlayRestrictionResolver
ListUXPlatform_FreeTierPlaylistImpl.PLTrackViewModelFactory
ListUXPlatform_FreeTierPlaylistImpl.PLTrackViewModelImplementation
ListUXPlatform_FreeTierPlaylistImpl.ListPlayerImpl
ListUXPlatform_FreeTierPlaylistImpl.LegacySwipableElementTableViewCell
ListUXPlatformConsumers_DefaultItemListRowPluginImpl.TrackRowElementUI
ListUXPlatformConsumers_DefaultItemListRowPluginImpl.LegacyTrackRowElementUI
TrackRowDataElement
LegacyTrackRowDataElement
TrackRowRestriction
TrackRowPlayState
```

### Offline / Downloaded State Pipeline

```text
SPTTrackOfflineState
SPTOfflineAvailability
Spotify_Playlist_Cosmos_Proto_TrackOfflineState
Offline_DeadEndsUIImpl.OfflineContentStateFactoryImpl
Offline_UnavailableContentImpl.DownloadedContentCheckerImplementation
SPTUnavailableContentDownloadedContentChecker
OfflineContentState
OfflineContentStateFactory
DownloadedContentCheckerImplementation
contentIsDownloaded
isDownloaded
```

### Offline Mode / Reachability

```text
Connectivity_ReachabilityImpl.ForcedOfflineModeManagerImpl
SPTForcedOfflineModeManager
isForcedOfflineModeOn
isCurrentForcedOfflineModeOn
```

### Playability / Restriction Pipeline

```text
CreativeWorkCommons_PlaybackAvailabilityImpl.PlaybackAvailabilityServiceImpl
CreativeWorkCommons_PlaybackAvailabilityImpl.PlaybackAvailabilityDataSourceImpl
CreativeWorkCommons_PlaybackAvailabilityImpl.PlaybackAvailabilityDataSourceProviderImpl
SPTCollectionPlatformPlayStateRestriction
Spotify_CosmosUtil_Proto_PlayabilityRestriction
Spotify_Restrictions_Permissions_PermissionsProto_CanPlayContentRequest
Spotify_Restrictions_Permissions_PermissionsProto_CanPlayContentResponse
Spotify_Restrictions_Permissions_PermissionsProto_CanPlayContentResult
canPlayContent:
canPlayContentWithURI:
playabilityRestriction
```

### Spotify Offline Playable Cache

```text
Offline_PlayableCacheImpl.PlayableCacheAvailabilityProviderImplementation
Offline_PlayableCacheImpl.PlayableCacheServiceImplementation
Offline_PlayableCacheImpl.PlayableCachePlayerImplementation
Offline_PlayableCacheImpl.PlayableCacheListPlayerImplementation
Offline_PlayableCacheImpl.PlayEffectHandler
Spotify_OfflinePlayableCacheEsperanto_Proto_GetTracksRequest
Spotify_OfflinePlayableCacheEsperanto_Proto_GetTracksResponse
Spotify_OfflinePlayableCacheEsperanto_Proto_HasEnoughTracksRequest
Spotify_OfflinePlayableCacheEsperanto_Proto_HasEnoughTracksResponse
```

This may be the most Spotify-native place to imitate downloaded tracks, but it is probably more complex than intercepting playlist row playability first.

## Probe Added

Added a narrow runtime probe:

```text
Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifyOfflinePathwayProbe.swift
```

It does not enumerate all classes or methods. It only checks whether known candidate classes exist and whether they respond to known selectors.

Expected log markers:

```text
Studify offline pathway probe started
Offline pathway class found label=...
Offline pathway class missing label=...
Offline pathway object reason=refreshCell class=...
```

## Immediate Next Targets

The likely first hook candidates are:

1. `ListUXPlatform_FreeTierPlaylistImpl.FTPPlayRestrictionResolver`
   - Goal: make a playlist row unrestricted/playable when the Studify manifest has the track.

2. `ListUXPlatform_FreeTierPlaylistImpl.PLTrackViewModelImplementation`
   - Goal: determine whether downloaded/playable/disabled state lives in the row model.

3. `CreativeWorkCommons_PlaybackAvailabilityImpl.PlaybackAvailabilityServiceImpl`
   - Goal: fake content as playable at the service layer.

4. `Offline_UnavailableContentImpl.DownloadedContentCheckerImplementation`
   - Goal: fake "downloaded content exists" for selected track/playlist URIs.

5. `Offline_PlayableCacheImpl.PlayableCacheAvailabilityProviderImplementation`
   - Goal: imitate Spotify's own offline playable cache availability.

## Current Test Interpretation

If the probe logs class existence and selector matches, we choose a direct hook.

If the probe logs only the cell class and no useful upstream selectors, the next step is a narrowly targeted object-context probe from the cell/responder chain, not a broad runtime scan.

## Product Direction

The final system should likely be:

- Spotify download button triggers Studify server job.
- Server returns manifest `{ spotifyTrackURI -> localPath, status }`.
- Tweak stores manifest in `Documents/StudifyLibrary/manifest.json`.
- Tweak marks rows playable/downloaded only when manifest says the file exists.
- Tweak intercepts row play/skip/queue commands and plays local files with `AVAudioPlayer` or `AVPlayer`.
- Spotify UI is allowed to render as normally as possible from faked availability state.
