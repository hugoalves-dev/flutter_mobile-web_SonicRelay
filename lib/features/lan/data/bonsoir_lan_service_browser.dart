import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import '../../../core/diagnostics/sonic_log.dart';
import 'lan_discovery_service.dart';

/// [LanServiceBrowser] over `bonsoir` (Android NSD, Apple Bonjour). A platform
/// failure is logged and leaves discovery empty — QR and typed-code pairing
/// and remembered endpoints still work without multicast.
class BonsoirLanServiceBrowser implements LanServiceBrowser {
  final _services = StreamController<DiscoveredService>.broadcast();
  final _lost = StreamController<String>.broadcast();
  BonsoirDiscovery? _discovery;
  BonsoirBroadcast? _broadcast;
  StreamSubscription<BonsoirDiscoveryEvent>? _events;

  @override
  Stream<DiscoveredService> get services => _services.stream;

  @override
  Stream<String> get servicesLost => _lost.stream;

  @override
  Future<void> startBrowsing() async {
    if (_discovery != null) return;
    try {
      final discovery = BonsoirDiscovery(
        type: LanDiscoveryService.publisherType,
      );
      await discovery.initialize();
      _events = discovery.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            unawaited(discovery.serviceResolver.resolveService(event.service));
          case BonsoirDiscoveryServiceResolvedEvent():
            _publish(event.service);
          case BonsoirDiscoveryServiceUpdatedEvent():
            _publish(event.service);
          case BonsoirDiscoveryServiceLostEvent():
            _lost.add(event.service.name);
          default:
            break;
        }
      });
      await discovery.start();
      _discovery = discovery;
    } on Object catch (error) {
      sonicLog('LAN', 'mDNS browse unavailable: $error');
    }
  }

  void _publish(BonsoirService service) => _services.add(
    DiscoveredService(
      name: service.name,
      attributes: service.attributes,
      host: service.host,
      port: service.port,
    ),
  );

  @override
  Future<void> stopBrowsing() async {
    await _events?.cancel();
    _events = null;
    try {
      await _discovery?.stop();
    } on Object catch (error) {
      sonicLog('LAN', 'mDNS browse stop failed: $error');
    }
    _discovery = null;
  }

  @override
  Future<void> broadcastPresence(String hint) async {
    if (_broadcast != null) return;
    try {
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: 'SonicRelay-$hint',
          type: LanDiscoveryService.viewerType,
          // Viewers listen on nothing; the port only satisfies DNS-SD.
          port: 9,
          attributes: {'v': LanDiscoveryService.protocolVersion, 'id': hint},
        ),
      );
      await broadcast.initialize();
      await broadcast.start();
      _broadcast = broadcast;
    } on Object catch (error) {
      sonicLog('LAN', 'mDNS presence unavailable: $error');
    }
  }

  @override
  Future<void> stopPresence() async {
    try {
      await _broadcast?.stop();
    } on Object catch (error) {
      sonicLog('LAN', 'mDNS presence stop failed: $error');
    }
    _broadcast = null;
  }
}
