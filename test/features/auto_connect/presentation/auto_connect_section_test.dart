import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/features/auto_connect/presentation/auto_connect_section.dart';
import 'package:sonic_relay/features/auto_connect/presentation/auto_connect_settings_notifier.dart';
import 'package:sonic_relay/features/auto_connect/presentation/paired_publishers_provider.dart';
import 'package:sonic_relay/features/pairing/domain/device_pairing.dart';

DevicePairing _pairing(String publisherId, String name) => DevicePairing(
  pairingId: 'p-$publisherId',
  publisherDeviceId: publisherId,
  viewerDeviceId: 'me',
  status: 'active',
  createdAt: DateTime.utc(2026),
  publisherDeviceName: name,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, String> stored = const {},
  List<DevicePairing> publishers = const [],
}) async {
  FlutterSecureStorage.setMockInitialValues(Map.of(stored));
  final container = ProviderContainer(
    overrides: [
      pairedPublishersProvider.overrideWith((ref) async => publishers),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AutoConnectSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

SwitchListTile _switch(WidgetTester tester) =>
    tester.widget(find.byType(SwitchListTile));

void main() {
  testWidgets('the switch starts off', (tester) async {
    await _pump(tester, publishers: [_pairing('pub-1', 'Home PC')]);

    expect(
      find.text('Automatically connect to selected device'),
      findsOneWidget,
    );
    expect(_switch(tester).value, isFalse);
  });

  testWidgets('lists each paired publisher by name and id', (tester) async {
    await _pump(
      tester,
      publishers: [_pairing('pub-1', 'Home PC'), _pairing('pub-2', 'Work PC')],
    );

    expect(find.text('Home PC'), findsOneWidget);
    expect(find.text('pub-1'), findsOneWidget);
    expect(find.text('Work PC'), findsOneWidget);
  });

  testWidgets('selecting a device persists it', (tester) async {
    final container = await _pump(
      tester,
      publishers: [_pairing('pub-1', 'Home PC')],
    );

    await tester.tap(find.text('Home PC'));
    await tester.pumpAndSettle();

    final settings = container.read(autoConnectSettingsProvider).value!;
    expect(settings.publisherDeviceId, 'pub-1');
    expect(settings.publisherDeviceName, 'Home PC');
  });

  testWidgets('enabling without a device asks to choose one first', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      publishers: [_pairing('pub-1', 'Home PC')],
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Choose a device first.'), findsOneWidget);
    expect(container.read(autoConnectSettingsProvider).value!.enabled, isFalse);
  });

  testWidgets('enabling with a device selected turns it on', (tester) async {
    final container = await _pump(
      tester,
      stored: {'autoConnect.publisherDeviceId': 'pub-1'},
      publishers: [_pairing('pub-1', 'Home PC')],
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(container.read(autoConnectSettingsProvider).value!.enabled, isTrue);
  });

  testWidgets('a selected device that is no longer paired is flagged', (
    tester,
  ) async {
    await _pump(
      tester,
      stored: {
        'autoConnect.enabled': 'true',
        'autoConnect.publisherDeviceId': 'gone',
      },
      publishers: [_pairing('pub-1', 'Home PC')],
    );

    expect(
      find.text('Pairing revoked — choose another device'),
      findsOneWidget,
    );
  });

  test('only active publishers this device listens to are offered', () {
    final offered = selectPairedPublishers([
      _pairing('pub-1', 'Home PC'),
      DevicePairing(
        pairingId: 'x',
        publisherDeviceId: 'pub-2',
        viewerDeviceId: 'me',
        status: 'revoked',
        createdAt: DateTime.utc(2026),
      ),
      DevicePairing(
        pairingId: 'y',
        publisherDeviceId: 'me',
        viewerDeviceId: 'other',
        status: 'active',
        createdAt: DateTime.utc(2026),
      ),
      _pairing(publicRadioPublisherDeviceId, 'Public Radio'),
    ], currentDeviceId: 'me');

    expect(offered.map((p) => p.publisherDeviceId), ['pub-1']);
  });
}
