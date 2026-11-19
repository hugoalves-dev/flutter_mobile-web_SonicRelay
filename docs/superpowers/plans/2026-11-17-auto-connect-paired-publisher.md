# Auto-connect to a Paired Publisher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Join one user-selected paired publisher's session automatically, without a code, while the join page is open.

**Architecture:** Pure `AutoConnectPolicy` decides what to attempt from discovery results; a Riverpod `AutoConnectController` owns pause/block/backoff state and calls the existing `JoinSessionViewModel.joinDiscovered`. Settings persist through `FlutterSecureStorage`. No backend changes.

**Tech Stack:** Flutter, Riverpod, flutter_secure_storage, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-17-auto-connect-paired-publisher-design.md`

## Global Constraints

- Off by default; absent storage = off.
- Exactly one selected publisher.
- Never attempt while join status is `joining` or `joined`; only runs while the join page is mounted.
- Network/manualRetry backoff: 5 s, 15 s, 45 s, then block that session id.
- `unauthorized`/`missingDevice` stop auto-connect until app restart.
- Leave pauses until cold start or Resume, and blocks the left session id.
- Public Radio virtual publisher id `0b1e5a7a-0000-4000-8000-000000000001` is never offered in Settings.

## Review Focus

- Discovery returns a session of the selected publisher that is `isFull` → do not attempt (would always fail `maxViewers`). Test in Task 2.
- Backend older than this client omits `publisherDeviceId` → parsed as `''`, never matches. Test in Task 1.
- Join page rebuilt (navigate away and back) mid-backoff → timers cancelled with the controller's listener; no duplicate attempts. Test in Task 3.
- User taps a different discovered session manually while auto-connect is waiting → status `joining` suppresses the auto attempt. Test in Task 2.
- Selected publisher's pairing revoked → Settings shows the revoked label and discovery no longer returns it. Test in Task 4.

---

### Task 1: Settings value, storage and DTO field

**Files:**
- Create: `lib/features/auto_connect/domain/auto_connect_settings.dart`
- Create: `lib/core/storage/auto_connect_storage.dart`
- Modify: `lib/features/sessions/data/dto/discoverable_session.dart` (add `publisherDeviceId`, `createdAt`)
- Modify: `lib/app/di/app_providers.dart` (providers)
- Test: `test/core/storage/auto_connect_storage_test.dart`, `test/features/sessions/data/discoverable_session_test.dart`

**Interfaces:**
- Produces: `class AutoConnectSettings { final bool enabled; final String? publisherDeviceId; final String? publisherDeviceName; bool get isActive => enabled && publisherDeviceId != null; static const off; copyWith }`
- Produces: `AutoConnectStorage(FlutterSecureStorage)` with `Future<AutoConnectSettings> read()`, `Future<void> write(AutoConnectSettings)`; keys `autoConnect.enabled`, `autoConnect.publisherDeviceId`, `autoConnect.publisherDeviceName`.
- Produces: `autoConnectStorageProvider`, `autoConnectSettingsProvider` (`AsyncNotifierProvider<AutoConnectSettingsNotifier, AutoConnectSettings>` with `setEnabled(bool)`, `select(String id, String name)`).
- Produces: `DiscoverableSession.publisherDeviceId` (`String`, default `''`), `DiscoverableSession.createdAt` (`DateTime?`).

- [ ] Tests: storage defaults to `AutoConnectSettings.off`; round-trips enabled+id+name; `enabled` true with no id reads `isActive == false`. DTO parses `publisherDeviceId`/`createdAt` and defaults to `''`/null when absent.
- [ ] Run `flutter test test/core/storage/auto_connect_storage_test.dart test/features/sessions/data/discoverable_session_test.dart` → FAIL.
- [ ] Implement.
- [ ] Run → PASS. Commit `feat(auto-connect): persist auto-connect settings`.

### Task 2: Pure policy

**Files:**
- Create: `lib/features/auto_connect/domain/auto_connect_policy.dart`
- Test: `test/features/auto_connect/domain/auto_connect_policy_test.dart`

**Interfaces:**
- Consumes: Task 1 types, `JoinSessionStatus`, `SessionsFailureKind`.
- Produces:
  - `enum AutoConnectPhase { off, waiting, connecting, paused, error }`
  - `class AutoConnectStatus { final AutoConnectPhase phase; final String? deviceName; final String? message; }`
  - `class AutoConnectPolicy { static DiscoverableSession? pick({required AutoConnectSettings settings, required bool paused, required bool stopped, required JoinSessionStatus joinStatus, required List<DiscoverableSession> sessions, required Set<String> blocked, required Set<String> coolingDown}); static FailureAction onFailure(SessionsFailureKind kind, int attempt); }`
  - `sealed class FailureAction`: `RetryAfter(Duration)`, `BlockSession(String message)`, `StopAll(String message)`.

- [ ] Tests (`pick`): returns null when settings inactive / paused / stopped / status `joining` or `joined`; ignores other publishers; skips blocked and cooling-down ids; skips `isFull`; picks newest `createdAt` among matches; returns match when status is `idle` or `failed`.
- [ ] Tests (`onFailure`): `network` attempts 1,2,3 → RetryAfter 5 s, 15 s, 45 s; attempt 4 → BlockSession; `manualRetry` same as network; `maxViewers`/`invalidCode`/`expiredCode`/`notPaired`/`invalidResponse` → BlockSession; `notPaired` message `'Pairing with <device> is no longer active.'` (device name passed in); `unauthorized`/`missingDevice` → StopAll.
- [ ] Run → FAIL. Implement. Run → PASS. Commit `feat(auto-connect): add selection and failure policy`.

### Task 3: Controller

**Files:**
- Create: `lib/features/auto_connect/presentation/auto_connect_controller.dart`
- Modify: `lib/features/sessions/presentation/join_session_view_model.dart` — `joinDiscovered` returns `Future<SessionsFailureKind?>` (null on success; existing callers ignore it).
- Test: `test/features/auto_connect/presentation/auto_connect_controller_test.dart`

**Interfaces:**
- Consumes: `discoverableSessionsProvider`, `joinSessionViewModelProvider`, `autoConnectSettingsProvider`, Task 2 policy.
- Produces: `autoConnectControllerProvider` (`NotifierProvider<AutoConnectController, AutoConnectStatus>`, **not** autoDispose: pause/block survive page rebuilds) with:
  - `void onDiscovery(List<DiscoverableSession> sessions)` — called by the join page.
  - `void pauseAfterLeave(String? sessionId)`; `void resume()`; `void cancelPending()` (join page dispose).
  - Backoff timers via injectable `Timer Function(Duration, void Function())` provider `autoConnectTimerFactoryProvider`.

- [ ] Tests with fake `SessionsApi` overriding `sessionsApiProvider`: attempts the selected session once; second `onDiscovery` while joining does not attempt; network failure schedules retry at 5 s (fake timer fires → second attempt); after 3 retries blocked; `pauseAfterLeave('s1')` → no attempt for `s1` or anything, phase `paused`; `resume()` → `s1` still skipped but new `s2` attempted; `unauthorized` → phase `error`, no further attempts; `cancelPending()` cancels the timer; status `waiting` with device name when nothing matches.
- [ ] Run → FAIL. Implement. Run → PASS. Commit `feat(auto-connect): add auto-connect controller`.

### Task 4: Settings UI

**Files:**
- Create: `lib/features/settings/presentation/widgets/auto_connect_section.dart`
- Modify: `lib/features/settings/presentation/settings_page.dart` (add section after Connection)
- Modify: `lib/app/di/app_providers.dart` (`pairedPublishersProvider`: `FutureProvider.autoDispose<List<DevicePairing>>` — current device id via `currentPairingDeviceIdProvider`, `pairingRepositoryProvider.list(id)`, keep `status == 'active'`, `viewerDeviceId == id`, publisher id ≠ Public Radio id)
- Test: `test/features/settings/presentation/auto_connect_section_test.dart`

- [ ] Widget tests: switch `Automatically connect to selected device` off by default; radio list shows each active publisher name + id; non-active/other-role/Public Radio excluded; selecting persists; enabling with no selection shows `Choose a device first.` and stays off; stored id absent from list shows `Pairing revoked — choose another device`.
- [ ] Run → FAIL. Implement. Run → PASS. Commit `feat(auto-connect): add settings section`.

### Task 5: Join page banner, discovery hook, resume/network refresh, leave pause

**Files:**
- Create: `lib/features/auto_connect/presentation/auto_connect_banner.dart`
- Modify: `lib/features/sessions/presentation/join_session_page.dart` — `ref.listen(discoverableSessionsProvider, …)` → `onDiscovery`; banner above discovered list; `cancelPending` on dispose (convert to stateful if needed).
- Modify: `lib/features/listener/presentation/listener_page.dart` — onLeave calls `pauseAfterLeave(sessionId)` before `leave()` (session id from `joinSessionViewModelProvider`).
- Modify: `lib/app/sonic_relay_app.dart` — on resume `ref.invalidate(discoverableSessionsProvider)`; same on `networkMonitorProvider.onChanged` → `true`.
- Test: `test/features/auto_connect/presentation/auto_connect_banner_test.dart`, extend join page test.

- [ ] Tests: banner texts `Auto-connect: waiting for PC-1`, `Connecting to PC-1…`, `Auto-connect paused (you left the session)` + `Resume` button calling `resume()`; hidden when phase `off`. Join page with enabled settings and fake discovery containing the selected publisher navigates to `/session/waiting`.
- [ ] Run → FAIL. Implement. Run → PASS. Commit `feat(auto-connect): connect from the join page`.

### Task 6: Verify

- [ ] `dart format --set-exit-if-changed lib test`, `flutter analyze`, `flutter test test/features test/core/storage test/app` → all pass.
