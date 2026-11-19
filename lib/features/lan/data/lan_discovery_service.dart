import 'dart:async';

import '../domain/trusted_publisher.dart';

/// A resolved DNS-SD instance (name, TXT attributes, address).
class DiscoveredService {
  const DiscoveredService({
    required this.name,
    required this.attributes,
    required this.host,
    required this.port,
  });

  final String name;
  final Map<String, String> attributes;
  final String? host;
  final int port;
}

/// A SonicRelay Desktop seen on the link. Matching a [TrustedPublisher] by
/// [hint] is only a hint: identity is proven by the pinned TLS handshake.
class DiscoveredPublisher {
  const DiscoveredPublisher({
    required this.name,
    required this.hint,
    required this.endpoints,
  });

  final String name;
  final String hint;
  final List<String> endpoints;
}

/// mDNS/DNS-SD transport, abstracted so discovery logic is testable.
abstract interface class LanServiceBrowser {
  Stream<DiscoveredService> get services;
  Stream<String> get servicesLost;
  Future<void> startBrowsing();
  Future<void> stopBrowsing();
  Future<void> broadcastPresence(String hint);
  Future<void> stopPresence();
}

/// Browses `_sonicrelay._tcp` publishers and announces this phone as
/// `_sonicrelay-viewer._tcp` while the app is in the foreground
/// (dotnet_SonicRelay#75). TXT carries only `v=1` and a 6-hex hint.
class LanDiscoveryService {
  LanDiscoveryService(this._browser);

  static const publisherType = '_sonicrelay._tcp';
  static const viewerType = '_sonicrelay-viewer._tcp';
  static const protocolVersion = '1';

  final LanServiceBrowser _browser;
  final _publishers = <String, DiscoveredPublisher>{};
  final _changes = StreamController<List<DiscoveredPublisher>>.broadcast();
  StreamSubscription<DiscoveredService>? _found;
  StreamSubscription<String>? _lost;

  List<DiscoveredPublisher> get publishers =>
      List.unmodifiable(_publishers.values);
  Stream<List<DiscoveredPublisher>> get changes => _changes.stream;

  Future<void> start({required String viewerHint}) async {
    _found ??= _browser.services.listen(_onFound);
    _lost ??= _browser.servicesLost.listen(_onLost);
    await _browser.startBrowsing();
    await _browser.broadcastPresence(viewerHint);
  }

  Future<void> stop() async {
    await _browser.stopPresence();
    await _browser.stopBrowsing();
    _publishers.clear();
    _emit();
  }

  /// The discovered instance of a paired desktop, if it is on this link.
  DiscoveredPublisher? findTrusted(TrustedPublisher publisher) {
    for (final candidate in _publishers.values) {
      if (candidate.hint == publisher.hint) return candidate;
    }
    return null;
  }

  Future<void> dispose() async {
    await _found?.cancel();
    await _lost?.cancel();
    await _changes.close();
  }

  void _onFound(DiscoveredService service) {
    final hint = service.attributes['id'];
    if (service.attributes['v'] != protocolVersion ||
        hint == null ||
        hint.length != 6) {
      return;
    }
    final host = service.host;
    if (host == null || host.isEmpty) return;
    final formatted = host.contains(':') ? '[$host]' : host;
    _publishers[service.name] = DiscoveredPublisher(
      name: service.name,
      hint: hint,
      endpoints: ['$formatted:${service.port}'],
    );
    _emit();
  }

  void _onLost(String name) {
    if (_publishers.remove(name) != null) _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(publishers);
  }
}
