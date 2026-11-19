import '../../../core/websocket/websocket_client.dart';
import 'trusted_publisher.dart';

/// Close codes of LAN signaling protocol v1 that a retry cannot fix.
class LanCloseCodes {
  const LanCloseCodes._();

  static const unauthorized = 4401;
  static const revoked = 4403;
  static const unavailable = 4409;
  static const sessionEnded = 4410;

  static bool isTerminal(int? code) =>
      code == unauthorized ||
      code == revoked ||
      code == unavailable ||
      code == sessionEnded;
}

/// Marks a [StreamSession] as signaled through a desktop's LAN host
/// (dotnet_SonicRelay#75): pinned TLS through [connector], authenticated with
/// the per-device LAN credential, never the cloud identity.
class LanSessionTarget {
  const LanSessionTarget({
    required this.publisher,
    required this.viewerDeviceId,
    required this.connector,
  });

  final TrustedPublisher publisher;
  final String viewerDeviceId;
  final WebSocketConnector connector;

  Map<String, String> get headers => {
    'Authorization': 'SonicRelay-Lan ${publisher.credential}',
    'X-SonicRelay-Device': viewerDeviceId,
  };
}
