# Studify Signal Server

Local demo server for testing the Spotify tweak control plane.

It receives playlist download signals from the tweak, creates an in-memory job,
simulates job state changes, and displays the state in a browser dashboard.

## Run

```sh
node Tools/StudifySignalServer/server.js
```

By default it listens on `0.0.0.0:8787`.

Open the printed dashboard URL on your Mac. Use that same LAN URL as the tweak's
server base URL when testing from an iPhone.

## Manual Test

```sh
curl -X POST http://127.0.0.1:8787/v1/jobs/playlist \
  -H 'Content-Type: application/json' \
  -d '{"playlistUri":"spotify:playlist:demo","playlistUrl":"https://open.spotify.com/playlist/demo","deviceId":"mac-manual-test","clientVersion":"studify-ios-0.1"}'
```

## Endpoints

- `GET /` dashboard
- `GET /events` server-sent events stream
- `GET /v1/health`
- `POST /v1/jobs/playlist`
- `GET /v1/jobs`
- `GET /v1/jobs/:jobId`
- `GET /v1/jobs/:jobId/manifest.csv`
