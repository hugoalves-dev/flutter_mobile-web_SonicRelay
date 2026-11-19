import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/webrtc/rtc_peer_connection_factory.dart';
import 'package:sonic_relay/features/listener/domain/listener_connection_state.dart';
import 'package:sonic_relay/features/listener/domain/listener_stats.dart';
import 'package:sonic_relay/features/listener/presentation/listener_page.dart';
import 'package:sonic_relay/features/listener/presentation/listener_view_model.dart';
import 'package:sonic_relay/features/signaling/data/signaling_client.dart';

class _StubListenerViewModel extends ListenerViewModel {
  _StubListenerViewModel(this._initial);

  final ListenerState _initial;

  @override
  ListenerState build() => _initial;

  @override
  Future<void> leave({bool pauseAutoConnect = true}) async {}
}

Future<void> _pumpWith(WidgetTester tester, ListenerState state) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        listenerViewModelProvider.overrideWith(
          () => _StubListenerViewModel(state),
        ),
      ],
      child: const MaterialApp(home: ListenerPage()),
    ),
  );
}

void main() {
  testWidgets('renders the idle state', (tester) async {
    await _pumpWith(tester, const ListenerState());

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Silent'), findsOneWidget);
    expect(find.text('Leave session'), findsOneWidget);
    // Metrics unavailable render as em dashes.
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('renders the waiting-for-publisher state', (tester) async {
    await _pumpWith(
      tester,
      const ListenerState(
        connection: ListenerConnectionState.waitingForOffer,
        signaling: SignalingConnectionState.connected,
      ),
    );

    expect(find.text('Waiting for publisher'), findsOneWidget);
    expect(
      find.text('Waiting for the publisher to start streaming…'),
      findsOneWidget,
    );
  });

  testWidgets('renders the connected state with metrics', (tester) async {
    await _pumpWith(
      tester,
      const ListenerState(
        connection: ListenerConnectionState.connected,
        signaling: SignalingConnectionState.connected,
        stats: ListenerStats(
          iceState: 'Connected',
          hasRemoteAudio: true,
          rttMs: 48,
          jitterMs: 6,
          transport: RtcTransportMode.direct,
        ),
      ),
    );

    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('48 ms'), findsOneWidget);
    expect(find.text('6 ms'), findsOneWidget);
    expect(find.text('Direct'), findsOneWidget);
  });

  testWidgets('renders the reconnecting state', (tester) async {
    await _pumpWith(
      tester,
      const ListenerState(
        connection: ListenerConnectionState.reconnecting,
        signaling: SignalingConnectionState.reconnecting,
        stats: ListenerStats(iceState: 'Reconnecting'),
      ),
    );

    expect(find.text('Reconnecting'), findsWidgets);
    expect(
      find.text('Connection dropped — trying to reconnect…'),
      findsOneWidget,
    );
  });

  testWidgets('renders the ended state with a back action', (tester) async {
    await _pumpWith(
      tester,
      const ListenerState(
        connection: ListenerConnectionState.ended,
        signaling: SignalingConnectionState.ended,
      ),
    );

    expect(find.text('Session ended'), findsOneWidget);
    expect(find.text('The publisher ended this session.'), findsOneWidget);
    expect(find.text('Back to sessions'), findsOneWidget);
  });

  testWidgets('renders the failed state', (tester) async {
    await _pumpWith(
      tester,
      const ListenerState(
        connection: ListenerConnectionState.failed,
        stats: ListenerStats(iceState: 'Failed'),
      ),
    );

    expect(find.text('Connection failed'), findsOneWidget);
    expect(
      find.text("Couldn't connect to the stream. Try rejoining."),
      findsOneWidget,
    );
  });
}
