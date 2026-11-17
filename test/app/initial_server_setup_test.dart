import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/app/env/app_config.dart';
import 'package:sonic_relay/app/sonic_relay_app.dart';
import 'package:sonic_relay/core/diagnostics/sonic_log.dart';
import 'package:sonic_relay/core/storage/coturn_override_storage.dart';
import 'package:sonic_relay/core/webrtc/relay_modes.dart';
import 'package:sonic_relay/core/webrtc/relay_settings_api.dart';

const _customTurn = 'turn:relay.example.com:3478';

class _FakeRelaySettingsApi extends RelaySettingsApi {
  _FakeRelaySettingsApi({this.turnUris = const []}) : super(Dio());

  final List<String> turnUris;
  final List<List<String>?> pushedTurnUris = [];

  @override
  Future<RelaySettings> fetch() async =>
      RelaySettings(relayMode: RelayModes.automatic, turnUris: turnUris);

  @override
  Future<void> update({String? relayMode, List<String>? turnUris}) async {
    pushedTurnUris.add(turnUris);
  }
}

class _FailedDeviceSetupNotifier extends DeviceReadinessNotifier {
  @override
  DeviceReadinessState build() => const DeviceReadinessState.deviceSetup(
    errorMessage: 'Unable to reach the server.',
  );
}

class _ReadyReadinessNotifier extends DeviceReadinessNotifier {
  @override
  DeviceReadinessState build() => const DeviceReadinessState.ready();
}

ProviderContainer _container({
  bool setupCompleted = false,
  String? coturnOverride,
  DeviceReadinessNotifier Function()? readiness,
  RelaySettingsApi? relaySettingsApi,
}) => ProviderContainer(
  overrides: [
    initialServerSetupCompletedProvider.overrideWith(
      () => InitialServerSetupCompletedNotifier(setupCompleted),
    ),
    coturnOverrideProvider.overrideWith(
      () => CoturnOverrideNotifier(coturnOverride),
    ),
    deviceReadinessProvider.overrideWith(
      readiness ?? _FailedDeviceSetupNotifier.new,
    ),
    diagnosticsDirectoryProvider.overrideWithValue(
      Directory.systemTemp.createTempSync('sonicrelay_setup_test_').path,
    ),
    relaySettingsApiProvider.overrideWithValue(
      relaySettingsApi ?? _FakeRelaySettingsApi(),
    ),
  ],
);

Future<void> _pumpApp(WidgetTester tester, ProviderContainer container) async {
  addTearDown(() => setSonicLogSink(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const SonicRelayApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterTurn(WidgetTester tester, String value) =>
    tester.enterText(find.byType(TextField).at(1), value);

Future<void> _saveSetup(WidgetTester tester) async {
  await tester.tap(find.text('Save and continue'));
  await tester.pumpAndSettle();
}

CoturnOverrideStorage _coturnStorage() =>
    const CoturnOverrideStorage(FlutterSecureStorage());

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('first-run TURN choice', () {
    testWidgets('an empty TURN field keeps the backend-provided TURN servers', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await _pumpApp(tester, container);

      await _enterTurn(tester, '');
      await _saveSetup(tester);

      expect(container.read(initialServerSetupCompletedProvider), isTrue);
      expect(container.read(coturnOverrideProvider), isNull);
      expect(await _coturnStorage().readPendingSync(), isFalse);
    });

    testWidgets(
      'leaving the pre-filled default TURN does not become an override',
      (tester) async {
        final container = _container();
        addTearDown(container.dispose);
        await _pumpApp(tester, container);

        expect(find.text(AppConfig.defaultTurnUrl), findsOneWidget);
        await _saveSetup(tester);

        expect(container.read(coturnOverrideProvider), isNull);
      },
    );

    testWidgets('a custom TURN is saved and queued for backend sync', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await _pumpApp(tester, container);

      await _enterTurn(tester, _customTurn);
      await _saveSetup(tester);

      expect(container.read(coturnOverrideProvider), _customTurn);
      expect(await _coturnStorage().readPendingSync(), isTrue);
    });
  });

  testWidgets(
    'a failed device setup can reopen the server setup to fix the address',
    (tester) async {
      final container = _container(setupCompleted: true);
      addTearDown(container.dispose);
      await _pumpApp(tester, container);

      expect(find.text('Retry device setup'), findsOneWidget);
      await tester.tap(find.text('Change server address'));
      await tester.pumpAndSettle();

      expect(find.text('Server setup'), findsOneWidget);
      expect(container.read(initialServerSetupCompletedProvider), isFalse);
    },
  );

  group('RelaySettingsSync.pull', () {
    test('pushes a pending first-run TURN instead of overwriting it', () async {
      await _coturnStorage().writePendingSync(true);
      final api = _FakeRelaySettingsApi();
      final container = _container(
        coturnOverride: _customTurn,
        readiness: _ReadyReadinessNotifier.new,
        relaySettingsApi: api,
      );
      addTearDown(container.dispose);

      await container.read(relaySettingsSyncProvider).pull();

      expect(container.read(coturnOverrideProvider), _customTurn);
      expect(api.pushedTurnUris, [
        [_customTurn],
      ]);
      expect(await _coturnStorage().readPendingSync(), isFalse);
    });

    test('adopts the backend TURN when nothing is pending', () async {
      final container = _container(
        coturnOverride: _customTurn,
        readiness: _ReadyReadinessNotifier.new,
        relaySettingsApi: _FakeRelaySettingsApi(
          turnUris: ['turn:other.example.com:3478'],
        ),
      );
      addTearDown(container.dispose);

      await container.read(relaySettingsSyncProvider).pull();

      expect(
        container.read(coturnOverrideProvider),
        'turn:other.example.com:3478',
      );
    });
  });
}
