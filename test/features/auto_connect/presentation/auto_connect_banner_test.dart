import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/core/network/network_monitor.dart';
import 'package:sonic_relay/features/auto_connect/presentation/auto_connect_banner.dart';
import 'package:sonic_relay/features/auto_connect/presentation/auto_connect_controller.dart';
import 'package:sonic_relay/features/sessions/data/dto/discoverable_session.dart';
import 'package:sonic_relay/features/sessions/data/dto/public_room_info.dart';
import 'package:sonic_relay/features/sessions/data/sessions_repository.dart';
import 'package:sonic_relay/features/sessions/domain/stream_session.dart';

const _homeSession = DiscoverableSession(
  sessionId: 's1',
  publisherDeviceId: 'pub-1',
  publisherDeviceName: 'Home PC',
  status: 'waiting',
  viewerCount: 0,
  maxViewers: 2,
);

class _FakeRepository implements SessionsRepository {
  final List<String> joinedIds = [];

  @override
  StreamSession? get currentSession => null;

  @override
  Future<StreamSession> joinById(String sessionId) async {
    joinedIds.add(sessionId);
    return StreamSession(
      sessionId: sessionId,
      signalingUrl: Uri.parse('wss://x/ws'),
    );
  }

  @override
  Future<StreamSession> join(String code) => throw UnimplementedError();

  @override
  Future<List<DiscoverableSession>> discover() async => const [];

  @override
  Future<PublicRoomInfo> getPublicRoom() async =>
      const PublicRoomInfo.disabled();
}

Future<(ProviderContainer, _FakeRepository)> _pump(
  WidgetTester tester, {
  bool enabled = true,
  List<DiscoverableSession> discovered = const [],
}) async {
  FlutterSecureStorage.setMockInitialValues({
    'autoConnect.enabled': enabled ? 'true' : 'false',
    'autoConnect.publisherDeviceId': 'pub-1',
    'autoConnect.publisherDeviceName': 'Home PC',
  });
  final repository = _FakeRepository();
  final container = ProviderContainer(
    overrides: [
      sessionsRepositoryProvider.overrideWithValue(repository),
      networkMonitorProvider.overrideWithValue(NoopNetworkMonitor()),
      discoverableSessionsProvider.overrideWith(
        (ref) => Stream.value(discovered),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: AutoConnectBanner())),
    ),
  );
  await tester.pumpAndSettle();
  return (container, repository);
}

void main() {
  testWidgets('shows nothing when auto-connect is off', (tester) async {
    await _pump(tester, enabled: false);

    expect(find.textContaining('Auto-connect'), findsNothing);
  });

  testWidgets('waits for the selected device by name', (tester) async {
    await _pump(tester);

    expect(find.text('Auto-connect: waiting for Home PC'), findsOneWidget);
  });

  testWidgets('joins the selected publisher when discovery reports it', (
    tester,
  ) async {
    final (_, repository) = await _pump(tester, discovered: [_homeSession]);

    expect(repository.joinedIds, ['s1']);
  });

  testWidgets('a paused state offers Resume', (tester) async {
    final (container, _) = await _pump(tester);

    container
        .read(autoConnectControllerProvider.notifier)
        .pauseAfterLeave('s1');
    await tester.pumpAndSettle();

    expect(
      find.text('Auto-connect paused (you left the session)'),
      findsOneWidget,
    );
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();

    expect(
      container.read(autoConnectControllerProvider).phase,
      AutoConnectPhase.waiting,
    );
  });

  testWidgets('does not join while another page covers the join page', (
    tester,
  ) async {
    // Settings is pushed over the join page, which stays mounted underneath.
    final (container, repository) = await _pump(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Settings')),
      ),
    );
    await tester.pumpAndSettle();

    await container.read(autoConnectControllerProvider.notifier).onDiscovery([
      _homeSession,
    ]);
    expect(repository.joinedIds, isEmpty);

    navigator.pop();
    await tester.pumpAndSettle();
    await container.read(autoConnectControllerProvider.notifier).onDiscovery([
      _homeSession,
    ]);

    expect(repository.joinedIds, ['s1']);
  });

  testWidgets('shows the connecting state', (tester) async {
    final (container, _) = await _pump(tester);

    container
        .read(autoConnectControllerProvider.notifier)
        .state = const AutoConnectStatus(
      AutoConnectPhase.connecting,
      deviceName: 'Home PC',
    );
    await tester.pump();

    expect(find.text('Connecting to Home PC…'), findsOneWidget);
  });
}
