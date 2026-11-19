# LAN / Offline Signaling (Mobile) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Android/iOS viewer pair offline with a SonicRelay Desktop, find it on the LAN, signal over pinned TLS and receive WebRTC/Opus P2P without RelayControl, with `auto / lanOnly / cloudOnly` and a visible effective path.

**Architecture:** A `features/lan` feature (dart:io only, never imported from web code) holds trusted publishers, the pinned HTTP client, pairing, discovery and a LAN session connector. A `SessionConnector` chooses LAN or the existing cloud join before the session is established; the existing `WebSocketClient`/`SignalingClient`/`WebRtcReceiverService` are reused with a LAN connector and `iceServers: []`.

**Tech Stack:** Flutter 3 / Dart ^3.11, Riverpod 3, flutter_webrtc, flutter_secure_storage, `bonsoir` (FOSS, no Google artifacts), `crypto`.

**Spec:** Desktop repo `docs/superpowers/specs/2026-11-17-lan-offline-signaling-design.md`; protocol: RelayControl `docs/protocol/lan-signaling-v1.md`.

## Global Constraints

- `connectivityMode` literals `"auto" | "lanOnly" | "cloudOnly"`, default `"auto"`, key `connectivity.mode` in secure storage.
- LAN UI and code paths are disabled on web (`kIsWeb`); `lib/features/lan/**` is never imported by web-reachable libraries (conditional import barrel like `platform_websocket_connector.dart`).
- Pin = base64url(SHA-256(cert DER)); the TLS callback accepts **only** a matching pin (manual code: matching 5-byte prefix during pairing only).
- `lanOnly`: zero RelayControl calls (API, ICE, cloud signaling, device bootstrap).
- LAN-signaled sessions: `iceServers: []`.
- Auto fallback only before establishment: TCP/TLS 3 s per endpoint (parallel), ICE `connected` within 15 s; afterwards reconnect on the same transport, max 5 attempts, then terminal error with manual Retry.
- mDNS: browse `_sonicrelay._tcp`; broadcast `_sonicrelay-viewer._tcp` (TXT `v=1`, `id=<6 hex of sha256(viewerDeviceId)>`) only in foreground.
- Android adds exactly `android.permission.CHANGE_WIFI_MULTICAST_STATE`; iOS adds `NSLocalNetworkUsageDescription` and `NSBonjourServices` = `_sonicrelay._tcp`, `_sonicrelay-viewer._tcp`.
- Credentials and secrets never logged; pins truncated to 8 chars.

## Review Focus

1. A scanned legacy cloud QR (2 keys) keeps pairing exactly as today (Task 2 test `legacy cloud payload still parses`).
2. A Desktop presenting a different certificate after pairing → `lan.pin_mismatch`, no fallback to trusting it (Task 3 test `rejects other certificate`).
3. Publisher visible via mDNS but TCP unreachable → `lan.isolation_suspected`, no endless loop (Task 5 test `isolation suspected stops after bounded attempts`).
4. `lanOnly` with no trusted publisher → explicit guidance to pair, not a spinner (Task 5 test `lanOnly without trusted publisher reports needsPairing`).
5. Web build compiles and never touches `dart:io` LAN code (Task 7 web-safe architecture test).

---

### Task 1: Connectivity mode storage + LAN ICE config

**Files:**
- Create: `lib/core/webrtc/connectivity_modes.dart`, `lib/core/storage/connectivity_mode_storage.dart`
- Modify: `lib/features/listener/data/webrtc_receiver_service.dart` (constructor flag `bool lanSignaled = false` → uses `RtcIceServerConfig.empty()` and skips resolver/forceRelay)
- Modify: `lib/core/webrtc/rtc_ice_server_config.dart` (add `RtcIceServerConfig.empty()`)
- Test: `test/core/storage/connectivity_mode_storage_test.dart`, `test/features/listener/webrtc_receiver_lan_ice_test.dart`

**Interfaces:**
- Produces: `ConnectivityModes { auto, lanOnly, cloudOnly; isValid }`; `ConnectivityModeStorage(FlutterSecureStorage) { Future<String> read(); Future<void> write(String) }`; provider `connectivityModeProvider`.

- [ ] Step 1: tests — `defaults to auto`, `persists`, `invalid stored value falls back to auto`, `lan signaled receiver creates peer with empty ice servers and never calls resolver`.
- [ ] Step 2: `flutter test test/core/storage test/features/listener` → FAIL. Step 3: implement. Step 4: → PASS.
- [ ] Step 5: commit `feat(lan): connectivity mode and LAN ICE config (#75)`.

### Task 2: Pairing payload v2 + manual code

**Files:**
- Modify: `lib/features/pairing/domain/pairing_challenge_payload.dart` (becomes `PairingPayload` parser returning `{ cloud: PairingChallengePayload?, lan: LanPairingOffer? }`; legacy 2-key format → cloud only)
- Create: `lib/features/lan/domain/lan_pairing_offer.dart`, `lib/features/lan/domain/manual_pairing_code.dart`
- Test: `test/features/pairing/pairing_payload_test.dart`, `test/features/lan/manual_pairing_code_test.dart`

**Interfaces:**
- Produces: `LanPairingOffer { String pairingId; String secret; String pin; String publisherDeviceId; String name; List<String> endpoints }`.
- Produces: `ManualPairingCode.tryDecode(String) -> ({List<int> pinPrefix, List<int> secret})?` (Crockford, case-insensitive, `-` ignored, O→0, I/L→1), and `encode` for tests — vectors shared with the Desktop tests.

- [ ] Step 1: tests — `legacy cloud payload still parses`, `v2 with both blocks`, `v2 lan only`, `rejects v2 with no blocks`, `rejects malformed endpoints`, `manual code round trip matches desktop vector`.
- [ ] Step 2–4: fail → implement → pass. Step 5: commit `feat(lan): QR payload v2 and manual pairing code (#75)`.

### Task 3: Pinned TLS client + LAN pairing + trusted publishers

**Files:**
- Create: `lib/features/lan/data/pinned_http_client.dart`, `lib/features/lan/data/lan_pairing_api.dart`, `lib/features/lan/data/trusted_publisher_store.dart`, `lib/features/lan/domain/trusted_publisher.dart`, `lib/features/lan/domain/lan_failure.dart`
- Test: `test/features/lan/pinned_http_client_test.dart`, `lan_pairing_api_test.dart`, `trusted_publisher_store_test.dart`

**Interfaces:**
- Produces: `bool pinMatches(X509Certificate cert, {String? pin, List<int>? pinPrefix})`; `HttpClient createPinnedHttpClient({String? pin, List<int>? pinPrefix})` (`SecurityContext(withTrustedRoots: false)`, `badCertificateCallback` = `pinMatches`, `connectionTimeout` 3 s).
- Produces: `LanPairingApi.pair({required String endpoint, LanPairingOffer? offer, String? manualCode, required String viewerDeviceId, required String viewerName, required String platform}) -> Future<TrustedPublisher>`; throws `LanFailure(code)` with codes `pairing_invalid`, `pairing_expired`, `rate_limited`, `pin_mismatch`, `unreachable`.
- Produces: `TrustedPublisher { publisherDeviceId, name, pin, credential, lastEndpoints, lastSeenAt, hint }`; `TrustedPublisherStore { Future<List<TrustedPublisher>> list(); save(); remove(id); updateEndpoints(id, endpoints) }`. Viewer device id: a random UUID persisted in secure storage (`lan.viewerDeviceId`), independent of the cloud device id.

- [ ] Step 1: tests — `accepts matching pin`, `rejects other certificate`, `prefix accepted only for pairing`, `pair maps 400/410/429`, `store round trip`, `remove forgets credential`. (Pairing API tested against a fake `HttpClient`.)
- [ ] Step 2–4: fail → implement → pass. Step 5: commit `feat(lan): pinned TLS pairing and trusted publishers (#75)`.

### Task 4: mDNS discovery and presence

**Files:**
- Modify: `pubspec.yaml` (add `bonsoir`, `crypto`), `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `test/architecture/android_permission_surface_test.dart` (allow `CHANGE_WIFI_MULTICAST_STATE`)
- Create: `lib/features/lan/data/lan_discovery_service.dart`
- Test: `test/features/lan/lan_discovery_service_test.dart` (fake bonsoir adapter)

**Interfaces:**
- Produces: `abstract interface class LanServiceBrowser { Stream<DiscoveredPublisher> browse(); Future<void> stop(); Future<void> broadcastPresence(String hint); Future<void> stopPresence(); }`; `DiscoveredPublisher { String hint; List<String> endpoints }`; `LanDiscoveryService(LanServiceBrowser) { Stream<List<DiscoveredPublisher>> publishers; DiscoveredPublisher? findTrusted(TrustedPublisher) }`.

- [ ] Step 1: tests — `matches trusted publisher by hint`, `presence txt has only v and id`, `lost service removed`. Step 2–4: fail → implement → pass; `flutter test test/architecture` PASS (FOSS + permission tests).
- [ ] Step 5: commit `feat(lan): mDNS discovery and viewer presence (#75)`.

### Task 5: Session connector (LAN-first, cloud fallback) + LAN signaling

**Files:**
- Create: `lib/features/lan/data/lan_websocket_connector.dart` (dart:io; `WebSocket.connect(url, headers: {Authorization: 'SonicRelay-Lan <cred>', X-SonicRelay-Device: id}, customClient: pinned)`)
- Create: `lib/features/lan/data/lan_session_connector.dart`, `lib/features/sessions/domain/session_transport.dart`
- Modify: `lib/features/sessions/presentation/join_session_view_model.dart`, `lib/features/signaling/data/signaling_client.dart` (accept connector + headers provider override; LAN close codes 4401/4403/4409/4410 are terminal, not retried)
- Test: `test/features/lan/lan_session_connector_test.dart`, `test/features/signaling/signaling_client_lan_test.dart`

**Interfaces:**
- Produces: `enum SessionTransport { lan, cloud }`; `sealed class ConnectOutcome { Connected(SessionTransport, String path) | Failed(LanFailure) }`.
- Produces: `LanSessionConnector.connect(TrustedPublisher p, {required Duration tcpTimeout /*3s*/, required Duration iceTimeout /*15s*/}) -> Future<ConnectOutcome>`; endpoint order: mDNS-resolved, then `lastEndpoints`; first TLS success wins.
- Decision: `auto` → LAN if a trusted publisher has any endpoint and connect succeeds, else cloud join (existing); `lanOnly` → LAN or `Failed`; `cloudOnly` → existing flow unchanged. Failure codes: `unreachable`, `isolation_suspected` (seen via mDNS, TCP failed), `pin_mismatch`, `revoked` (4403), `needs_pairing` (no trusted publisher), `no_direct_route` (ICE failed).

- [ ] Step 1: tests — `auto uses lan when reachable`, `auto falls back to cloud before establishment when lan unreachable`, `auto falls back when ice not connected in 15s`, `lanOnly never calls cloud` (strict fake throws), `lanOnly without trusted publisher reports needsPairing`, `isolation suspected stops after bounded attempts`, `4403 is terminal and marks revoked`, `reconnect after establishment stays on lan`.
- [ ] Step 2–4: fail → implement → pass. Step 5: commit `feat(lan): LAN-first session connector with cloud fallback (#75)`.

### Task 6: Effective path + diagnostics UI + Settings

**Files:**
- Modify: `lib/features/listener/presentation/widgets/ice_state_panel.dart` (path label from selected candidate pair stats: `LAN · P2P direct` / `RelayControl signaling · P2P direct` / `RelayControl signaling · TURN relay`; nothing before `connected`)
- Modify: `lib/features/settings/presentation/settings_page.dart` (Connectivity: mode selector, trusted LAN publishers with Forget, "Pair over local network" form `host:port` + code)
- Modify: `lib/features/pairing/presentation/pairing_view_model.dart` (QR v2: run cloud pairing if `cloud` present and mode ≠ lanOnly; run LAN pairing if `lan` present and mode ≠ cloudOnly; report each outcome)
- Modify: `lib/app/router/app_router.dart` (first-run server setup and cloud pairing gate do not block `lanOnly`)
- Modify: `lib/core/diagnostics/diagnostic_redactor.dart` (redact `credential`, `sec`, `SonicRelay-Lan`)
- Test: `test/features/listener/connection_path_test.dart`, `test/features/settings/connectivity_settings_test.dart`, `test/features/pairing/pairing_view_model_lan_test.dart`, `test/app/app_router_test.dart`, `test/core/diagnostics/diagnostic_redactor_test.dart`

**Interfaces:**
- Produces: `String? connectionPathLabel(SessionTransport t, String iceState, String? localType, String? remoteType)`.

- [ ] Step 1: tests — `path pending until connected`, `relay candidate labelled TURN`, `lan transport labelled LAN P2P`, `settings mode persists`, `qr v2 pairs both blocks in auto`, `lanOnly skips cloud block`, `router lanOnly bypasses server setup`, `redactor removes lan secrets`.
- [ ] Step 2–4: fail → implement → pass. Step 5: commit `feat(lan): path, diagnostics and connectivity settings (#75)`.

### Task 7: Web safety, docs, full verification

**Files:**
- Modify: `test/architecture/web_safe_libraries_test.dart` (assert `features/lan/**` unreachable from web entry), `docs/troubleshooting.md`, `docs/integration-flow.md`, `docs/flutter-architecture.md`
- Create: `docs/lan-mode.md` (permissions, pairing, routed subnets, diagnostics, manual matrix)

- [ ] Step 1: add the architecture assertion; run `flutter test test/architecture` → PASS.
- [ ] Step 2: `flutter analyze` → no issues; `dart format --set-exit-if-changed lib test` → clean; `flutter test` → PASS; `flutter build web` → succeeds.
- [ ] Step 3: commit `docs(lan): LAN mode guide and web-safety guard (#75)`.
