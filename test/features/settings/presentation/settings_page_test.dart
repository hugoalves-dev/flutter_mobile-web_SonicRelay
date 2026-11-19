import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/core/storage/relay_mode_storage.dart';
import 'package:sonic_relay/core/webrtc/relay_modes.dart';
import 'package:sonic_relay/features/auto_connect/presentation/paired_publishers_provider.dart';
import 'package:sonic_relay/features/settings/presentation/settings_page.dart';
import 'package:sonic_relay/features/support/presentation/widgets/support_project_card.dart';

class _FakeRelayModeStorage extends RelayModeStorage {
  _FakeRelayModeStorage() : super(const FlutterSecureStorage());

  String stored = RelayModes.automatic;

  @override
  Future<String> read() async => stored;

  @override
  Future<void> write(String mode) async => stored = mode;
}

class _ReadyReadinessNotifier extends DeviceReadinessNotifier {
  @override
  DeviceReadinessState build() => const DeviceReadinessState.ready();
}

class _PairingRequiredReadinessNotifier extends DeviceReadinessNotifier {
  @override
  DeviceReadinessState build() => const DeviceReadinessState.pairingRequired();
}

Future<void> _pumpSettings(
  WidgetTester tester,
  DeviceReadinessNotifier Function() readinessNotifierFactory,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceReadinessProvider.overrideWith(readinessNotifierFactory),
        diagnosticsDirectoryProvider.overrideWithValue(
          Directory.systemTemp.createTempSync('sonicrelay_settings_test_').path,
        ),
        relayModeStorageProvider.overrideWithValue(_FakeRelayModeStorage()),
        pairedPublishersProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the coturn section is visible once the device is paired', (tester) async {
    await _pumpSettings(tester, _ReadyReadinessNotifier.new);

    expect(find.text('Coturn'), findsOneWidget);
  });

  testWidgets('the coturn section is hidden before pairing completes', (tester) async {
    await _pumpSettings(tester, _PairingRequiredReadinessNotifier.new);

    expect(find.text('Coturn'), findsNothing);
  });

  testWidgets('the privacy policy link is reachable before pairing', (tester) async {
    // Play requires the policy to be reachable from inside the app, and a user
    // who has not paired yet is exactly the one most likely to go looking for
    // it, so this link must not sit behind the paired-only sections.
    await _pumpSettings(tester, _PairingRequiredReadinessNotifier.new);

    expect(find.text('Privacy policy'), findsOneWidget);
  });

  testWidgets('the how-to-use entry is reachable before pairing', (tester) async {
    // A user who has not paired yet is exactly the one most likely to need this
    // explanation, so it must not sit behind the paired-only sections.
    await _pumpSettings(tester, _PairingRequiredReadinessNotifier.new);

    expect(find.text('How to use'), findsOneWidget);
  });

  testWidgets('the donation card is reachable from settings', (tester) async {
    // Settings is where a user who already decided to support the project goes
    // looking, so the ask must not sit behind the paired-only sections.
    await _pumpSettings(tester, _PairingRequiredReadinessNotifier.new);

    final card = tester.widget<SupportProjectCard>(
      find.byType(SupportProjectCard),
    );
    expect(card.compact, isTrue);
  });
}
