import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/lan_providers.dart';
import 'package:sonic_relay/core/storage/connectivity_mode_storage.dart';
import 'package:sonic_relay/core/webrtc/connectivity_modes.dart';
import 'package:sonic_relay/features/lan/presentation/lan_settings_section.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<ProviderContainer> pump(WidgetTester tester, String mode) async {
    final container = ProviderContainer(
      overrides: [
        connectivityModeProvider.overrideWith(
          () => ConnectivityModeNotifier(mode),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: LanSettingsSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('settings mode persists', (tester) async {
    final container = await pump(tester, ConnectivityModes.auto);

    await tester.tap(find.byKey(const Key('connectivity-lanOnly')));
    await tester.pumpAndSettle();

    expect(container.read(connectivityModeProvider), ConnectivityModes.lanOnly);
    expect(
      await const ConnectivityModeStorage(FlutterSecureStorage()).read(),
      ConnectivityModes.lanOnly,
    );
  });

  testWidgets('cloudOnly hides local pairing', (tester) async {
    await pump(tester, ConnectivityModes.cloudOnly);

    expect(find.byKey(const Key('lan-pair')), findsNothing);
  });

  testWidgets('an invalid address is explained', (tester) async {
    await pump(tester, ConnectivityModes.auto);

    await tester.enterText(find.byKey(const Key('lan-address')), 'nope');
    await tester.enterText(
      find.byKey(const Key('lan-code')),
      '0E85-HHQJ-20G3-0G2G',
    );
    await tester.tap(find.byKey(const Key('lan-pair')));
    await tester.pumpAndSettle();

    expect(find.textContaining('host:port'), findsOneWidget);
  });
}
