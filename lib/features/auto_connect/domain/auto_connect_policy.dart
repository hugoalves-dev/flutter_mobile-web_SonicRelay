import '../../sessions/data/dto/discoverable_session.dart';
import '../../sessions/data/sessions_repository.dart';
import '../../sessions/presentation/join_session_view_model.dart';
import 'auto_connect_settings.dart';

/// What the next step after a failed automatic join is. Every path ends in either a
/// bounded retry or giving up, so a failure can never turn into a join loop.
sealed class FailureAction {
  const FailureAction();
}

/// Retry the same session after [delay].
class RetryAfter extends FailureAction {
  const RetryAfter(this.delay);
  final Duration delay;
}

/// Never auto-attempt this session again in this process. A new session from the same
/// publisher is still eligible.
class BlockSession extends FailureAction {
  const BlockSession(this.message);
  final String message;
}

/// Stop auto-connect until the app restarts: the device identity itself is unusable.
class StopAll extends FailureAction {
  const StopAll(this.message);
  final String message;
}

/// Pure decisions behind auto-connect (spec 2026-11-17-auto-connect-paired-publisher).
abstract final class AutoConnectPolicy {
  static const retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 45),
  ];

  /// The session to join now, or null when nothing should be attempted.
  static DiscoverableSession? pick({
    required AutoConnectSettings settings,
    required bool paused,
    required bool stopped,
    required JoinSessionStatus joinStatus,
    required List<DiscoverableSession> sessions,
    required Set<String> blocked,
    required Set<String> coolingDown,
  }) {
    if (!settings.isActive || paused || stopped) return null;
    // Joining or joined means a session is starting or playing: never replace it.
    if (joinStatus == JoinSessionStatus.joining ||
        joinStatus == JoinSessionStatus.joined) {
      return null;
    }
    final candidates = sessions.where(
      (s) =>
          s.publisherDeviceId == settings.publisherDeviceId &&
          !s.isFull &&
          !blocked.contains(s.sessionId) &&
          !coolingDown.contains(s.sessionId),
    );
    DiscoverableSession? newest;
    for (final session in candidates) {
      if (newest == null || _isNewer(session, newest)) newest = session;
    }
    return newest;
  }

  /// What to do after the [attempt]-th failed join (1-based) of one session.
  static FailureAction onFailure(
    SessionsFailureKind kind,
    int attempt,
    String deviceName,
  ) => switch (kind) {
    SessionsFailureKind.network || SessionsFailureKind.manualRetry =>
      attempt <= retryDelays.length
          ? RetryAfter(retryDelays[attempt - 1])
          : BlockSession('Could not reach $deviceName. Join it manually.'),
    SessionsFailureKind.maxViewers => BlockSession(
      '$deviceName has no free listener slot.',
    ),
    SessionsFailureKind.notPaired => BlockSession(
      'Pairing with $deviceName is no longer active.',
    ),
    SessionsFailureKind.unauthorized || SessionsFailureKind.missingDevice =>
      const StopAll('Your device identity is no longer authorized.'),
    SessionsFailureKind.invalidCode ||
    SessionsFailureKind.expiredCode ||
    SessionsFailureKind.invalidResponse => BlockSession(
      'The session on $deviceName is no longer available.',
    ),
  };

  static bool _isNewer(DiscoverableSession a, DiscoverableSession b) {
    final aAt = a.createdAt;
    final bAt = b.createdAt;
    if (aAt == null) return false;
    return bAt == null || aAt.isAfter(bAt);
  }
}
