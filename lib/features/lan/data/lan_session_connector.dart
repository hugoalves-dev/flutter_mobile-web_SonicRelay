import 'dart:async';
import 'dart:convert';

import '../../../core/diagnostics/sonic_log.dart';
import '../../../core/websocket/websocket_client.dart';
import '../../sessions/domain/stream_session.dart';
import '../domain/lan_failure.dart';
import '../domain/lan_session_target.dart';
import '../domain/trusted_publisher.dart';
import 'lan_platform_contract.dart';
import 'trusted_publisher_store.dart';

/// Finds a working LAN path to a paired desktop before a session is
/// committed to it (dotnet_SonicRelay#75). Each endpoint — mDNS first, then
/// remembered ones — is probed with the real handshake: pinned TLS, the LAN
/// credential, and the hub's first `session.joined`, which also carries the
/// session id. The probe socket is closed; the listener then opens its own.
class LanSessionConnector {
  LanSessionConnector({
    required LanPlatform platform,
    required TrustedPublisherStore store,
    this.probeTimeout = const Duration(seconds: 5),
  }) : _platform = platform,
       _store = store;

  final LanPlatform _platform;
  final TrustedPublisherStore _store;
  final Duration probeTimeout;

  Future<StreamSession> connect(
    TrustedPublisher publisher, {
    List<String> discovered = const [],
  }) async {
    final endpoints = <String>{
      ...discovered,
      ...publisher.lastEndpoints,
    }.toList();
    if (endpoints.isEmpty) throw const LanFailure(LanFailureCode.unreachable);

    final target = LanSessionTarget(
      publisher: publisher,
      viewerDeviceId: await _store.viewerDeviceId(),
      connector: _platform.signalingConnector(publisher),
    );

    for (final endpoint in endpoints) {
      final uri = Uri.parse('wss://$endpoint/lan/v1/signaling');
      final String? sessionId;
      try {
        sessionId = await _probe(target, uri);
      } on LanTransportException catch (error) {
        if (error.failure == LanTransportFailure.tlsRejected) {
          throw LanFailure(LanFailureCode.pinMismatch, error.detail);
        }
        sonicLog('LAN', 'endpoint unreachable: $endpoint');
        continue;
      }
      if (sessionId == null) continue;
      await _store.updateEndpoints(publisher.publisherDeviceId, [endpoint]);
      return StreamSession(
        sessionId: sessionId,
        signalingUrl: uri,
        lan: target,
      );
    }

    // Seen on the link but no TCP/TLS: the classic client-isolation symptom.
    throw LanFailure(
      discovered.isNotEmpty
          ? LanFailureCode.isolationSuspected
          : LanFailureCode.unreachable,
    );
  }

  /// The session id announced by the hub, null when the endpoint gave
  /// nothing usable, or a [LanFailure] for a definitive rejection.
  Future<String?> _probe(LanSessionTarget target, Uri uri) async {
    final WebSocketConnection connection;
    try {
      connection = await target
          .connector(uri, target.headers)
          .timeout(probeTimeout);
    } on TimeoutException {
      return null;
    }

    final first = Completer<String?>();
    final subscription = connection.stream.listen(
      (data) {
        if (first.isCompleted || data is! String) return;
        try {
          final json = jsonDecode(data);
          if (json is Map<String, dynamic> &&
              json['type'] == 'session.joined' &&
              json['sessionId'] is String) {
            first.complete(json['sessionId'] as String);
          }
        } on FormatException {
          // Not an envelope; keep waiting.
        }
      },
      onDone: () {
        if (!first.isCompleted) first.complete(null);
      },
      onError: (Object _) {
        if (!first.isCompleted) first.complete(null);
      },
    );

    try {
      final sessionId = await first.future.timeout(
        probeTimeout,
        onTimeout: () => null,
      );
      if (sessionId != null) return sessionId;
      final closeCode = connection is WebSocketCloseInfo
          ? (connection as WebSocketCloseInfo).closeCode
          : null;
      switch (closeCode) {
        case LanCloseCodes.unauthorized:
          throw const LanFailure(LanFailureCode.unauthorized);
        case LanCloseCodes.revoked:
          throw const LanFailure(LanFailureCode.revoked);
        case LanCloseCodes.unavailable:
        case LanCloseCodes.sessionEnded:
          throw const LanFailure(LanFailureCode.sessionUnavailable);
      }
      return null;
    } finally {
      await subscription.cancel();
      await connection.close();
    }
  }
}
