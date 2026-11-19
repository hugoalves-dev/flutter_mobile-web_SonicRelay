# Troubleshooting

Phase 3 failure modes for the device-first Flutter viewer.

## Viewer remains on device setup

- **Missing credential:** first launch calls `POST /api/devices/bootstrap`,
  writes the complete credential to secure storage, and exchanges it through
  `POST /api/devices/token`.
- **Temporary network failure:** keep the credential and use **Retry device
  setup**.
- **Invalid or revoked credential:** the token exchange clears secure storage,
  publishes permanent invalidation, and requires **Reset device identity**.
  Reset creates a new device identity and requires pairing again.

Device-authenticated requests use:

```text
Authorization: Bearer <device_access_token>
```

## Pairing fails

Use the QR code displayed by SonicRelay Windows, or enter its challenge id and
pairing code manually. The scanner accepts exactly:

```json
{
  "challengeId": "00000000-0000-0000-0000-000000000001",
  "code": "ABC12345"
}
```

An invalid or expired challenge needs a newly generated pairing challenge. If
camera permission is denied, close the scanner and use the manual fields. The
camera is requested only while the scanner screen is open.

## Session join is rejected

The session code is separate from the pairing code. Flutter sends only:

```json
{
  "code": "ABC123"
}
```

The backend derives the viewer device from `DeviceBearer` and requires an active
pairing with the publisher. Re-pair if the pairing was revoked, then request a
fresh session code if the old one expired.

## Mutating action returns 401

A pairing completion/revocation or other unsafe mutation is sent exactly once.
The interceptor refreshes the device token but never repeats the mutation
automatically. Retry the action manually; that next request uses the refreshed
bearer. If token exchange is also rejected, the app returns to
`/device-setup`.

## Signaling reconnect stops after revocation

Signaling connects with only `sessionId` in the query:

```text
GET /ws/signaling?sessionId={sessionId}
Authorization: Bearer <device_access_token>
```

Network and temporary token failures reconnect with exponential backoff, capped
at 30s. A revoked device produces `DeviceIdentitySessionInvalidatedException`,
which is a permanent failure: no further timer is scheduled and the router sends
even an active listener to `/device-setup`.

Two events cut the pending backoff short and retry immediately: the device
gaining a network transport (`network changed online=true` in the diagnostic
log), and the app being resumed. Each attempt is also bounded by a 15s connect
timeout, so a half-open network cannot leave an attempt pending forever with no
timer left to recover it.

## Viewer waits for the publisher

`viewer.ready` is not sent on socket open. The publisher first sends
`publisher.ready` to the viewer participant; Flutter replies `viewer.ready` to
that message's authenticated `from` participant.

Every `viewer.ready` carries a deadline. If no `webrtc.offer` answers it within
10s it is re-sent, up to three times, and then the signaling socket is reopened
so the backend re-announces this viewer from scratch. After that the viewer
stays in `reconnecting` and waits to be announced to again rather than looping —
a publisher that is simply gone cannot be nudged. A `participant_not_found`
error frame drops the deadline for the same reason. If it never recovers,
confirm the Windows publisher remains online and the session is active.

## Signaling error frames

| `code` | Meaning | Likely cause |
| --- | --- | --- |
| `invalid_message` | Invalid JSON or missing type | Malformed frame |
| `unsupported_message_type` | Type is not routable | Server-only/unknown outbound type |
| `invalid_recipient` | Missing or invalid `to` | Routed message lacks participant id |
| `participant_not_found` | Recipient is not live | Stale participant id |

## No audio or unexpected relay

ICE servers and short-lived TURN credentials come from
`GET /api/webrtc/ice-servers`. Check backend reachability and coturn ports
`3478/udp`, `3478/tcp`, and `5349/tcp`. The public STUN fallback is debug-only;
strict NATs can require TURN. Use **Force relay (TURN only)** in Settings to
diagnose restrictive networks.

## Local network (LAN) mode

LAN pairing and listening report a diagnostic code (`lan.unreachable`, `lan.isolation_suspected`,
`lan.pin_mismatch`, `lan.revoked`, `ice.no_direct_route`, ...). See [LAN mode](lan-mode.md) for
each code and what to do; the listener's **Path** row shows whether audio is LAN P2P, RelayControl
P2P or TURN.

## Local checklist

1. Start the backend and configure matching HTTP/WS dart defines.
2. Complete device setup.
3. Pair by QR or manual challenge from SonicRelay Windows.
4. Create a new Windows stream session and enter its separate session code.
5. Confirm signaling uses only `sessionId` and a `DeviceBearer` header.
