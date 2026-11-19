import '../../../core/webrtc/rtc_peer_connection_factory.dart';

/// The path the audio actually took (dotnet_SonicRelay#75), using the same
/// labels as the desktop dashboard. Null until ICE is connected and the
/// selected pair is known: nothing may be claimed before that.
String? connectionPathLabel({
  required bool lan,
  required bool connected,
  required RtcTransportMode transport,
}) {
  if (!connected) return null;
  return switch (transport) {
    RtcTransportMode.relay => 'RelayControl signaling · TURN relay',
    RtcTransportMode.direct =>
      lan ? 'LAN · P2P direct' : 'RelayControl signaling · P2P direct',
    RtcTransportMode.unknown => null,
  };
}
