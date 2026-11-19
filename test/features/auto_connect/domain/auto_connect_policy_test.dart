import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/features/auto_connect/domain/auto_connect_policy.dart';
import 'package:sonic_relay/features/auto_connect/domain/auto_connect_settings.dart';
import 'package:sonic_relay/features/sessions/data/dto/discoverable_session.dart';
import 'package:sonic_relay/features/sessions/data/sessions_repository.dart';
import 'package:sonic_relay/features/sessions/presentation/join_session_view_model.dart';

const _selected = AutoConnectSettings(
  enabled: true,
  publisherDeviceId: 'pub-1',
  publisherDeviceName: 'Home PC',
);

DiscoverableSession _session(
  String id, {
  String publisher = 'pub-1',
  DateTime? createdAt,
  int viewers = 0,
  int maxViewers = 2,
}) => DiscoverableSession(
  sessionId: id,
  publisherDeviceId: publisher,
  publisherDeviceName: 'Home PC',
  status: 'waiting',
  viewerCount: viewers,
  maxViewers: maxViewers,
  createdAt: createdAt,
);

DiscoverableSession? _pick({
  AutoConnectSettings settings = _selected,
  bool paused = false,
  bool stopped = false,
  JoinSessionStatus joinStatus = JoinSessionStatus.idle,
  required List<DiscoverableSession> sessions,
  Set<String> blocked = const {},
  Set<String> coolingDown = const {},
}) => AutoConnectPolicy.pick(
  settings: settings,
  paused: paused,
  stopped: stopped,
  joinStatus: joinStatus,
  sessions: sessions,
  blocked: blocked,
  coolingDown: coolingDown,
);

void main() {
  group('pick', () {
    test('returns the selected publisher session when idle', () {
      expect(_pick(sessions: [_session('s1')])?.sessionId, 's1');
    });

    test('also attempts after a previous failure', () {
      expect(
        _pick(
          joinStatus: JoinSessionStatus.failed,
          sessions: [_session('s1')],
        )?.sessionId,
        's1',
      );
    });

    test('does nothing when off or nothing is selected', () {
      expect(
        _pick(settings: AutoConnectSettings.off, sessions: [_session('s1')]),
        isNull,
      );
      expect(
        _pick(
          settings: const AutoConnectSettings(enabled: true),
          sessions: [_session('s1')],
        ),
        isNull,
      );
    });

    test('does nothing while paused or stopped', () {
      expect(_pick(paused: true, sessions: [_session('s1')]), isNull);
      expect(_pick(stopped: true, sessions: [_session('s1')]), isNull);
    });

    test('never interrupts a join in flight or an active session', () {
      expect(
        _pick(
          joinStatus: JoinSessionStatus.joining,
          sessions: [_session('s1')],
        ),
        isNull,
      );
      expect(
        _pick(joinStatus: JoinSessionStatus.joined, sessions: [_session('s1')]),
        isNull,
      );
    });

    test('ignores sessions of other publishers', () {
      expect(_pick(sessions: [_session('s1', publisher: 'pub-2')]), isNull);
    });

    test('skips blocked and cooling-down sessions', () {
      expect(_pick(sessions: [_session('s1')], blocked: {'s1'}), isNull);
      expect(_pick(sessions: [_session('s1')], coolingDown: {'s1'}), isNull);
    });

    test('skips a full session', () {
      expect(
        _pick(sessions: [_session('s1', viewers: 2, maxViewers: 2)]),
        isNull,
      );
    });

    test('picks the newest of several matching sessions', () {
      final picked = _pick(
        sessions: [
          _session('old', createdAt: DateTime.utc(2026, 1, 1)),
          _session('new', createdAt: DateTime.utc(2026, 1, 2)),
        ],
      );

      expect(picked?.sessionId, 'new');
    });
  });

  group('onFailure', () {
    test('network failures back off 5, 15 and 45 seconds, then block', () {
      expect(
        AutoConnectPolicy.onFailure(SessionsFailureKind.network, 1, 'Home PC'),
        isA<RetryAfter>().having(
          (a) => a.delay,
          'delay',
          const Duration(seconds: 5),
        ),
      );
      expect(
        (AutoConnectPolicy.onFailure(SessionsFailureKind.network, 2, 'Home PC')
                as RetryAfter)
            .delay,
        const Duration(seconds: 15),
      );
      expect(
        (AutoConnectPolicy.onFailure(
                  SessionsFailureKind.manualRetry,
                  3,
                  'Home PC',
                )
                as RetryAfter)
            .delay,
        const Duration(seconds: 45),
      );
      expect(
        AutoConnectPolicy.onFailure(SessionsFailureKind.network, 4, 'Home PC'),
        isA<BlockSession>(),
      );
    });

    test('session-level refusals block only that session', () {
      for (final kind in [
        SessionsFailureKind.maxViewers,
        SessionsFailureKind.invalidCode,
        SessionsFailureKind.expiredCode,
        SessionsFailureKind.invalidResponse,
      ]) {
        expect(
          AutoConnectPolicy.onFailure(kind, 1, 'Home PC'),
          isA<BlockSession>(),
          reason: '$kind',
        );
      }
    });

    test('a revoked pairing blocks with a message naming the device', () {
      final action = AutoConnectPolicy.onFailure(
        SessionsFailureKind.notPaired,
        1,
        'Home PC',
      );

      expect(action, isA<BlockSession>());
      expect(
        (action as BlockSession).message,
        'Pairing with Home PC is no longer active.',
      );
    });

    test('identity failures stop auto-connect entirely', () {
      expect(
        AutoConnectPolicy.onFailure(SessionsFailureKind.unauthorized, 1, 'x'),
        isA<StopAll>(),
      );
      expect(
        AutoConnectPolicy.onFailure(SessionsFailureKind.missingDevice, 1, 'x'),
        isA<StopAll>(),
      );
    });
  });
}
