import 'dart:async';

import '../../../core/websocket/websocket_client.dart';
import '../domain/trusted_publisher.dart';
import 'lan_discovery_service.dart';
import 'lan_pairing_api.dart';
import 'lan_platform_contract.dart';

/// Selected by `lan_platform.dart` for the browser. LAN mode is out of the
/// web MVP (dotnet_SonicRelay#75): browsers cannot pin a self-signed
/// certificate or browse mDNS, so everything here reports "unsupported".
LanPlatform createLanPlatform() => const WebLanPlatform();

class WebLanPlatform implements LanPlatform {
  const WebLanPlatform();

  @override
  bool get isSupported => false;

  @override
  LanPost get pairingPost =>
      (_, _, _) async => throw const LanTransportException(
        LanTransportFailure.unreachable,
        'LAN is not supported on the web',
      );

  @override
  WebSocketConnector signalingConnector(TrustedPublisher publisher) =>
      (_, _) async => throw const LanTransportException(
        LanTransportFailure.unreachable,
        'LAN is not supported on the web',
      );

  @override
  Future<bool> canReach(String endpoint, Duration timeout) async => false;

  @override
  LanServiceBrowser createBrowser() => _NoBrowser();
}

class _NoBrowser implements LanServiceBrowser {
  @override
  Stream<DiscoveredService> get services => const Stream.empty();

  @override
  Stream<String> get servicesLost => const Stream.empty();

  @override
  Future<void> startBrowsing() async {}

  @override
  Future<void> stopBrowsing() async {}

  @override
  Future<void> broadcastPresence(String hint) async {}

  @override
  Future<void> stopPresence() async {}
}
