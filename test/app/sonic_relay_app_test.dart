import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/app/sonic_relay_app.dart';
import 'package:sonic_relay/core/diagnostics/sonic_log.dart';
import 'package:dio/dio.dart';
import 'package:sonic_relay/core/storage/relay_mode_storage.dart';
import 'package:sonic_relay/core/storage/theme_mode_storage.dart';
import 'package:sonic_relay/core/webrtc/relay_modes.dart';
import 'package:sonic_relay/core/webrtc/relay_settings_api.dart';
import 'package:sonic_relay/features/listener/presentation/listener_page.dart';
import 'package:sonic_relay/features/sessions/data/dto/public_room_info.dart';
import 'package:sonic_relay/features/sessions/presentation/join_session_page.dart';
import 'package:sonic_relay/features/settings/presentation/settings_page.dart';

String _testDiagnosticsDirectory() =>
    Directory.systemTemp.createTempSync('sonicrelay_app_test_').path;

/// Avoids the real `FlutterSecureStorage` plugin, which has no platform channel under
/// `flutter test`.
class _FakeRelayModeStorage extends RelayModeStorage {
  _FakeRelayModeStorage() : super(const FlutterSecureStorage());

  String stored = RelayModes.automatic;

  @override
  Future<String> read() async => stored;

  @override
  Future<void> write(String mode) async => stored = mode;
}

/// Avoids the real `FlutterSecureStorage` plugin, same reasoning as
/// [_FakeRelayModeStorage].
class _FakeThemeModeStorage extends ThemeModeStorage {
  _FakeThemeModeStorage() : super(const FlutterSecureStorage());

  ThemeMode stored = ThemeMode.system;

  @override
  Future<ThemeMode> read() async => stored;

  @override
  Future<void> write(ThemeMode mode) async => stored = mode;
}

/// Avoids a real Dio call (and its dangling timer) when the settings page
/// mounts with a ready device and pulls the synced relay preferences.
class _FakeRelaySettingsApi extends RelaySettingsApi {
  _FakeRelaySettingsApi() : super(Dio());

  @override
  Future<RelaySettings> fetch() async =>
      const RelaySettings(relayMode: RelayModes.automatic, turnUris: []);

  @override
  Future<void> update({String? relayMode, List<String>? turnUris}) async {}
}

ProviderScope testApp() => ProviderScope(
  overrides: [
    initialServerSetupCompletedProvider.overrideWith(
      () => InitialServerSetupCompletedNotifier(true),
    ),
    deviceReadinessProvider.overrideWith(_ReadyReadinessNotifier.new),
    onboardingCompletedProvider.overrideWith(
      () => OnboardingCompletedNotifier(true),
    ),
    diagnosticsDirectoryProvider.overrideWithValue(_testDiagnosticsDirectory()),
    relayModeStorageProvider.overrideWithValue(_FakeRelayModeStorage()),
    themeModeStorageProvider.overrideWithValue(_FakeThemeModeStorage()),
    // Avoids a real Dio call (and its dangling timer) when the join page mounts and watches
    // this provider eagerly.
    discoverableSessionsProvider.overrideWith((ref) => Stream.value(const [])),
    // Avoids a real Dio call (and its dangling timer) when the join page mounts and watches
    // this provider eagerly, same reasoning as discoverableSessionsProvider above.
    publicRoomProvider.overrideWith(
      (ref) => Stream.value(const PublicRoomInfo.disabled()),
    ),
    relaySettingsApiProvider.overrideWithValue(_FakeRelaySettingsApi()),
  ],
  child: const SonicRelayApp(),
);

void main() {
  testWidgets(
    'wires a light and a dark Material 3 theme, defaulting to system',
    (tester) async {
      await tester.pumpWidget(testApp());
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.theme?.useMaterial3, isTrue);
      expect(materialApp.theme?.brightness, Brightness.light);
      expect(materialApp.darkTheme?.useMaterial3, isTrue);
      expect(materialApp.darkTheme?.brightness, Brightness.dark);
      expect(materialApp.themeMode, ThemeMode.system);
    },
  );

  testWidgets(
    'selecting Light in Settings switches the active theme immediately',
    (tester) async {
      await tester.pumpWidget(testApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);

      await tester.ensureVisible(find.text('Light'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.light);
      expect(
        Theme.of(tester.element(find.text('Appearance'))).brightness,
        Brightness.light,
      );
    },
  );

  testWidgets('startup opens device-first join without any account UI', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text('Join stream'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('feature pages show device-first presentation content', (
    tester,
  ) async {
    // Fixed once per test: the ProviderScope below is reused (updated, not
    // recreated) by Flutter's element diffing across the three pumpWidget
    // calls, since it has no distinguishing key. Regenerating this value on
    // every pumpPage call made diagnosticsDirectoryProvider look "changed" on
    // each pump, cascading an invalidation down to the non-autoDispose
    // listenerViewModelProvider and making it rebuild on its existing
    // Notifier instance — which crashed on the `late final` fields in
    // ListenerViewModel.build() already being set from the first pump.
    final diagnosticsDirectory = _testDiagnosticsDirectory();

    Future<void> pumpPage(Widget page) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceReadinessProvider.overrideWith(_ReadyReadinessNotifier.new),
            diagnosticsDirectoryProvider.overrideWithValue(
              diagnosticsDirectory,
            ),
            relayModeStorageProvider.overrideWithValue(_FakeRelayModeStorage()),
            discoverableSessionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            publicRoomProvider.overrideWith(
              (ref) => Stream.value(const PublicRoomInfo.disabled()),
            ),
            relaySettingsApiProvider.overrideWithValue(_FakeRelaySettingsApi()),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: page,
          ),
        ),
      );
    }

    await pumpPage(const JoinSessionPage());
    expect(find.text('Join stream'), findsOneWidget);

    await pumpPage(const ListenerPage());
    expect(find.text('Audio monitor'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('WebRTC / ICE'), findsOneWidget);

    await pumpPage(const SettingsPage());
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Manage pairings'), findsOneWidget);
    expect(find.text('Reset device identity'), findsOneWidget);
    expect(find.text('Log out'), findsNothing);
    expect(find.text('Delete account'), findsNothing);
  });

  testWidgets('device-first startup fits a common small Android viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // Without this wiring the mechanism in sonic_log.dart is inert in the real
  // app: `Background` and `WebRTC` lines stay in logcat only, so an exported
  // log from a phone that streamed for hours shows no foreground-service
  // activity — which reads exactly like the service never having run.
  testWidgets('running the app routes tagged logs into the exportable log', (
    tester,
  ) async {
    addTearDown(() => setSonicLogSink(null));
    final container = ProviderContainer(
      overrides: [
        initialServerSetupCompletedProvider.overrideWith(
          () => InitialServerSetupCompletedNotifier(true),
        ),
        deviceReadinessProvider.overrideWith(_ReadyReadinessNotifier.new),
        onboardingCompletedProvider.overrideWith(
          () => OnboardingCompletedNotifier(true),
        ),
        diagnosticsDirectoryProvider.overrideWithValue(
          _testDiagnosticsDirectory(),
        ),
        relayModeStorageProvider.overrideWithValue(_FakeRelayModeStorage()),
        discoverableSessionsProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
        publicRoomProvider.overrideWith(
          (ref) => Stream.value(const PublicRoomInfo.disabled()),
        ),
        relaySettingsApiProvider.overrideWithValue(_FakeRelaySettingsApi()),
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

    sonicLog('Background', 'starting foreground service');
    await tester.pumpAndSettle();

    final events = container.read(diagnosticLogProvider).recentEvents;
    expect(
      events.map((event) => (event.category, event.message)),
      contains(('Background', 'starting foreground service')),
    );
  });
}

class _ReadyReadinessNotifier extends DeviceReadinessNotifier {
  @override
  DeviceReadinessState build() => const DeviceReadinessState.ready();
}
