# roku-remote — iPhone TV remote (WIP, parked)

An iPhone web remote for a Roku streaming stick, with volume and power passing
through to the Sony TV over HDMI-CEC.

**Status: unfinished.** The server and device layers are done; the web UI that
they exist to serve has not been written yet. Nothing here runs end to end.

## Why it's a local server and not a hosted page

A Roku is controlled over its External Control Protocol — unauthenticated HTTP
on port 8060, LAN only. Two things make a hosted static page impossible:

- iOS Safari hard-blocks an HTTPS page from calling `http://192.168.x.x`. There
  is no user override for mixed content.
- ECP sends no CORS headers, so the browser cannot read any response.

So this runs on a machine on the same Wi-Fi (Mac, Pi, whatever stays on), serves
the UI over plain HTTP, and proxies to the Roku itself. The phone opens
`http://<that-machine-ip>:8080` and adds it to the home screen.

Service workers are deliberately absent: they require a secure context, and a
LAN IP over HTTP is not one. "Add to Home Screen" still gives a standalone
window via `apple-mobile-web-app-capable`.

## What's built

| File | Status |
|------|--------|
| `lib/ecp.js` | Done — SSDP discovery, key presses, text entry, app list/icons/launch, device info |
| `lib/sony.js` | Done — Bravia REST (power, volume, mute, HDMI input) + Wake-on-LAN |
| `server.js` | Done — static host, JSON API over both libs, config persistence |
| `public/` | **Missing** — the actual remote UI |

## What's left

1. `public/index.html` + `styles.css` + `app.js` — D-pad, playback row, volume
   rail, app grid, text-entry sheet. Mobile-first, safe-area aware, hold-to-repeat
   on the d-pad and volume.
2. `public/manifest.webmanifest` and `apple-touch-icon` PNGs.
3. First-run device picker wired to `GET /api/discover`.

## Running what exists

```sh
node roku-remote/server.js
```

It prints the LAN URLs to open. The API works today (`curl` against it is a fine
way to test), but `/` will 404 until `public/` exists.

## API

| Route | Purpose |
|-------|---------|
| `GET /api/discover` | SSDP scan for Rokus on the LAN |
| `GET /api/status` | Device name, model, active app |
| `POST /api/key/:key` | One key press (`up`, `select`, `volumeup`, `poweroff`, …) |
| `POST /api/keydown/:key`, `POST /api/keyup/:key` | Held keys |
| `POST /api/type` | `{"text":"..."}` into an on-screen keyboard |
| `GET /api/apps`, `GET /api/icon/:id`, `POST /api/launch/:id` | Channel list and launching |
| `GET/POST /api/config` | Roku IP and optional Sony credentials |
| `POST /api/tv/{power,volume,mute,input}` | Direct Sony control, when configured |

## Sony TV notes

Volume and power reach the TV over HDMI-CEC through the Roku — the TV needs
Bravia Sync enabled (Settings → External inputs → Bravia Sync settings). That
covers most cases.

CEC power-*on* is the flaky part once the TV has been off a while, which is what
`lib/sony.js` is for. Configuring the TV's IP and pre-shared key routes power,
volume and input selection straight to the TV instead. Enable it under
Settings → Network → Home Network Setup → IP Control → Authentication:
"Normal and Pre-Shared Key". A Bravia in deep standby leaves the network
entirely, so add the TV's MAC to use Wake-on-LAN.

`config.json` holds that pre-shared key and is gitignored — keep it that way.
