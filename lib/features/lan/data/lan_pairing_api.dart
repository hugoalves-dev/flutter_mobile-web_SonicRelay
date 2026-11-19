import 'dart:async';

import '../../../core/diagnostics/sonic_log.dart';
import '../domain/lan_failure.dart';
import '../domain/lan_pairing_offer.dart';
import '../domain/manual_pairing_code.dart';
import '../domain/trusted_publisher.dart';
import 'lan_platform_contract.dart';

/// Which certificate a request may trust: the full [pin] (QR) or only a
/// [pinPrefix] (typed code during the 120 s pairing window).
class PinPolicy {
  const PinPolicy({this.pin, this.pinPrefix});

  final String? pin;
  final List<int>? pinPrefix;
}

class LanHttpResponse {
  const LanHttpResponse(this.statusCode, this.body, {this.certificatePin});

  final int statusCode;
  final Map<String, dynamic> body;

  /// The pin of the certificate the server actually presented, when known.
  final String? certificatePin;
}

typedef LanPost =
    Future<LanHttpResponse> Function(
      String endpoint,
      Map<String, Object?> body,
      PinPolicy pin,
    );

/// Offline pairing with a SonicRelay Desktop over pinned TLS (dotnet_SonicRelay#75).
class LanPairingApi {
  LanPairingApi({required LanPost post}) : _post = post;

  final LanPost _post;

  /// Tries [endpoints] in order. A TLS rejection is a pin mismatch and stops
  /// immediately — another address would only reach the same impostor.
  Future<TrustedPublisher> pair({
    required List<String> endpoints,
    LanPairingOffer? offer,
    String? manualCode,
    required String viewerDeviceId,
    required String viewerName,
    required String platform,
  }) async {
    final PinPolicy policy;
    final Map<String, Object?> body;
    List<int>? typedPrefix;
    if (offer != null) {
      policy = PinPolicy(pin: offer.pin);
      body = {'pid': offer.pairingId, 'sec': offer.secret};
    } else {
      final decoded = ManualPairingCode.tryDecode(manualCode);
      if (decoded == null) {
        throw const LanFailure(LanFailureCode.pairingInvalid);
      }
      typedPrefix = decoded.pinPrefix;
      policy = PinPolicy(pinPrefix: typedPrefix);
      body = {'code': ManualPairingCode.normalize(manualCode)};
    }
    body.addAll({
      'viewerDeviceId': viewerDeviceId,
      'viewerName': viewerName,
      'platform': platform,
    });

    for (final endpoint in endpoints) {
      final LanHttpResponse response;
      try {
        response = await _post(endpoint, body, policy);
      } on LanTransportException catch (error) {
        if (error.failure == LanTransportFailure.tlsRejected) {
          throw LanFailure(LanFailureCode.pinMismatch, error.detail);
        }
        sonicLog(
          'LAN',
          'pairing endpoint unreachable: $endpoint (${error.detail})',
        );
        continue;
      } on TimeoutException {
        sonicLog('LAN', 'pairing endpoint timed out: $endpoint');
        continue;
      }
      return _toPublisher(response, endpoint, endpoints, offer, typedPrefix);
    }
    throw const LanFailure(LanFailureCode.unreachable);
  }

  TrustedPublisher _toPublisher(
    LanHttpResponse response,
    String endpoint,
    List<String> endpoints,
    LanPairingOffer? offer,
    List<int>? typedPrefix,
  ) {
    switch (response.statusCode) {
      case 200:
        break;
      case 410:
        throw const LanFailure(LanFailureCode.pairingExpired);
      case 429:
        throw const LanFailure(LanFailureCode.rateLimited);
      default:
        throw const LanFailure(LanFailureCode.pairingInvalid);
    }

    final body = response.body;
    final pin = body['pin'];
    final credential = body['credential'];
    final deviceId = body['publisherDeviceId'];
    if (pin is! String || credential is! String || deviceId is! String) {
      throw const LanFailure(
        LanFailureCode.pairingInvalid,
        'malformed response',
      );
    }
    // The pin we store must be the certificate we actually saw, and match
    // what the QR or the typed code promised.
    if (response.certificatePin != null && response.certificatePin != pin) {
      throw const LanFailure(LanFailureCode.pinMismatch);
    }
    if (offer != null && offer.pin != pin) {
      throw const LanFailure(LanFailureCode.pinMismatch);
    }
    if (typedPrefix != null &&
        !_startsWith(decodeBase64UrlSafe(pin), typedPrefix)) {
      throw const LanFailure(LanFailureCode.pinMismatch);
    }

    return TrustedPublisher(
      publisherDeviceId: deviceId,
      name:
          (body['publisherName'] as String?) ??
          offer?.name ??
          'SonicRelay Desktop',
      pin: pin,
      credential: credential,
      lastEndpoints: [endpoint, ...endpoints.where((e) => e != endpoint)],
      lastSeenAt: DateTime.now().toUtc(),
    );
  }

  static bool _startsWith(List<int>? bytes, List<int> prefix) {
    if (bytes == null || bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }
}

/// base64url decode that returns null instead of throwing on garbage.
List<int>? decodeBase64UrlSafe(String value) {
  try {
    return decodeBase64Url(value);
  } on FormatException {
    return null;
  }
}
