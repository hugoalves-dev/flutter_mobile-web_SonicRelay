import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/app/di/lan_providers.dart';
import 'package:sonic_relay/core/webrtc/connectivity_modes.dart';
import 'package:sonic_relay/features/lan/data/lan_discovery_service.dart';
import 'package:sonic_relay/features/lan/domain/trusted_publisher.dart';
import 'package:sonic_relay/features/lan/presentation/lan_publishers_card.dart';
import 'package:sonic_relay/features/sessions/data/dto/discoverable_session.dart';
import 'package:sonic_relay/features/sessions/data/dto/public_room_info.dart';
import 'package:sonic_relay/features/sessions/presentation/join_session_page.dart';

class SilentBrowser implements LanServiceBrowser {
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

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Widget wrap(String mode, {required void Function() onCloudLookup}) =>
      ProviderScope(
        overrides: [
          connectivityModeProvider.overrideWith(
            () => ConnectivityModeNotifier(mode),
          ),
          lanDiscoveryServiceProvider.overrideWith(
            (ref) => LanDiscoveryService(SilentBrowser()),
          ),
          trustedPublishersProvider.overrideWith(
            (ref) async => const [
              TrustedPublisher(
                publisherDeviceId: '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
                name: 'DESKTOP-01',
                pin: 'pin',
                credential: 'cred',
                lastEndpoints: ['192.168.1.20:47321'],
              ),
            ],
          ),
          discoverableSessionsProvider.overrideWith((ref) {
            onCloudLookup();
            return Stream.value(const <DiscoverableSession>[]);
          }),
          publicRoomProvider.overrideWith((ref) {
            onCloudLookup();
            return Stream.value(const PublicRoomInfo.disabled());
          }),
        ],
        child: const MaterialApp(home: JoinSessionPage()),
      );

  testWidgets('lanOnly shows paired desktops and never looks up the cloud', (
    tester,
  ) async {
    var cloudLookups = 0;
    await tester.pumpWidget(
      wrap(ConnectivityModes.lanOnly, onCloudLookup: () => cloudLookups++),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LanPublishersCard), findsOneWidget);
    expect(find.text('DESKTOP-01'), findsOneWidget);
    expect(find.text('Join stream'), findsNothing);
    expect(cloudLookups, 0);
  });

  testWidgets('cloudOnly hides the local network card', (tester) async {
    await tester.pumpWidget(
      wrap(ConnectivityModes.cloudOnly, onCloudLookup: () {}),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LanPublishersCard), findsNothing);
    expect(find.text('Join stream'), findsOneWidget);
  });
}
