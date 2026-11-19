import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/websocket/websocket_client.dart';
import 'package:sonic_relay/features/lan/data/lan_discovery_service.dart';
import 'package:sonic_relay/features/lan/data/lan_pairing_api.dart';
import 'package:sonic_relay/features/lan/data/lan_platform_contract.dart';
import 'package:sonic_relay/features/lan/data/lan_session_connector.dart';
import 'package:sonic_relay/features/lan/data/trusted_publisher_store.dart';
import 'package:sonic_relay/features/lan/domain/lan_failure.dart';
import 'package:sonic_relay/features/lan/domain/trusted_publisher.dart';

class ProbeConnection implements WebSocketConnection, WebSocketCloseInfo {
  ProbeConnection({this.firstMessage, this.closeWith});

  final String? firstMessage;
  final int? closeWith;
  final _controller = StreamController<dynamic>();
  bool closed = false;

  @override
  int? closeCode;

  @override
  Stream<dynamic> get stream {
    scheduleMicrotask(() {
      if (firstMessage != null) _controller.add(firstMessage);
      if (closeWith != null) {
        closeCode = closeWith;
        _controller.close();
      }
    });
    return _controller.stream;
  }

  @override
  void add(String data) {}

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
  }
}

class FakePlatform implements LanPlatform {
  FakePlatform(this.behaviour);

  /// endpoint -> what connecting to it does.
  final Map<String, Object> behaviour;
  final attempted = <String>[];

  @override
  bool get isSupported => true;

  @override
  WebSocketConnector signalingConnector(
    TrustedPublisher publisher,
  ) => (uri, headers) async {
    final endpoint =
        '${uri.host.contains(':') ? '[${uri.host}]' : uri.host}:${uri.port}';
    attempted.add(endpoint);
    final outcome =
        behaviour[endpoint] ??
        const LanTransportException(LanTransportFailure.unreachable);
    if (outcome is Exception) throw outcome;
    return outcome as ProbeConnection;
  };

  @override
  LanPost get pairingPost => throw UnimplementedError();

  @override
  Future<bool> canReach(String endpoint, Duration timeout) async => false;

  @override
  LanServiceBrowser createBrowser() => throw UnimplementedError();
}

void main() {
  const storage = FlutterSecureStorage();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  const publisher = TrustedPublisher(
    publisherDeviceId: '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
    name: 'DESKTOP-01',
    pin: 'pin',
    credential: 'cred',
    lastEndpoints: ['192.168.1.20:47321', '192.168.2.20:47321'],
  );

  String joined(String sessionId) => jsonEncode({
    'type': 'session.joined',
    'sessionId': sessionId,
    'payload': {'participantId': 'v', 'role': 'viewer'},
  });

  Future<LanFailureCode> failureOf(Future<Object?> future) async {
    try {
      await future;
    } on LanFailure catch (failure) {
      return failure.code;
    }
    fail('expected a LanFailure');
  }

  test('auto uses lan when reachable and learns the session id', () async {
    final probe = ProbeConnection(firstMessage: joined('session-1'));
    const store = TrustedPublisherStore(storage);
    await store.save(publisher);
    final connector = LanSessionConnector(
      platform: FakePlatform({'192.168.2.20:47321': probe}),
      store: store,
    );

    final session = await connector.connect(publisher);

    expect(session.sessionId, 'session-1');
    expect(session.isLan, isTrue);
    expect(
      session.signalingUrl.toString(),
      'wss://192.168.2.20:47321/lan/v1/signaling',
    );
    expect(session.lan!.headers['X-SonicRelay-Device'], isNotEmpty);
    expect(probe.closed, isTrue);
    expect(
      (await store.list()).single.lastEndpoints.first,
      '192.168.2.20:47321',
    );
  });

  test('discovered endpoints are tried before remembered ones', () async {
    final platform = FakePlatform({
      '10.0.0.9:47321': ProbeConnection(firstMessage: joined('s')),
    });
    final connector = LanSessionConnector(
      platform: platform,
      store: const TrustedPublisherStore(storage),
    );

    await connector.connect(publisher, discovered: ['10.0.0.9:47321']);

    expect(platform.attempted, ['10.0.0.9:47321']);
  });

  test('every endpoint unreachable is lan.unreachable', () async {
    final connector = LanSessionConnector(
      platform: FakePlatform({}),
      store: const TrustedPublisherStore(storage),
    );

    expect(
      await failureOf(connector.connect(publisher)),
      LanFailureCode.unreachable,
    );
  });

  test(
    'isolation suspected when mDNS sees the desktop but TCP fails',
    () async {
      final connector = LanSessionConnector(
        platform: FakePlatform({}),
        store: const TrustedPublisherStore(storage),
      );

      expect(
        await failureOf(
          connector.connect(publisher, discovered: ['192.168.1.20:47321']),
        ),
        LanFailureCode.isolationSuspected,
      );
    },
  );

  test('a different certificate stops immediately as pin mismatch', () async {
    final platform = FakePlatform({
      '192.168.1.20:47321': const LanTransportException(
        LanTransportFailure.tlsRejected,
      ),
    });
    final connector = LanSessionConnector(
      platform: platform,
      store: const TrustedPublisherStore(storage),
    );

    expect(
      await failureOf(connector.connect(publisher)),
      LanFailureCode.pinMismatch,
    );
    expect(platform.attempted, hasLength(1));
  });

  for (final (code, failure) in [
    (4401, LanFailureCode.unauthorized),
    (4403, LanFailureCode.revoked),
    (4409, LanFailureCode.sessionUnavailable),
  ]) {
    test('close $code during the probe is ${failure.diagnosticCode}', () async {
      final connector = LanSessionConnector(
        platform: FakePlatform({
          '192.168.1.20:47321': ProbeConnection(closeWith: code),
        }),
        store: const TrustedPublisherStore(storage),
      );

      expect(await failureOf(connector.connect(publisher)), failure);
    });
  }

  test('a desktop that never answers counts as unreachable', () async {
    final connector = LanSessionConnector(
      platform: FakePlatform({'192.168.1.20:47321': ProbeConnection()}),
      store: const TrustedPublisherStore(storage),
      probeTimeout: const Duration(milliseconds: 50),
    );

    expect(
      await failureOf(connector.connect(publisher)),
      LanFailureCode.unreachable,
    );
  });
}
