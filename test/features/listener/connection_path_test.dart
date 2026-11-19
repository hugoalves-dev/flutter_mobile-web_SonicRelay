import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/webrtc/rtc_peer_connection_factory.dart';
import 'package:sonic_relay/features/listener/domain/connection_path.dart';

void main() {
  test('path pending until connected', () {
    expect(
      connectionPathLabel(
        lan: true,
        connected: false,
        transport: RtcTransportMode.direct,
      ),
      isNull,
    );
    expect(
      connectionPathLabel(
        lan: true,
        connected: true,
        transport: RtcTransportMode.unknown,
      ),
      isNull,
    );
  });

  test('lan transport labelled LAN P2P', () {
    expect(
      connectionPathLabel(
        lan: true,
        connected: true,
        transport: RtcTransportMode.direct,
      ),
      'LAN · P2P direct',
    );
  });

  test('cloud direct is RelayControl signaling with P2P media', () {
    expect(
      connectionPathLabel(
        lan: false,
        connected: true,
        transport: RtcTransportMode.direct,
      ),
      'RelayControl signaling · P2P direct',
    );
  });

  test('relay candidate labelled TURN', () {
    expect(
      connectionPathLabel(
        lan: false,
        connected: true,
        transport: RtcTransportMode.relay,
      ),
      'RelayControl signaling · TURN relay',
    );
  });
}
