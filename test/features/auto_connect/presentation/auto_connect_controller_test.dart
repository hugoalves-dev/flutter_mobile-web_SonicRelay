import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/features/auto_connect/domain/auto_connect_policy.dart';
import 'package:sonic_relay/features/auto_connect/presentation/auto_connect_controller.dart';
import 'package:sonic_relay/features/auto_connect/presentation/auto_connect_settings_notifier.dart';
import 'package:sonic_relay/features/sessions/data/dto/discoverable_session.dart';
import 'package:sonic_relay/features/sessions/data/dto/public_room_info.dart';
import 'package:sonic_relay/features/sessions/data/sessions_repository.dart';
import 'package:sonic_relay/features/sessions/domain/stream_session.dart';
import 'package:sonic_relay/features/sessions/presentation/join_session_view_model.dart';

DiscoverableSession _session(String id, {String publisher = 'pub-1'}) =>
    DiscoverableSession(
      sessionId: id,
      publisherDeviceId: publisher,
      publisherDeviceName: 'Home PC',
      status: 'waiting',
      viewerCount: 0,
      maxViewers: 2,
    );

class _FakeRepository implements SessionsRepository {
  final List<String> joinedIds = [];
  final List<SessionsFailure?> results = [];
  Completer<void>? gate;

  @override
  StreamSession? get currentSession => null;

  @override
  Future<StreamSession> joinById(String sessionId) async {
    joinedIds.add(sessionId);
    if (gate case final g?) await g.future;
    final failure = results.isEmpty ? null : results.removeAt(0);
    if (failure != null) throw failure;
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

class _FakeTimers {
  final List<_FakeTimer> timers = [];

  Timer create(Duration duration, void Function() callback) {
    final timer = _FakeTimer(duration, callback);
    timers.add(timer);
    return timer;
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.callback);
  final Duration duration;
  final void Function() callback;
  bool cancelled = false;

  void fire() {
    if (!cancelled) callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

const _network = SessionsFailure(SessionsFailureKind.network, 'offline');

void main() {
  late _FakeRepository repository;
  late _FakeTimers timers;
  late ProviderContainer container;

  Future<void> start({bool enabled = true}) async {
    FlutterSecureStorage.setMockInitialValues({
      'autoConnect.enabled': enabled ? 'true' : 'false',
      'autoConnect.publisherDeviceId': 'pub-1',
      'autoConnect.publisherDeviceName': 'Home PC',
    });
    repository = _FakeRepository();
    timers = _FakeTimers();
    container = ProviderContainer(
      overrides: [
        sessionsRepositoryProvider.overrideWithValue(repository),
        autoConnectTimerFactoryProvider.overrideWithValue(timers.create),
      ],
    );
    addTearDown(container.dispose);
    await container.read(autoConnectSettingsProvider.future);
  }

  AutoConnectController controller() =>
      container.read(autoConnectControllerProvider.notifier);
  AutoConnectStatus status() => container.read(autoConnectControllerProvider);

  Future<void> discover(List<DiscoverableSession> sessions) async {
    await controller().onDiscovery(sessions);
  }

  test('joins the selected publisher session', () async {
    await start();

    await discover([_session('s1')]);

    expect(repository.joinedIds, ['s1']);
    expect(
      container.read(joinSessionViewModelProvider).status,
      JoinSessionStatus.joined,
    );
  });

  test('does nothing when the setting is off', () async {
    await start(enabled: false);

    await discover([_session('s1')]);

    expect(repository.joinedIds, isEmpty);
    expect(status().phase, AutoConnectPhase.off);
  });

  test('reports waiting with the device name when nothing matches', () async {
    await start();

    await discover([_session('s9', publisher: 'pub-2')]);

    expect(repository.joinedIds, isEmpty);
    expect(status().phase, AutoConnectPhase.waiting);
    expect(status().deviceName, 'Home PC');
  });

  test('does not start a second join while one is in flight', () async {
    await start();
    repository.gate = Completer<void>();

    final first = discover([_session('s1')]);
    await Future<void>.delayed(Duration.zero);
    expect(status().phase, AutoConnectPhase.connecting);
    await discover([_session('s1')]);
    repository.gate!.complete();
    await first;

    expect(repository.joinedIds, ['s1']);
  });

  test('retries a network failure after 5 seconds', () async {
    await start();
    repository.results.add(_network);

    await discover([_session('s1')]);
    expect(timers.timers.single.duration, const Duration(seconds: 5));
    // Still cooling down: the next poll must not attempt it.
    await discover([_session('s1')]);
    expect(repository.joinedIds, ['s1']);

    timers.timers.single.fire();
    await Future<void>.delayed(Duration.zero);

    expect(repository.joinedIds, ['s1', 's1']);
  });

  test('gives up on a session after three network retries', () async {
    await start();
    repository.results.addAll([_network, _network, _network, _network]);

    await discover([_session('s1')]);
    for (var i = 0; i < 3; i++) {
      timers.timers.last.fire();
      await Future<void>.delayed(Duration.zero);
    }
    await discover([_session('s1')]);

    expect(repository.joinedIds, hasLength(4));
    expect(timers.timers, hasLength(3));
    expect(status().message, isNotNull);
  });

  test('leave pauses auto-connect and blocks the left session', () async {
    await start();

    controller().pauseAfterLeave('s1');
    await discover([_session('s1'), _session('s2')]);

    expect(repository.joinedIds, isEmpty);
    expect(status().phase, AutoConnectPhase.paused);
  });

  test('resume joins a new session but never the one that was left', () async {
    await start();
    controller().pauseAfterLeave('s1');

    controller().resume();
    await discover([_session('s1')]);
    expect(repository.joinedIds, isEmpty);

    await discover([_session('s1'), _session('s2')]);
    expect(repository.joinedIds, ['s2']);
  });

  test('an identity failure stops all further attempts', () async {
    await start();
    repository.results.add(
      const SessionsFailure(SessionsFailureKind.unauthorized, 'no'),
    );

    await discover([_session('s1')]);
    await discover([_session('s2')]);

    expect(repository.joinedIds, ['s1']);
    expect(status().phase, AutoConnectPhase.error);
  });

  test(
    'a session ended by the publisher does not block the next one',
    () async {
      await start();

      await discover([_session('s1')]);
      await discover([_session('s2')]);

      expect(repository.joinedIds, ['s1', 's2']);
    },
  );

  test('cancelPending cancels a scheduled retry', () async {
    await start();
    repository.results.add(_network);
    await discover([_session('s1')]);

    controller().cancelPending();
    timers.timers.single.fire();
    await Future<void>.delayed(Duration.zero);

    expect(repository.joinedIds, ['s1']);
  });

  test('uses the policy retry schedule', () {
    expect(AutoConnectPolicy.retryDelays.first, const Duration(seconds: 5));
  });
}
