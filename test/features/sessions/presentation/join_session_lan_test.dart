import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/app/di/lan_providers.dart';
import 'package:sonic_relay/core/webrtc/connectivity_modes.dart';
import 'package:sonic_relay/features/lan/data/lan_session_connector.dart';
import 'package:sonic_relay/features/lan/domain/lan_failure.dart';
import 'package:sonic_relay/features/lan/domain/lan_session_target.dart';
import 'package:sonic_relay/features/lan/domain/trusted_publisher.dart';
import 'package:sonic_relay/features/sessions/data/dto/discoverable_session.dart';
import 'package:sonic_relay/features/sessions/data/dto/public_room_info.dart';
import 'package:sonic_relay/features/sessions/data/sessions_repository.dart';
import 'package:sonic_relay/features/sessions/domain/stream_session.dart';
import 'package:sonic_relay/features/sessions/presentation/join_session_view_model.dart';

const publisher = TrustedPublisher(
  publisherDeviceId: '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
  name: 'DESKTOP-01',
  pin: 'pin',
  credential: 'cred',
  lastEndpoints: ['192.168.1.20:47321'],
);

class FakeConnector implements LanSessionConnector {
  LanFailure? failure;
  int calls = 0;

  @override
  Duration get probeTimeout => Duration.zero;

  @override
  Future<StreamSession> connect(
    TrustedPublisher publisher, {
    List<String> discovered = const [],
  }) async {
    calls++;
    if (failure case final value?) throw value;
    return StreamSession(
      sessionId: 'lan-session',
      signalingUrl: Uri.parse('wss://192.168.1.20:47321/lan/v1/signaling'),
      lan: LanSessionTarget(
        publisher: publisher,
        viewerDeviceId: 'viewer',
        connector: (_, _) => throw UnimplementedError(),
      ),
    );
  }
}

class CloudRepository implements SessionsRepository {
  CloudRepository({this.sessions = const [], this.strict = false});

  final List<DiscoverableSession> sessions;
  final bool strict;
  String? joinedSessionId;

  void _guard() {
    if (strict) throw StateError('lanOnly must never call the cloud');
  }

  @override
  StreamSession? get currentSession => null;

  @override
  Future<List<DiscoverableSession>> discover() async {
    _guard();
    return sessions;
  }

  @override
  Future<StreamSession> joinById(String sessionId) async {
    _guard();
    joinedSessionId = sessionId;
    return StreamSession(
      sessionId: sessionId,
      signalingUrl: Uri.parse('wss://cloud/ws/signaling'),
    );
  }

  @override
  Future<StreamSession> join(String code) async => throw UnimplementedError();

  @override
  Future<PublicRoomInfo> getPublicRoom() async =>
      const PublicRoomInfo.disabled();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ProviderContainer container({
    required String mode,
    required FakeConnector connector,
    required CloudRepository cloud,
  }) {
    final result = ProviderContainer(
      overrides: [
        connectivityModeProvider.overrideWith(
          () => ConnectivityModeNotifier(mode),
        ),
        lanSessionConnectorProvider.overrideWithValue(connector),
        sessionsRepositoryProvider.overrideWithValue(cloud),
      ],
    );
    addTearDown(result.dispose);
    return result;
  }

  test('auto uses lan when reachable', () async {
    final connector = FakeConnector();
    final c = container(
      mode: ConnectivityModes.auto,
      connector: connector,
      cloud: CloudRepository(strict: true),
    );

    await c.read(joinSessionViewModelProvider.notifier).joinLan(publisher);

    final state = c.read(joinSessionViewModelProvider);
    expect(state.status, JoinSessionStatus.joined);
    expect(state.session!.isLan, isTrue);
  });

  test(
    'auto falls back to the same desktop on RelayControl before the session starts',
    () async {
      final connector = FakeConnector()
        ..failure = const LanFailure(LanFailureCode.unreachable);
      final cloud = CloudRepository(
        sessions: const [
          DiscoverableSession(
            sessionId: 'other',
            publisherDeviceName: 'LAPTOP',
            status: 'live',
            viewerCount: 0,
            maxViewers: 4,
          ),
          DiscoverableSession(
            sessionId: 'cloud-1',
            publisherDeviceName: 'desktop-01',
            status: 'live',
            viewerCount: 0,
            maxViewers: 4,
          ),
        ],
      );
      final c = container(
        mode: ConnectivityModes.auto,
        connector: connector,
        cloud: cloud,
      );

      await c.read(joinSessionViewModelProvider.notifier).joinLan(publisher);

      final state = c.read(joinSessionViewModelProvider);
      expect(state.status, JoinSessionStatus.joined);
      expect(state.session!.isLan, isFalse);
      expect(cloud.joinedSessionId, 'cloud-1');
      expect(state.notice, contains('lan.unreachable'));
    },
  );

  test(
    'auto without a matching cloud session reports the LAN failure',
    () async {
      final connector = FakeConnector()
        ..failure = const LanFailure(LanFailureCode.isolationSuspected);
      final c = container(
        mode: ConnectivityModes.auto,
        connector: connector,
        cloud: CloudRepository(),
      );

      await c.read(joinSessionViewModelProvider.notifier).joinLan(publisher);

      final state = c.read(joinSessionViewModelProvider);
      expect(state.status, JoinSessionStatus.failed);
      expect(state.errorMessage, contains('isolates clients'));
      expect(state.canRetry, isTrue);
    },
  );

  test('a revoked phone never falls back silently', () async {
    final connector = FakeConnector()
      ..failure = const LanFailure(LanFailureCode.revoked);
    final c = container(
      mode: ConnectivityModes.auto,
      connector: connector,
      cloud: CloudRepository(strict: true),
    );

    await c.read(joinSessionViewModelProvider.notifier).joinLan(publisher);

    expect(
      c.read(joinSessionViewModelProvider).status,
      JoinSessionStatus.failed,
    );
  });

  test('lanOnly never calls cloud', () async {
    final connector = FakeConnector()
      ..failure = const LanFailure(LanFailureCode.unreachable);
    final c = container(
      mode: ConnectivityModes.lanOnly,
      connector: connector,
      cloud: CloudRepository(strict: true),
    );

    await c.read(joinSessionViewModelProvider.notifier).joinLan(publisher);

    final state = c.read(joinSessionViewModelProvider);
    expect(state.status, JoinSessionStatus.failed);
    expect(state.errorMessage, contains('could not be reached'));
  });

  test('retry after a LAN failure retries the same desktop', () async {
    final connector = FakeConnector()
      ..failure = const LanFailure(LanFailureCode.unreachable);
    final c = container(
      mode: ConnectivityModes.lanOnly,
      connector: connector,
      cloud: CloudRepository(strict: true),
    );
    final vm = c.read(joinSessionViewModelProvider.notifier);
    await vm.joinLan(publisher);

    connector.failure = null;
    await vm.retry();

    expect(connector.calls, 2);
    expect(
      c.read(joinSessionViewModelProvider).status,
      JoinSessionStatus.joined,
    );
  });
}
