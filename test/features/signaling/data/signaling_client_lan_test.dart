import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/diagnostics/file_diagnostic_log.dart';
import 'package:sonic_relay/core/websocket/websocket_client.dart';
import 'package:sonic_relay/features/device_identity/data/device_identity_session.dart';
import 'package:sonic_relay/features/lan/data/lan_platform_contract.dart';
import 'package:sonic_relay/features/lan/domain/lan_failure.dart';
import 'package:sonic_relay/features/lan/domain/lan_session_target.dart';
import 'package:sonic_relay/features/lan/domain/trusted_publisher.dart';
import 'package:sonic_relay/features/sessions/domain/stream_session.dart';
import 'package:sonic_relay/features/signaling/data/signaling_client.dart';

class CodedConnection implements WebSocketConnection, WebSocketCloseInfo {
  final _controller = StreamController<dynamic>.broadcast();
  final sent = <String>[];

  @override
  int? closeCode;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(String data) => sent.add(data);

  @override
  Future<void> close() => _controller.close();

  Future<void> serverClose(int code) {
    closeCode = code;
    return _controller.close();
  }
}

/// Fails the test if the LAN path ever touches the cloud identity.
class ForbiddenDeviceIdentitySession implements DeviceIdentitySession {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('LAN signaling must not use the cloud device identity');
}

Timer _instant(Duration delay, void Function() callback) =>
    Timer(Duration.zero, callback);

void main() {
  const publisher = TrustedPublisher(
    publisherDeviceId: '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
    name: 'DESKTOP-01',
    pin: 'pin',
    credential: 'lan-credential',
    lastEndpoints: ['192.168.1.20:47321'],
  );
  const viewerId = '11111111-1111-1111-1111-111111111111';

  late List<CodedConnection> connections;
  late List<Map<String, String>> headersSeen;
  late List<Uri> urisSeen;
  late SignalingClient client;

  StreamSession lanSession() => StreamSession(
    sessionId: 'session-lan',
    signalingUrl: Uri.parse('wss://192.168.1.20:47321/lan/v1/signaling'),
    lan: LanSessionTarget(
      publisher: publisher,
      viewerDeviceId: viewerId,
      connector: (uri, headers) async {
        urisSeen.add(uri);
        headersSeen.add(headers);
        final connection = CodedConnection();
        connections.add(connection);
        return connection;
      },
    ),
  );

  setUp(() {
    connections = [];
    headersSeen = [];
    urisSeen = [];
    final webSocketClient = WebSocketClient(
      connector: (_, _) async =>
          throw StateError('the cloud connector must not be used'),
      diagnosticLog: FileDiagnosticLog(
        Directory.systemTemp.createTempSync('sr_lan_sig_').path,
      ),
      scheduleTimer: _instant,
    );
    client = SignalingClient(
      webSocketClient: webSocketClient,
      deviceIdentitySession: ForbiddenDeviceIdentitySession(),
      diagnosticLog: FileDiagnosticLog(
        Directory.systemTemp.createTempSync('sr_lan_sig_').path,
      ),
    );
    addTearDown(webSocketClient.dispose);
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test(
    'connects with the LAN credential and never the cloud identity',
    () async {
      await client.connect(session: lanSession());

      expect(client.isLanSession, isTrue);
      expect(headersSeen.single, {
        'Authorization': 'SonicRelay-Lan lan-credential',
        'X-SonicRelay-Device': viewerId,
      });
      expect(urisSeen.single.path, '/lan/v1/signaling');
    },
  );

  for (final (code, failure) in [
    (4401, LanFailureCode.unauthorized),
    (4403, LanFailureCode.revoked),
    (4409, LanFailureCode.sessionUnavailable),
  ]) {
    test(
      'close $code is terminal and reported as ${failure.diagnosticCode}',
      () async {
        final failures = <LanFailure>[];
        client.lanFailures.listen(failures.add);
        await client.connect(session: lanSession());

        await connections.single.serverClose(code);
        await settle();

        expect(connections, hasLength(1));
        expect(failures.single.code, failure);
      },
    );
  }

  test(
    'a certificate rejected after the probe is reported as pin mismatch',
    () async {
      final failures = <LanFailure>[];
      client.lanFailures.listen(failures.add);
      final session = lanSession();

      await client.connect(
        session: StreamSession(
          sessionId: session.sessionId,
          signalingUrl: session.signalingUrl,
          lan: LanSessionTarget(
            publisher: publisher,
            viewerDeviceId: viewerId,
            connector: (_, _) async => throw const LanTransportException(
              LanTransportFailure.tlsRejected,
              'certificate changed',
            ),
          ),
        ),
      );
      await settle();

      expect(failures.single.code, LanFailureCode.pinMismatch);
    },
  );

  test('a dropped LAN socket reconnects on the same transport', () async {
    await client.connect(session: lanSession());

    await connections.single.serverClose(1006);
    await settle();

    expect(connections, hasLength(2));
    expect(client.isLanSession, isTrue);
  });

  test('a cloud session after a LAN one is no longer LAN', () async {
    await client.connect(session: lanSession());
    await client.leave();

    expect(client.isLanSession, isFalse);
  });
}
