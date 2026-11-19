import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/features/lan/data/lan_discovery_service.dart';
import 'package:sonic_relay/features/lan/domain/trusted_publisher.dart';

class FakeBrowser implements LanServiceBrowser {
  final found = StreamController<DiscoveredService>.broadcast();
  final lost = StreamController<String>.broadcast();
  String? presenceHint;
  bool browsing = false;
  int presenceStops = 0;

  @override
  Stream<DiscoveredService> get services => found.stream;

  @override
  Stream<String> get servicesLost => lost.stream;

  @override
  Future<void> startBrowsing() async => browsing = true;

  @override
  Future<void> stopBrowsing() async => browsing = false;

  @override
  Future<void> broadcastPresence(String hint) async => presenceHint = hint;

  @override
  Future<void> stopPresence() async => presenceStops++;
}

void main() {
  const desktopId = '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e';
  late FakeBrowser browser;
  late LanDiscoveryService discovery;

  TrustedPublisher trusted() => const TrustedPublisher(
    publisherDeviceId: desktopId,
    name: 'DESKTOP-01',
    pin: 'pin',
    credential: 'cred',
    lastEndpoints: ['192.168.1.20:47321'],
  );

  setUp(() async {
    browser = FakeBrowser();
    discovery = LanDiscoveryService(browser);
    await discovery.start(viewerHint: 'abcdef');
  });

  tearDown(() => discovery.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('matches trusted publisher by hint', () async {
    browser.found.add(
      DiscoveredService(
        name: 'SonicRelay-${lanHint(desktopId)}',
        attributes: {'v': '1', 'id': lanHint(desktopId)},
        host: '192.168.1.20',
        port: 47321,
      ),
    );
    await settle();

    final match = discovery.findTrusted(trusted())!;
    expect(match.endpoints, ['192.168.1.20:47321']);
  });

  test('presence txt has only v and id, and browsing starts', () {
    expect(browser.presenceHint, 'abcdef');
    expect(browser.browsing, isTrue);
  });

  test('ipv6 host is bracketed', () async {
    browser.found.add(
      DiscoveredService(
        name: 'x',
        attributes: {'v': '1', 'id': 'ffffff'},
        host: 'fd00::20',
        port: 1,
      ),
    );
    await settle();

    expect(discovery.publishers.single.endpoints, ['[fd00::20]:1']);
  });

  test('unknown version or missing hint is ignored', () async {
    browser.found
      ..add(
        DiscoveredService(
          name: 'a',
          attributes: {'v': '2', 'id': 'ffffff'},
          host: 'h',
          port: 1,
        ),
      )
      ..add(
        DiscoveredService(
          name: 'b',
          attributes: {'v': '1'},
          host: 'h',
          port: 1,
        ),
      );
    await settle();

    expect(discovery.publishers, isEmpty);
  });

  test('lost service removed', () async {
    browser.found.add(
      DiscoveredService(
        name: 'a',
        attributes: {'v': '1', 'id': 'ffffff'},
        host: 'h',
        port: 1,
      ),
    );
    await settle();

    browser.lost.add('a');
    await settle();

    expect(discovery.publishers, isEmpty);
  });

  test('stop ends presence and browsing', () async {
    await discovery.stop();

    expect(browser.presenceStops, 1);
    expect(browser.browsing, isFalse);
  });
}
