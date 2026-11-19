import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';
import '../data/dto/discoverable_session.dart';
import '../data/sessions_repository.dart';
import '../domain/stream_session.dart';

enum JoinSessionStatus { idle, joining, joined, failed }

class JoinSessionState {
  const JoinSessionState({
    this.code = '',
    this.status = JoinSessionStatus.idle,
    this.validationMessage,
    this.errorMessage,
    this.session,
    this.retryable = false,
    this.retryTarget,
    this.retryPublicRoomSessionId,
  });

  final String code;
  final JoinSessionStatus status;
  final String? validationMessage;
  final String? errorMessage;
  final StreamSession? session;
  final bool retryable;

  /// The discovered session a failed [JoinSessionViewModel.joinDiscovered] should re-attempt
  /// on retry, or null when the failure came from the manual code path (retry re-reads
  /// [code] instead). Set alongside [retryable] whenever a discovered-session join fails.
  final DiscoverableSession? retryTarget;

  /// The public room session id a failed [JoinSessionViewModel.joinPublicRoom] should
  /// re-attempt on retry. Mutually exclusive with [retryTarget] — the public room has no
  /// [DiscoverableSession] (it isn't in that list; see [PublicRoomInfo]).
  final String? retryPublicRoomSessionId;

  bool get isJoining => status == JoinSessionStatus.joining;
  bool get canRetry => status == JoinSessionStatus.failed && retryable;
}

final joinSessionViewModelProvider =
    NotifierProvider<JoinSessionViewModel, JoinSessionState>(
      JoinSessionViewModel.new,
    );

class JoinSessionViewModel extends Notifier<JoinSessionState> {
  // Exactly what the backend accepts (SessionEndpoints.JoinAsync): six ASCII alphanumerics.
  // The old 4-12 pattern with hyphens let codes through that the server always rejected,
  // which surfaced to the user as a useless "invalid code".
  static final _validCode = RegExp(r'^[A-Z0-9]{6}$');
  late final SessionsRepository _repository;

  @override
  JoinSessionState build() {
    _repository = ref.watch(sessionsRepositoryProvider);
    return const JoinSessionState();
  }

  void updateCode(String value) {
    // Strip whitespace and hyphens anywhere in the string, not just at the ends, so a code
    // that was pasted or read aloud with separators still normalises to what the server wants.
    state = JoinSessionState(
      code: value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase(),
    );
  }

  Future<void> join() async {
    if (!_validCode.hasMatch(state.code)) {
      state = JoinSessionState(
        code: state.code,
        validationMessage: 'Enter a valid session code.',
      );
      return;
    }

    state = JoinSessionState(
      code: state.code,
      status: JoinSessionStatus.joining,
    );
    try {
      final session = await _repository.join(state.code);
      state = JoinSessionState(
        code: state.code,
        status: JoinSessionStatus.joined,
        session: session,
      );
    } on SessionsFailure catch (error) {
      _applyFailure(error);
    } catch (_) {
      state = JoinSessionState(
        code: state.code,
        status: JoinSessionStatus.failed,
        errorMessage: 'Unable to join the session. Please retry.',
        retryable: true,
      );
    }
  }

  /// Retries whichever path last failed: the public room re-attempts its session id, a
  /// discovered-session tap re-attempts that same session (there is no code to re-read for
  /// either), everything else re-reads [state.code] through [join].
  Future<void> retry() {
    if (state.retryPublicRoomSessionId case final sessionId?) {
      return joinPublicRoom(sessionId);
    }
    final target = state.retryTarget;
    return target != null ? joinDiscovered(target) : join();
  }

  /// Joins a discovered session without a code. Returns null on success, or the failure
  /// kind so automatic callers (auto-connect) can decide whether to retry; an unexpected
  /// error is reported as [SessionsFailureKind.network], which only ever earns a bounded
  /// retry.
  Future<SessionsFailureKind?> joinDiscovered(
    DiscoverableSession session,
  ) async {
    state = JoinSessionState(
      code: state.code,
      status: JoinSessionStatus.joining,
      retryTarget: session,
    );
    try {
      final joined = await _repository.joinById(session.sessionId);
      state = JoinSessionState(
        code: state.code,
        status: JoinSessionStatus.joined,
        session: joined,
      );
      return null;
    } on SessionsFailure catch (error) {
      _applyFailure(error, retryTarget: session);
      return error.kind;
    } catch (_) {
      state = JoinSessionState(
        code: state.code,
        status: JoinSessionStatus.failed,
        errorMessage: 'Unable to join the session. Please retry.',
        retryable: true,
        retryTarget: session,
      );
      return SessionsFailureKind.network;
    }
  }

  Future<void> joinPublicRoom(String sessionId) async {
    state = JoinSessionState(
      code: state.code,
      status: JoinSessionStatus.joining,
      retryPublicRoomSessionId: sessionId,
    );
    try {
      final joined = await _repository.joinById(sessionId);
      state = JoinSessionState(
        code: state.code,
        status: JoinSessionStatus.joined,
        session: joined,
      );
    } on SessionsFailure catch (error) {
      _applyFailure(error, retryPublicRoomSessionId: sessionId);
    } catch (_) {
      state = JoinSessionState(
        code: state.code,
        status: JoinSessionStatus.failed,
        errorMessage: 'Unable to join the session. Please retry.',
        retryable: true,
        retryPublicRoomSessionId: sessionId,
      );
    }
  }

  /// Shared failure handling for [join], [joinDiscovered], and [joinPublicRoom], so every
  /// join path always reports and recovers from a given [SessionsFailureKind] the same way.
  /// At most one of [retryTarget]/[retryPublicRoomSessionId] should be set, matching which
  /// path is retrying; both null means the manual code path.
  void _applyFailure(
    SessionsFailure error, {
    DiscoverableSession? retryTarget,
    String? retryPublicRoomSessionId,
  }) {
    var message = error.message;
    if (error.kind == SessionsFailureKind.unauthorized) {
      message = 'Your device identity is no longer authorized.';
      ref.read(deviceReadinessProvider.notifier).requireDeviceSetup(message);
    }
    state = JoinSessionState(
      code: state.code,
      status: JoinSessionStatus.failed,
      errorMessage: message,
      retryable:
          error.kind == SessionsFailureKind.network ||
          error.kind == SessionsFailureKind.manualRetry ||
          error.kind == SessionsFailureKind.missingDevice ||
          error.kind == SessionsFailureKind.invalidResponse,
      retryTarget: retryTarget,
      retryPublicRoomSessionId: retryPublicRoomSessionId,
    );
  }
}
