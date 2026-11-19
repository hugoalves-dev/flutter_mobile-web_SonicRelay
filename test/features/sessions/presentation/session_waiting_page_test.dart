import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sonic_relay/features/listener/presentation/listener_view_model.dart';
import 'package:sonic_relay/features/sessions/domain/stream_session.dart';
import 'package:sonic_relay/features/sessions/presentation/join_session_view_model.dart';
import 'package:sonic_relay/features/sessions/presentation/session_waiting_page.dart';

final _session = StreamSession(
  sessionId: 'session-1',
  signalingUrl: Uri.parse('wss://stream.example/ws/signaling'),
);

class _JoinedSessionViewModel extends JoinSessionViewModel {
  @override
  JoinSessionState build() => JoinSessionState(
    code: 'ABC123',
    status: JoinSessionStatus.joined,
    session: _session,
  );
}

class _ConnectedListenerViewModel extends ListenerViewModel {
  @override
  ListenerState build() => const ListenerState();

  @override
  Future<void> connect({required StreamSession session}) async {}
}

class _PendingListenerViewModel extends ListenerViewModel {
  final connectStarted = Completer<void>();
  final connectResult = Completer<void>();
  var leaveCalls = 0;

  @override
  ListenerState build() => const ListenerState();

  @override
  Future<void> connect({required StreamSession session}) {
    connectStarted.complete();
    return connectResult.future;
  }

  @override
  Future<void> leave({bool pauseAutoConnect = true}) async {
    leaveCalls++;
  }
}

void main() {
  testWidgets('opens listener after joining a session', (tester) async {
    final router = GoRouter(
      initialLocation: '/waiting',
      routes: [
        GoRoute(
          path: '/waiting',
          builder: (_, _) => const SessionWaitingPage(),
        ),
        GoRoute(
          path: '/listener',
          builder: (_, _) => const Scaffold(body: Text('Listener connected')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          joinSessionViewModelProvider.overrideWith(
            _JoinedSessionViewModel.new,
          ),
          listenerViewModelProvider.overrideWith(
            _ConnectedListenerViewModel.new,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Listener connected'), findsOneWidget);
  });

  testWidgets('leaving while connect is pending cancels the session handoff', (
    tester,
  ) async {
    final listener = _PendingListenerViewModel();
    final router = GoRouter(
      initialLocation: '/waiting',
      routes: [
        GoRoute(
          path: '/waiting',
          builder: (_, _) => const SessionWaitingPage(),
        ),
        GoRoute(
          path: '/join',
          builder: (_, _) => const Scaffold(body: Text('Join session')),
        ),
        GoRoute(
          path: '/listener',
          builder: (_, _) => const Scaffold(body: Text('Listener connected')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          joinSessionViewModelProvider.overrideWith(
            _JoinedSessionViewModel.new,
          ),
          listenerViewModelProvider.overrideWith(() => listener),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await listener.connectStarted.future;

    router.go('/join');
    await tester.pumpAndSettle();

    expect(listener.leaveCalls, 1);
    listener.connectResult.complete();
    await tester.pumpAndSettle();
    expect(find.text('Join session'), findsOneWidget);
    expect(find.text('Listener connected'), findsNothing);
  });
}
