import '../../../core/websocket/websocket_client.dart';
import '../domain/trusted_publisher.dart';
import 'lan_discovery_service.dart';
import 'lan_pairing_api.dart';

/// Why a LAN transport attempt failed, independent of `dart:io` types so the
/// shared LAN logic compiles for the browser (dotnet_SonicRelay#33, #75).
enum LanTransportFailure { unreachable, tlsRejected }

class LanTransportException implements Exception {
  const LanTransportException(this.failure, [this.detail]);

  final LanTransportFailure failure;
  final String? detail;

  @override
  String toString() =>
      'LanTransportException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// The platform half of LAN mode. Mobile implements it over `dart:io` and
/// bonsoir; the browser build gets an unsupported stub (LAN is out of the web
/// MVP).
abstract interface class LanPlatform {
  bool get isSupported;

  /// Pinned-TLS `POST /lan/v1/pair`.
  LanPost get pairingPost;

  /// A WebSocket connector that trusts only [publisher]'s pinned certificate.
  WebSocketConnector signalingConnector(TrustedPublisher publisher);

  /// Opens and closes a TCP connection to tell "no route" from "refused".
  Future<bool> canReach(String endpoint, Duration timeout);

  LanServiceBrowser createBrowser();
}
