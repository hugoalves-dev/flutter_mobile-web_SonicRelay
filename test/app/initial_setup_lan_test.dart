import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/app/di/lan_providers.dart';
import 'package:sonic_relay/app/sonic_relay_app.dart';
import 'package:sonic_relay/core/webrtc/connectivity_modes.dart';
import 'package:sonic_relay/features/lan/data/lan_discovery_service.dart';
import 'package:sonic_relay/features/sessions/data/dto/public_room_info.dart';

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

  testWidgets('first-run setup can skip the server for local network only', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        initialServerSetupCompletedProvider.overrideWith(
          () => InitialServerSetupCompletedNotifier(false),
        ),
        onboardingCompletedProvider.overrideWith(
          () => OnboardingCompletedNotifier(true),
        ),
        diagnosticsDirectoryProvider.overrideWithValue(
          Directory.systemTemp.createTempSync('sonicrelay_setup_lan_').path,
        ),
        lanDiscoveryServiceProvider.overrideWith(
          (ref) => LanDiscoveryService(SilentBrowser()),
        ),
        trustedPublishersProvider.overrideWith((ref) async => const []),
        discoverableSessionsProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
        publicRoomProvider.overrideWith(
          (ref) => Stream.value(const PublicRoomInfo.disabled()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SonicRelayApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('setup-local-network-only')));
    await tester.pumpAndSettle();

    expect(container.read(connectivityModeProvider), ConnectivityModes.lanOnly);
    expect(container.read(initialServerSetupCompletedProvider), isTrue);
    expect(find.text('Desktops on this network'), findsOneWidget);
  });
}
