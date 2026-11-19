/// A single ICE server (STUN or TURN) used to establish the peer connection.
class RtcIceServer {
  const RtcIceServer({required this.urls, this.username, this.credential});

  final List<String> urls;
  final String? username;
  final String? credential;

  Map<String, Object?> toMap() => {
    'urls': urls,
    if (username != null) 'username': username,
    if (credential != null) 'credential': credential,
  };
}

/// ICE configuration for the viewer's [RtcPeerConnection].
///
/// Kept as plain data so it can be built from a backend-provided server
/// list. Production ICE servers always come from the authenticated
/// `GET /api/webrtc/ice-servers` backend endpoint (see
/// [IceServersRepository]), which serves the SonicRelay coturn deployment.
/// [RtcIceServerConfig.defaults] is a development-only fallback used when
/// that request fails in a debug build; it is never used silently in
/// production and carries no private/production TURN credentials.
class RtcIceServerConfig {
  const RtcIceServerConfig(this.iceServers, {this.forceRelay = false});

  /// Development-only fallback: a single public STUN server, no TURN.
  factory RtcIceServerConfig.defaults() => const RtcIceServerConfig([
    RtcIceServer(urls: ['stun:stun1.google.com:19302']),
  ]);

  /// No STUN/TURN at all: host candidates only. Used for LAN-signaled sessions
  /// (dotnet_SonicRelay#75), which must not acquire an internet dependency.
  factory RtcIceServerConfig.empty() => const RtcIceServerConfig([]);

  final List<RtcIceServer> iceServers;

  /// When true, ICE only uses relay (TURN) candidates — `iceTransportPolicy:
  /// 'relay'`. When false, direct (host/srflx) candidates are allowed too
  /// (`'all'`). User-controlled so a viewer can force relay on hostile networks.
  final bool forceRelay;

  /// Returns a copy with [forceRelay] overridden; the server list is preserved.
  RtcIceServerConfig withRelay(bool value) =>
      RtcIceServerConfig(iceServers, forceRelay: value);

  /// The `configuration` map passed to `createPeerConnection`. Unified Plan
  /// is requested explicitly so a remote send-only audio track surfaces a
  /// receive-only transceiver without any local track being added.
  Map<String, dynamic> toConfiguration() => {
    'iceServers': iceServers.map((server) => server.toMap()).toList(),
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': forceRelay ? 'relay' : 'all',
  };
}
