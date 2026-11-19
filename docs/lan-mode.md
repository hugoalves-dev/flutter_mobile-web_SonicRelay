# Local network (LAN) mode

The Android/iOS viewer can listen to a paired SonicRelay Desktop on the local network **without
internet, RelayControl, STUN or TURN** (dotnet_SonicRelay#75). Flutter Web is out of scope: browsers
cannot pin a self-signed certificate or browse mDNS, so LAN code is compiled out of the web build
(`lib/features/lan/data/lan_platform.dart` → `web_lan_platform.dart`).

Protocol: RelayControl `docs/protocol/lan-signaling-v1.md`. Design: desktop_dotnet_SonicRelay
`docs/superpowers/specs/2026-11-17-lan-offline-signaling-design.md`.

## Connectivity modes (Settings → Local network)

| Mode | Behaviour |
| --- | --- |
| `auto` (default) | Paired desktops are listed on the join page and tried over the LAN first. If the LAN path cannot be established **before the session starts**, the app joins the same desktop's RelayControl session (matched by name) and says why. |
| `lanOnly` | No call to RelayControl at all: no cloud identity bootstrap, no session discovery, no ICE servers. First-run setup offers **Local network only** so a phone with no server can still pair and listen. |
| `cloudOnly` | The previous behaviour; no mDNS, no LAN card. |

LAN-signaled sessions always use `iceServers: []` (host candidates). A live session never moves
between LAN and RelayControl.

## Pairing

- **QR (same or other subnet):** scan the desktop's QR. Version 2 carries a `lan` block (addresses,
  certificate pin, single-use secret) and, when available, the `cloud` challenge — both pair in
  `auto`. The old two-key cloud QR still works.
- **Typed (no camera / routed subnet):** Settings → Local network → enter the desktop address
  (`192.168.1.20:47321`) and the 16-character local pairing code.
- The phone trusts only the pinned desktop certificate and stores a per-device LAN credential in
  secure storage. **Forget** removes it; the desktop can revoke it independently.

## Permissions

- Android: `CHANGE_WIFI_MULTICAST_STATE` (mDNS). Pinned by `test/architecture/android_permission_surface_test.dart`.
- iOS: `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_sonicrelay._tcp`,
  `_sonicrelay-viewer._tcp`). iOS asks the user the first time the app touches the local network.

## Discovery

While the join page is visible the app browses `_sonicrelay._tcp` and announces
`_sonicrelay-viewer._tcp` with TXT `v=1`, `id=<6-hex hint>` only. mDNS does not cross routers:
on another subnet use the QR or a typed address; after the first success the app remembers up to
four working addresses. An mDNS reflector, or unicast DNS-SD (iOS), makes routed discovery automatic.

## Diagnostics

The listener shows **Path**: `LAN · P2P direct`, `RelayControl signaling · P2P direct` or
`RelayControl signaling · TURN relay`, only once ICE is connected. LAN failures are shown with a code:

| Code | Meaning |
| --- | --- |
| `lan.unreachable` | No address of the desktop answered (no route, VLAN ACL, desktop firewall). |
| `lan.isolation_suspected` | Seen through mDNS but TCP refused: Wi-Fi client isolation. |
| `lan.pin_mismatch` | A different certificate answered; pair again. |
| `lan.pairing_invalid` / `lan.pairing_expired` / `lan.rate_limited` | Code wrong/used, expired (120 s) or too many attempts. |
| `lan.revoked` / `lan.unauthorized` | The desktop no longer trusts this phone; pair again. |
| `lan.session_unavailable` | The desktop has no live session or is full. |
| `ice.no_direct_route` | Signaling worked but UDP between the devices is blocked; LAN cannot bypass it. |

LAN reconnects are bounded (5 attempts); terminal close codes (4401/4403/4409) stop immediately
with the reason instead of looping.

Known limit: if LAN signaling succeeds but ICE then fails (UDP blocked), the app reports
`ice.no_direct_route`; it does not switch that session to RelayControl automatically. Leave and
join through RelayControl, or fix the network.
