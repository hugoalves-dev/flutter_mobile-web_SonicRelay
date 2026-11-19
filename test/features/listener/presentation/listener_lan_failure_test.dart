import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/core/diagnostics/file_diagnostic_log.dart';
import 'package:sonic_relay/core/websocket/websocket_client.dart';
import 'package:sonic_relay/features/device_identity/data/device_identity_session.dart';
import 'package:sonic_relay/features/lan/domain/lan_session_target.dart';
import 'package:sonic_relay/features/lan/domain/trusted_publisher.dart';
import 'package:sonic_relay/features/listener/presentation/listener_view_model.dart';
import 'package:sonic_relay/features/sessions/domain/stream_session.dart';
import 'package:sonic_relay/features/signaling/data/signaling_client.dart';

class CodedConnection implements WebSocketConnection, WebSocketCloseInfo {
  final _controller = StreamController<dynamic>.broadcast();

  @override
  int? closeCode;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(String data) {}

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }

  Future<void> serverClose(int code) {
    closeCode = code;
    return _controller.close();
  }
}

class TokenIdentity implements DeviceIdentitySession {
  @override
  Future<String> accessToken({bool forceRefresh = false}) async => 'token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a new session clears the previous LAN failure', () async {
    final connections = <CodedConnection>[];
    Future<WebSocketConnection> connect(Uri _, Map<String, String> _) async {
      final connection = CodedConnection();
      connections.add(connection);
      return connection;
    }

    final log = FileDiagnosticLog(
      Directory.systemTemp.createTempSync('sr_lan_fail_').path,
    );
    final webSocketClient = WebSocketClient(
      connector: connect,
      diagnosticLog: log,
      scheduleTimer: (delay, callback) => Timer(Duration.zero, callback),
    );
    final signaling = SignalingClient(
      webSocketClient: webSocketClient,
      deviceIdentitySession: TokenIdentity(),
      diagnosticLog: log,
    );
    final container = ProviderContainer(
      overrides: [signalingClientProvider.overrideWithValue(signaling)],
    );
    addTearDown(container.dispose);
    final vm = container.read(listenerViewModelProvider.notifier);

    await vm.connect(
      session: StreamSession(
        sessionId: 'lan-1',
        signalingUrl: Uri.parse('wss://192.168.1.20:47321/lan/v1/signaling'),
        lan: LanSessionTarget(
          publisher: const TrustedPublisher(
            publisherDeviceId: '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
            name: 'DESKTOP-01',
            pin: 'pin',
            credential: 'cred',
            lastEndpoints: ['192.168.1.20:47321'],
          ),
          viewerDeviceId: 'viewer',
          connector: connect,
        ),
      ),
    );
    await connections.single.serverClose(LanCloseCodes.revoked);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      container.read(listenerViewModelProvider).lanFailure,
      contains('lan.revoked'),
    );

    await vm.connect(
      session: StreamSession(
        sessionId: 'cloud-1',
        signalingUrl: Uri.parse('wss://cloud/ws/signaling'),
      ),
    );

    expect(container.read(listenerViewModelProvider).lanFailure, isNull);
    expect(container.read(listenerViewModelProvider).isLan, isFalse);
  });
}
