# Studify Signal Demo

This demo proves the control plane:

1. User taps Spotify playlist download.
2. EeveeSpotify intercepts the offline download action.
3. The tweak POSTs playlist JSON to a Studify server.
4. The server creates a job and simulates state transitions.
5. The server dashboard displays the job state live.

This does not perform real source lookup or audio downloading yet.

## Files

- `Sources/EeveeSpotify/Premium/ServerSidedReminder.x.swift`
  - Existing offline download hook.
  - Playlist download taps now call `sendStudifyPlaylistDownloadSignal(pageURI:)`.

- `Sources/EeveeSpotify/Studify/StudifyDownloadSignalClient.swift`
  - Builds the JSON payload.
  - Sends `POST /v1/jobs/playlist`.
  - Logs success/failure and returns the server `jobId`.

- `Tools/StudifySignalServer/server.js`
  - Local Node server with no npm dependencies.
  - Serves dashboard, job endpoints, CSV manifest, and live server-sent events.

## Run The Mac Server

```sh
node Tools/StudifySignalServer/server.js
```

Open the printed dashboard URL.

Manual endpoint test:

```sh
curl -X POST http://127.0.0.1:8787/v1/jobs/playlist \
  -H 'Content-Type: application/json' \
  -d '{"playlistUri":"spotify:playlist:demo","playlistUrl":"https://open.spotify.com/playlist/demo","deviceId":"mac-manual-test","clientVersion":"studify-ios-0.1"}'
```

## Configure The Tweak Server URL

The current default is:

```swift
private let defaultServerBaseURLString = "http://127.0.0.1:8787"
```

That works only when the client and server are on the same machine. On an
iPhone, `127.0.0.1` means the phone, not your Mac.

For device testing, change the value in:

```txt
Sources/EeveeSpotify/Studify/StudifyDownloadSignalClient.swift
```

to your Mac LAN URL, for example:

```swift
private let defaultServerBaseURLString = "http://192.168.1.25:8787"
```

If App Transport Security blocks local HTTP, use an HTTPS tunnel in front of
the local server and set this value to the HTTPS tunnel URL.

## Build The Tweak

Theos must be installed and exported:

```sh
export THEOS=~/theos
export PATH="$THEOS/bin:$PATH"
```

Then:

```sh
make clean
THEOS_PACKAGE_SCHEME=rootless make package
```

Install to a jailbroken device:

```sh
THEOS_DEVICE_IP=<iphone-ip> THEOS_DEVICE_PORT=22 THEOS_PACKAGE_SCHEME=rootless make package install
```

For IPA testing, build the deb first and then run:

```sh
bash build-ipa-local.sh /path/to/Spotify-Decrypted.ipa
```

## Expected Demo Behavior

1. Start the server on the Mac.
2. Open the dashboard.
3. Install and open the patched Spotify app on the iPhone.
4. Tap playlist download in Spotify.
5. The tweak sends JSON:

```json
{
  "playlistUri": "spotify:playlist:...",
  "playlistUrl": "https://open.spotify.com/playlist/...",
  "deviceId": "...",
  "deviceName": "...",
  "clientVersion": "studify-ios-0.1",
  "spotifyVersion": "...",
  "sentAt": "..."
}
```

6. The server dashboard shows:

```txt
queued
resolving_playlist
manifest_ready
searching_sources
ready_to_download
completed
```
