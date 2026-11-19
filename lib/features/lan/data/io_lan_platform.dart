import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/websocket/io_websocket_connector.dart';
import '../../../core/websocket/websocket_client.dart';
import '../domain/trusted_publisher.dart';
import 'bonsoir_lan_service_browser.dart';
import 'lan_discovery_service.dart';
import 'lan_pairing_api.dart';
import 'lan_platform_contract.dart';
import 'pinned_http_client.dart';

/// Selected by `lan_platform.dart` on Android/iOS; never compiled for the web.
LanPlatform createLanPlatform() => const IoLanPlatform();

class IoLanPlatform implements LanPlatform {
  const IoLanPlatform();

  static const _connectTimeout = Duration(seconds: 3);

  @override
  bool get isSupported => true;

  @override
  LanPost get pairingPost => _post;

  @override
  WebSocketConnector signalingConnector(TrustedPublisher publisher) =>
      (uri, headers) async {
        final client = createPinnedHttpClient(pin: publisher.pin);
        try {
          final socket = await WebSocket.connect(
            uri.toString(),
            headers: headers,
            customClient: client,
          ).timeout(signalingConnectTimeout);
          socket.pingInterval = signalingPingInterval;
          return IoWebSocketConnection(socket);
        } on HandshakeException catch (error) {
          throw LanTransportException(
            LanTransportFailure.tlsRejected,
            error.message,
          );
        } on SocketException catch (error) {
          throw LanTransportException(
            LanTransportFailure.unreachable,
            error.message,
          );
        } on TimeoutException {
          throw const LanTransportException(
            LanTransportFailure.unreachable,
            'timeout',
          );
        }
      };

  @override
  Future<bool> canReach(String endpoint, Duration timeout) async {
    final separator = endpoint.lastIndexOf(':');
    if (separator <= 0) return false;
    final host = endpoint
        .substring(0, separator)
        .replaceAll('[', '')
        .replaceAll(']', '');
    final port = int.tryParse(endpoint.substring(separator + 1));
    if (port == null) return false;
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } on Object {
      return false;
    }
  }

  @override
  LanServiceBrowser createBrowser() => BonsoirLanServiceBrowser();

  static Future<LanHttpResponse> _post(
    String endpoint,
    Map<String, Object?> body,
    PinPolicy policy,
  ) async {
    String? seenPin;
    final client = createPinnedHttpClient(
      pin: policy.pin,
      pinPrefix: policy.pinPrefix,
      onCertificate: (pin) => seenPin = pin,
    );
    try {
      final request = await client
          .postUrl(Uri.parse('https://$endpoint/lan/v1/pair'))
          .timeout(_connectTimeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final text = await response.transform(utf8.decoder).join();
      Map<String, dynamic> json = const {};
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) json = decoded;
      } on FormatException {
        // Error bodies are optional; the status code carries the meaning.
      }
      return LanHttpResponse(
        response.statusCode,
        json,
        certificatePin: seenPin,
      );
    } on HandshakeException catch (error) {
      throw LanTransportException(
        LanTransportFailure.tlsRejected,
        error.message,
      );
    } on SocketException catch (error) {
      throw LanTransportException(
        LanTransportFailure.unreachable,
        error.message,
      );
    } on TimeoutException {
      throw const LanTransportException(
        LanTransportFailure.unreachable,
        'timeout',
      );
    } finally {
      client.close(force: true);
    }
  }
}
