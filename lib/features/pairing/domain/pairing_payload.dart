import 'dart:convert';

import '../../lan/domain/lan_pairing_offer.dart';
import 'pairing_challenge_payload.dart';

/// A scanned pairing QR (dotnet_SonicRelay#75). Version 2 can carry a cloud
/// block, a LAN block, or both; the bare two-key cloud payload of older
/// desktops still parses as cloud-only.
class PairingPayload {
  const PairingPayload({this.cloud, this.lan});

  final PairingChallengePayload? cloud;
  final LanPairingOffer? lan;

  static PairingPayload parse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Invalid pairing payload.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid pairing payload.');
    }

    if (!decoded.containsKey('v')) {
      return PairingPayload(cloud: PairingChallengePayload.parse(raw));
    }
    if (decoded['v'] != 2) {
      throw const FormatException('Unsupported pairing payload version.');
    }

    final cloudJson = decoded['cloud'];
    final lanJson = decoded['lan'];
    if (cloudJson == null && lanJson == null) {
      throw const FormatException('The pairing payload has no cloud or LAN block.');
    }

    return PairingPayload(
      cloud: cloudJson == null
          ? null
          : PairingChallengePayload.parse(jsonEncode(cloudJson)),
      lan: lanJson == null ? null : _parseLan(lanJson),
    );
  }

  static LanPairingOffer _parseLan(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid LAN pairing block.');
    }
    String text(String key, {int min = 1}) {
      final value = json[key];
      if (value is! String || value.trim().length < min) {
        throw FormatException('Invalid LAN pairing field "$key".');
      }
      return value.trim();
    }

    final endpoints = json['ep'];
    if (endpoints is! List ||
        endpoints.isEmpty ||
        endpoints.any((e) => e is! String || !isLanEndpoint(e))) {
      throw const FormatException('Invalid LAN pairing endpoints.');
    }

    return LanPairingOffer(
      pairingId: text('pid', min: 36),
      secret: text('sec', min: 8),
      pin: text('pin', min: 43),
      publisherDeviceId: text('did', min: 36),
      name: text('name'),
      endpoints: endpoints.cast<String>().map((e) => e.trim()).toList(),
    );
  }
}
