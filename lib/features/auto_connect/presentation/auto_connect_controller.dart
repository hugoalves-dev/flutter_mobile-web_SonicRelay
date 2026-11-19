import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sessions/data/dto/discoverable_session.dart';
import '../../sessions/data/sessions_repository.dart';
import '../../sessions/presentation/join_session_view_model.dart';
import '../domain/auto_connect_policy.dart';
import '../domain/auto_connect_settings.dart';
import 'auto_connect_settings_notifier.dart';

typedef AutoConnectTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// Injectable so tests fire backoff timers by hand.
final autoConnectTimerFactoryProvider = Provider<AutoConnectTimerFactory>(
  (ref) => Timer.new,
);

enum AutoConnectPhase { off, waiting, connecting, paused, error }

class AutoConnectStatus {
  const AutoConnectStatus(this.phase, {this.deviceName, this.message});

  static const off = AutoConnectStatus(AutoConnectPhase.off);

  final AutoConnectPhase phase;
  final String? deviceName;
  final String? message;
}

/// Not auto-disposed: the pause after Leave and the blocked sessions must survive the
/// join page being rebuilt, and last until the process restarts.
final autoConnectControllerProvider =
    NotifierProvider<AutoConnectController, AutoConnectStatus>(
      AutoConnectController.new,
    );

/// Joins the selected paired publisher's session when the join page reports discovery
/// results (spec 2026-11-17-auto-connect-paired-publisher). Holds only the in-process
/// state the pure [AutoConnectPolicy] needs: pause, blocked sessions and backoff.
class AutoConnectController extends Notifier<AutoConnectStatus> {
  final Set<String> _blocked = {};
  final Map<String, int> _attempts = {};
  final Map<String, Timer> _cooling = {};
  List<DiscoverableSession> _lastSessions = const [];
  bool _paused = false;
  String? _stopMessage;
  String? _message;
  bool _inFlight = false;
  bool _attached = false;

  @override
  AutoConnectStatus build() {
    ref.listen(autoConnectSettingsProvider, (_, _) => unawaited(_evaluate()));
    ref.onDispose(cancelPending);
    return _idleStatus();
  }

  AutoConnectSettings get _settings =>
      ref.read(autoConnectSettingsProvider).value ?? AutoConnectSettings.off;

  /// The join page is showing. Auto-connect only ever acts while it is: that page is
  /// unmounted while a session plays, which is what keeps a playing session from being
  /// replaced (a settings change made from the listener page must not join anything).
  void attach() => _attached = true;

  /// The join page went away: stop acting, drop scheduled retries and forget the last
  /// discovery result so a stale list is never acted on later.
  void detach() {
    _attached = false;
    _lastSessions = const [];
    cancelPending();
  }

  /// Called with every discovery result while the join page is mounted.
  Future<void> onDiscovery(List<DiscoverableSession> sessions) {
    _lastSessions = sessions;
    return _evaluate();
  }

  /// The user explicitly left a session: stop auto-connecting until the next app start or
  /// an explicit [resume], so the session just left is not immediately rejoined.
  void pauseAfterLeave(String? sessionId) {
    _paused = true;
    cancelPending();
    state = _idleStatus();
  }

  /// The user's explicit go-ahead; it may rejoin the session that was left (the desktop
  /// keeps one session id alive for hours by rotating its code).
  void resume() {
    _paused = false;
    _message = null;
    unawaited(_evaluate());
  }

  /// Drops scheduled retries. Attempt counts are kept, so a session that already used its
  /// quick retries goes straight back to the long cooldown.
  void cancelPending() {
    for (final timer in _cooling.values) {
      timer.cancel();
    }
    _cooling.clear();
  }

  Future<void> _evaluate() async {
    if (_inFlight || !_attached) return;
    final settings = _settings;
    final target = AutoConnectPolicy.pick(
      settings: settings,
      paused: _paused,
      stopped: _stopMessage != null,
      joinStatus: ref.read(joinSessionViewModelProvider).status,
      sessions: _lastSessions,
      blocked: _blocked,
      coolingDown: _cooling.keys.toSet(),
    );
    if (target == null) {
      state = _idleStatus();
      return;
    }
    await _attempt(target, settings.displayName ?? target.publisherDeviceName);
  }

  Future<void> _attempt(DiscoverableSession target, String deviceName) async {
    _inFlight = true;
    state = AutoConnectStatus(
      AutoConnectPhase.connecting,
      deviceName: deviceName,
    );
    final SessionsFailureKind? failure;
    try {
      failure = await ref
          .read(joinSessionViewModelProvider.notifier)
          .joinDiscovered(target);
    } finally {
      _inFlight = false;
    }
    if (failure == null) {
      _attempts.remove(target.sessionId);
      _message = null;
      state = _idleStatus();
      return;
    }
    final attempt = (_attempts[target.sessionId] ?? 0) + 1;
    _attempts[target.sessionId] = attempt;
    switch (AutoConnectPolicy.onFailure(failure, attempt, deviceName)) {
      case RetryAfter(:final delay, :final message):
        _message = message;
        // The page may have gone away while the join was in flight.
        if (!_attached) break;
        _cooling[target.sessionId] = ref.read(autoConnectTimerFactoryProvider)(
          delay,
          () {
            _cooling.remove(target.sessionId);
            unawaited(_evaluate());
          },
        );
      case BlockSession(:final message):
        _blocked.add(target.sessionId);
        _message = message;
      case StopAll(:final message):
        _stopMessage = message;
        cancelPending();
    }
    state = _idleStatus();
  }

  AutoConnectStatus _idleStatus() {
    final settings = _settings;
    if (!settings.isActive) return AutoConnectStatus.off;
    final name = settings.displayName;
    if (_stopMessage case final message?) {
      return AutoConnectStatus(
        AutoConnectPhase.error,
        deviceName: name,
        message: message,
      );
    }
    if (_paused) {
      return AutoConnectStatus(AutoConnectPhase.paused, deviceName: name);
    }
    return AutoConnectStatus(
      AutoConnectPhase.waiting,
      deviceName: name,
      message: _message,
    );
  }
}
