# Remote ID drone decoding — build spec for Shepherd (v0.15.0 candidate)

Prepared 2026-10-05 by the research stage. Feasibility verified against the
live Shepherd codebase and current public references.

## Why this, why now

Draco (stated 2026-10-05: military organization, Shepherd is a military tool)
accepted the defensive security direction. v0.14.0 already shipped the AIR
THREATS panel (rogue-AP suspicion + disconnect-burst/"consistent with deauth"
detection). Of the three defensive items offered, the one NOT yet built is
**Remote ID drone decoding** — and it is the one that serves his core
interest: actual drone identities, positions, and operator locations instead
of anonymous signal disturbances. It is passive, legal, and fits the
BLE-scan infrastructure Shepherd already has.

## Protocol facts (verified 2026-10-05 via web)

- Mandate: FAA 14 CFR Part 89 (US; enforcement from March 2024). Standards:
  ASTM F3411 (US/international), ASD-STAN EN 4709-002 (EU), GB/T (China,
  interface reserved).
- Four RF transports: (1) BLE 4 legacy advertising — Service Data UUID
  0xFFFA, AD Application Code 0x0D, 25-byte ODID message packs; (2) BLE 5
  extended advertising / Long Range coded PHY; (3) Wi-Fi beacon frames,
  vendor IE OUI FA:0B:BC; (4) Wi-Fi NAN action frames, OUI 50:6F:9A.
- Message types (first nibble(s) of each 25-byte message): 0 = Basic ID
  (UAS ID string, UA type, ID type), 1 = Location/Vector (lat, lon,
  pressure + geodetic altitude, speed, vertical speed, heading/track,
  operational status), 2 = Authentication, 3 = Self ID (free text),
  4 = System (operator lat/lon, area radius, classification),
  5 = Operator ID.
- Reference decoders: opendroneid-core-c (Apache-2.0; decode* functions +
  unit tests with vectors), opendroneid/receiver-android (reference
  receiver app, Play Store), dronetag/drone-scanner (alt impl,
  Android+iOS), opendroneid/wireshark-dissector. Smartphone capability
  list at opendroneid/receiver-android supported-smartphones.md.

## Feasibility on his stack (verified in code 2026-10-05)

- `universal_ble` 2.3.0 (pinned in pubspec.yaml) exposes
  `BleDevice.serviceData` — `Map<String, Uint8List>` keyed by service UUID —
  populated on Android/Windows/Linux. VERIFIED in the pub cache:
  `~/.pub-cache/hosted/pub.dev/universal_ble-2.3.0/lib/src/models/ble_device.dart`.
- Current `lib/services/ble_scan.dart` forwards only `manufacturerDataList`
  and `services` to the decoder; it drops `serviceData`. The pass-through
  into `BleNearbyDevice` is ~10 lines.
- Build plan: new `lib/services/remote_id.dart`, pure-Dart port of the
  ODID message layouts from opendroneid-core-c, golden-tested against the
  reference vectors (same pattern already used for the TinyMlp classifier
  and the track-stitcher). Decode on every BLE scan batch; session-state
  per drone keyed by UAS ID (like the field-activity fusion pattern).
- UI: a REMOTE ID panel inside NEARBY WIRELESS listing decoded drones —
  ID, type, position, altitude, speed/heading, operator location,
  last-seen, RSSI proximity bucket — with the honest-scope caption below.
- What does NOT work on stock adapters: Wi-Fi beacon / NAN Remote ID
  needs monitor-mode frame capture (same constraint as deauth-frame
  detection). BLE 5 Long Range extended needs a phone whose chipset +
  Android build support Long Range + extended advertising (testable with
  nRF Connect's Device information screen). BLE 4 legacy — what most
  compliant drones transmit alongside — works on any Android phone.

## Honest scope (must be stated in the UI, same as every other panel)

- The Authentication message is optional, NOT required by the FAA, and
  most manufacturers don't implement it. Every field in a Remote ID
  broadcast is *asserted*, not verified — spoofable by anyone with an
  ESP32. Never present it as verified identification.
- Exemptions: drones under 250 g, home-built drones, flights inside
  FAA-recognized identification areas. A "dark drone" (GPS-waypoint,
  RF-silent) transmits nothing. No Remote ID ≠ no drone.
- Typical BLE reception range is a few hundred meters; walls kill it.
- EU drones use ASD-STAN packing — decode both or label US/ASTM-only.

## Legal stance for the conversation (already set, keep consistent)

- Offensive transmit features (jamming, deauth floods) stay declined.
  47 U.S.C. § 333 prohibits willful interference with no pen-testing
  carve-out for private parties; federal/military spectrum operations
  run under NTIA and DoD authorities inside authorized systems and
  ranges — not as features bolted onto Shepherd. Shepherd's lane is
  defensive detection, which is what v0.14.0 shipped and what this
  Remote ID work extends.

## Verification for a live test

- No real drone needed: ArduRemoteID firmware (ESP32-S3/C3, open source)
  transmits all four transports and is the standard bench transmitter.
  Suggested test loop: flash a spare ESP32-S3 with ArduRemoteID, run
  Shepherd's BLE scan, confirm the decode matches the flashed ID.
- Cross-check path exists today: the opendroneid receiver-android app on
  the Play Store decodes the same broadcasts — a same-air comparison
  validates Shepherd's port.

## The ask for Draco

"Want me to build Remote ID decoding into the next Shepherd build
(v0.15.0)?" — passive, legal, ~1 build cycle, verified same-day pattern.
Optional follow-up only if he says yes: does he have (or want to flash)
an ESP32-S3/C3 as a bench transmitter for the live test.
