import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/diagnostics/diagnostic_log.dart';
import 'package:sonic_relay/core/diagnostics/file_diagnostic_log.dart';
import 'package:sonic_relay/core/websocket/websocket_client.dart';

class CodedConnection implements WebSocketConnection, WebSocketCloseInfo {
  final _controller = StreamController<dynamic>.broadcast();

  @override
  int? closeCode;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(String data) {}

  @override
  Future<void> close() => _controller.close();

  Future<void> serverClose(int code) {
    closeCode = code;
    return _controller.close();
  }
}

DiagnosticLog _log() => FileDiagnosticLog(
  Directory.systemTemp.createTempSync('sonicrelay_lan_ws_').path,
);

Timer _instant(Duration delay, void Function() callback) =>
    Timer(Duration.zero, callback);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('a per-connect connector replaces the default one', () async {
    var defaultCalls = 0;
    var lanCalls = 0;
    final client = WebSocketClient(
      diagnosticLog: _log(),
      connector: (_, _) async {
        defaultCalls++;
        return CodedConnection();
      },
      scheduleTimer: _instant,
    );
    addTearDown(client.dispose);

    await client.connect(
      Uri.parse('wss://192.168.1.20:47321/lan/v1/signaling'),
      connector: (_, _) async {
        lanCalls++;
        return CodedConnection();
      },
    );

    expect(lanCalls, 1);
    expect(defaultCalls, 0);
  });

  test('a terminal close code stops reconnecting and is reported', () async {
    final connections = <CodedConnection>[];
    final client = WebSocketClient(
      diagnosticLog: _log(),
      connector: (_, _) async => CodedConnection(),
      scheduleTimer: _instant,
    );
    addTearDown(client.dispose);
    final terminations = <WebSocketTermination>[];
    client.terminations.listen(terminations.add);

    await client.connect(
      Uri.parse('wss://h/lan'),
      connector: (_, _) async {
        final connection = CodedConnection();
        connections.add(connection);
        return connection;
      },
      shouldReconnectOnClose: (code) => code != 4403,
    );
    await connections.single.serverClose(4403);
    await _settle();

    expect(connections, hasLength(1));
    expect(terminations.single.closeCode, 4403);
  });

  test('a non-terminal close reconnects as before', () async {
    final connections = <CodedConnection>[];
    final client = WebSocketClient(
      diagnosticLog: _log(),
      connector: (_, _) async => CodedConnection(),
      scheduleTimer: _instant,
    );
    addTearDown(client.dispose);

    await client.connect(
      Uri.parse('wss://h/lan'),
      connector: (_, _) async {
        final connection = CodedConnection();
        connections.add(connection);
        return connection;
      },
      shouldReconnectOnClose: (code) => code != 4403,
    );
    await connections.single.serverClose(1001);
    await _settle();

    expect(connections, hasLength(2));
  });

  test('maxAttempts bounds failed connects and reports exhaustion', () async {
    var attempts = 0;
    final client = WebSocketClient(
      diagnosticLog: _log(),
      connector: (_, _) async => CodedConnection(),
      scheduleTimer: _instant,
    );
    addTearDown(client.dispose);
    final terminations = <WebSocketTermination>[];
    client.terminations.listen(terminations.add);

    await client.connect(
      Uri.parse('wss://h/lan'),
      connector: (_, _) async {
        attempts++;
        throw StateError('unreachable');
      },
      maxAttempts: 5,
    );
    await _settle();

    expect(attempts, 5);
    expect(terminations.single.exhausted, isTrue);
  });

  test('without the new options the cloud behaviour is unchanged', () async {
    var attempts = 0;
    final client = WebSocketClient(
      diagnosticLog: _log(),
      connector: (_, _) async {
        attempts++;
        if (attempts < 8) throw StateError('down');
        return CodedConnection();
      },
      scheduleTimer: _instant,
    );
    addTearDown(client.dispose);

    await client.connect(Uri.parse('wss://cloud/ws'));
    await _settle();

    expect(attempts, 8);
  });
}
