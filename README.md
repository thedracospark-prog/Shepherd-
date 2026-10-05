# Shepherd

**Device-free RF sensing — a tripwire observatory that sees objects moving through radio noise.**

Shepherd turns the RF links of a mesh radio network into a sensing field. When an object crosses a link, the link's signal dips; Shepherd polls each radio's telemetry, tracks every link against a rolling baseline, and flags disturbances as crossing events — then fuses them into tracks with estimated size, distance, speed, and heading. No cameras, no tags, nothing worn or carried. Just the RF field itself.

Built by **Draco**.

## What it does

- **Alert-first dashboard** — big DETECTED / CLEAR banner, per-radio status cards, live link telemetry.
- **Tracking map** — draggable field map with per-node GPS positions, radio-tomographic shadow heatmap, and deterministic cross-network track solving (grid-search position solver; altitude when nodes are at different heights).
- **Beam 3D** — orbit-able antenna lobe visualization with first Fresnel zone ellipsoids.
- **WiFi Vision** — ambient disturbance sensing via the device's own Wi-Fi adapter (coarse RSSI tripwire, per-AP baselines, disturbance attribution by elimination).
- **Air Threats (defensive)** — rogue AP / evil-twin suspicion and disconnect-burst (deauth-pattern) recognition. Detect-only: Shepherd never transmits.
- **Nearby wireless** — passive BLE advertisement scanning with vendor decoding, plus LAN device sweep.
- **Embedded tiny AI (offline)** — pure-Dart neural nets running fully on-device: a crossing-event classifier and a track-stitching specialist, both trained on synthetic scenarios. No cloud, no LLM.
- **GPS positioning** — walk to each node and capture its position; defended-point marker with INBOUND / OUTBOUND / TRANSITING readouts.

## What it works with

| Hardware | Status | Notes |
|---|---|---|
| 2× Silvus SC4200P (meshed) | **Live** | JSON-RPC `streamscape_data` telemetry driver; rolling-baseline tripwire per link direction |
| L3Harris AN/PRC-163 | **In progress** | SNMP discovery probe in `tools/`; driver follows what the radio exposes |
| MPU5 / Wave Relay | **Planned** | Driver stub in the multi-driver framework |
| Meshtastic nodes | **Planned** | Cheap GPS/PIR field nodes; driver wakes when hardware is on hand |
| This device's Wi-Fi + BLE | **Live** | Windows via `netsh`; passive scan only |

Two mesh nodes = one link = tripwire. Three or more nodes unlock tracking.

## Install

### Windows

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) **outside** OneDrive (e.g. `%LOCALAPPDATA%\flutter`) — OneDrive file-locking breaks Flutter's cache.
2. Enable **Developer Mode** (Settings → System → For developers) — required for plugin symlinks.
3. Clone this repo, then:
   ```
   cd shepherd
   flutter pub get
   flutter run -d windows
   ```
4. Open the Settings gear → turn off simulated mode → enter your radio IP.

For a standalone install, double-click **`build_exe.bat`** — it compiles a portable release folder and zips it to your Desktop. (Unsigned binary: SmartScreen → *More info → Run anyway*.)

### Android

1. Install the Android SDK and accept licenses.
2. Double-click **`build_apk.bat`** — it checks prerequisites, then builds `shepherd.apk`.
3. Install the APK on the device; grant location permission for GPS node capture.

> **Note:** `lib/services/wifi_aware.dart` / `MainActivity.kt` contain experimental Wi-Fi Aware discovery (hand-written, cooperative-only). If the APK build fails in `compileReleaseKotlin`, that file is the first suspect — deleting it and its channel block builds fine without the Aware panel.

## Screenshots

See [`docs/screenshots/`](docs/screenshots/) — captured from the live app.

## Honest scope

Shepherd states its limits in the UI, not just here:

- **RF shows a radar scope, not a camera.** Tracks are moving blobs with size/distance/speed/heading estimates — never silhouettes or identities.
- Two nodes cannot triangulate; altitude needs nodes at different heights.
- Wi-Fi RSSI sensing is coarse signal disturbance only: no CSI imaging, no bearing, no object ID.
- Type guesses are heuristic and always labeled low-confidence.
- The embedded AI classifies closed events — it never suppresses alerts.

## Layout

```
lib/
  screens/    dashboard, tracking, beam 3D, WiFi vision, settings
  services/   radio drivers, tripwire, tracker, AI classifier, BLE, WiFi
  state/      app state + persistence
  models/     LinkSample and tracking models
  theme.dart  dark-mode design system
android/      Android shell (Wi-Fi Aware Kotlin lives here)
tools/        PC-side helpers (SNMP radio probe, etc.)
docs/         specs and screenshots
build_exe.bat / build_apk.bat   one-shot builders
```

## License

© 2026 Draco. All rights reserved.
