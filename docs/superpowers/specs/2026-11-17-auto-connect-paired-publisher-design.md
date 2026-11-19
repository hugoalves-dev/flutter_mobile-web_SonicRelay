# Auto-connect to a Paired Publisher (Flutter) — Design

Issue: hugoalves-dev/flutter_mobile-web_SonicRelay#65.
Companion: `desktop_dotnet_SonicRelay` spec `2026-11-17-start-session-on-launch-design.md`.

## Intent

A user who listens to their own trusted PC (home or work) should not have to type a
session code or tap a discovered session every time. When that PC is streaming, the
app should join it automatically. The PC side gets a matching option to start
streaming on launch (separate spec), so "turn on the PC, open the phone" just works.

## Key finding that shaped the design

The backend already supports code-free joins for paired viewers:

- `GET /api/sessions/discoverable` returns only waiting/active sessions whose publisher
  has an **active** pairing with the caller. It never returns the join code.
- `POST /api/sessions/{id}/join` re-checks DeviceBearer identity, active pairing,
  session state, mode gates and the viewer limit on **every** attempt.
- Revoking the pairing makes both stop working immediately.

The Flutter join page already polls `discoverable` every 5 s and offers one-tap joins.
A publisher-approved "auto-join grant" (suggested in the issue) would add no security
on top of this: any paired client can already join by id. **Decision (user): Flutter
only, the active pairing is the authorization. No backend changes.**

## Goals

- Settings → Auto-connect: a global switch "Automatically connect to selected device",
  **off by default**, and a picker for **exactly one** paired publisher (decision:
  single machine, no priority list).
- With it on, the app joins the selected publisher's session without a code when the
  app is on the join screen and the publisher has a joinable session.
- Clear status: "Waiting for <device>", "Connecting to <device>", errors, "Paused".
  Manual code join and Public Radio stay as they are.

## Non-goals / anti-goals

- No backend or WebRTC/signaling changes; no new media path.
- No background scanning with the app closed, no boot-time start, no foreground
  service just to look for publishers.
- Never connects to a non-paired or revoked publisher (guaranteed by the backend;
  the client also only offers active pairings).
- Never replaces a session that is already joined/playing.
- No persisted session codes.
- No retry loops: a failure must not cause repeated join attempts against the same
  session.

## Behavior

### Settings

- Section "Auto-connect" in `SettingsPage`.
- Switch (global). Below it, a radio list of this device's **active** pairings where
  this device is the viewer, labeled with `publisherDeviceName` (fallback: id) and the
  `publisherDeviceId` in secondary text. Public Radio's virtual publisher is excluded.
- Choosing a device stores its id and name. The switch can be on only with a device
  selected (turning it on with nothing selected selects nothing and shows a hint).
- If the stored device is no longer among active pairings, show it as
  "Pairing revoked — choose another device"; auto-connect does nothing for it.
- Persisted with `FlutterSecureStorage` like the other preferences (new
  `AutoConnectStorage`, keys `autoConnect.enabled`, `autoConnect.publisherDeviceId`,
  `autoConnect.publisherDeviceName`). Absent = off.

### When it attempts

Auto-connect runs **only while the join page is mounted**. The join page is the
"not in a session" screen, so this alone guarantees it never replaces an active
session, and it reuses the existing 5 s discovery poll as the signal (no extra
polling). It is re-evaluated on:

- app start (the join page mounts after identity/pairing gates),
- return to foreground (poll resumes; an immediate refresh is triggered on resume),
- network recovery (the existing `NetworkMonitor` triggers an immediate refresh),
- every discovery result while the page is open (publisher started a session).

On each discovery result, the coordinator attempts a join when **all** hold:

1. Setting enabled and a publisher selected.
2. Not paused (see Leave).
3. Join view model is idle/failed (not joining/joined) — no concurrent manual action.
4. A discovered session has `publisherDeviceId == selected` and is not blocked
   (see failure handling). If several match, pick the most recent `createdAt`
   (deterministic; discovery is already ordered that way).

The join goes through `JoinSessionViewModel.joinDiscovered(session)`, so success
navigates to `/session/waiting` through the page's existing listener and failures use
the existing message mapping.

### Failure handling (no loops)

Per session id, kept in memory by the coordinator:

| Failure | Action |
| --- | --- |
| `network` / `manualRetry` | retry the same session after 5 s, 15 s, 45 s; then every 5 min |
| `maxViewers` | retry that session every 5 min |
| `invalidCode` (session gone/ended) | block that session id |
| `notPaired` | block; show "Pairing with <device> is no longer active" |
| `unauthorized` / `missingDevice` | stop auto-connect until next app start; show error |
| other | block that session id |

A blocked session is never auto-attempted again in this process. The user can still
tap it manually. A publisher that is offline or has no session produces no attempts
and no errors (status stays "Waiting for <device>").

Transient failures cool down instead of blocking (changed after review): the desktop
publisher keeps one session id alive for hours by rotating its join code, so a
permanent block after a short outage would disable auto-connect to that PC until the
app restarts. Five minutes keeps attempts bounded without giving up.

Auto-connect only acts while the join page is mounted (`attach`/`detach` from the
banner). A settings change made from the listener page, or a failure that lands after
the page was left, never starts or schedules a join.

### Leave

When the user taps Leave/Disconnect in the listener (or Stop on the notification, or
backs out while waiting), auto-connect is **paused** until the next cold start of the
app or until the user taps "Resume" on the join page status banner. Pause is in memory
only. Resume is the user's explicit go-ahead and may rejoin the same session (its id
lives for hours on the desktop). Leaving a session the publisher already ended ("Back
to sessions" on an ended stream) and a dropped connection do not pause it: the next
session from that publisher is joined.

### Status banner (join page)

Shown only when the setting is on:

- "Auto-connect: waiting for <device>" (no matching session)
- "Connecting to <device>…" (attempt in flight)
- error text from the table above
- "Auto-connect paused (you left the session)" + **Resume** button

## Structure

- `lib/core/storage/auto_connect_storage.dart` — persistence.
- `lib/features/auto_connect/domain/auto_connect_settings.dart` — value object
  (`enabled`, `publisherDeviceId`, `publisherDeviceName`).
- `lib/features/auto_connect/domain/auto_connect_policy.dart` — pure decision logic:
  given settings, paused flag, join status, discovered sessions and the block/backoff
  table → which session to attempt (or none) and the banner status. Fully unit-tested.
- `lib/features/auto_connect/presentation/auto_connect_controller.dart` — Riverpod
  notifier owning paused state, block table and backoff timers; listens to
  `discoverableSessionsProvider` and the join view model; calls `joinDiscovered`.
- Settings widget `auto_connect_section.dart`; banner widget on the join page.
- `ListenerViewModel.leave()` calls `autoConnectController.pauseAfterLeave(sessionId)`.

## Testing

- Storage: default off, round-trip persists.
- Policy: off/no selection/paused → no attempt; matching session chosen; non-selected
  publisher ignored; newest of several matching chosen; blocked session skipped;
  backoff schedule and blocking after max retries; `unauthorized` stops entirely.
- Controller: Leave pauses and blocks the session; Resume clears pause but not the
  block; a new session from the same publisher is attempted after a publisher-side end;
  never attempts while joining/joined.
- Settings widget: lists only active viewer pairings, shows revoked selection.
- Existing join, Public Radio and listener tests stay green.

## Calls made by the designer (check these)

- Runs only on the join page (simplest way to guarantee "never replace an active
  session" and to reuse the existing poll).
- Pause after Leave lasts until cold start or explicit Resume.
- Backoff 5/15/45 s for network errors, then give up on that session.
- Most recent session wins if the selected publisher somehow has several.
