import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Non-identifying 6-hex hint announced in DNS-SD TXT records:
/// `sha256(deviceId)[0..6]`, identical to the desktop's `LanIdentity.ComputeHint`.
String lanHint(String deviceId) =>
    sha256.convert(utf8.encode(deviceId)).toString().substring(0, 6);

/// A SonicRelay Desktop this phone paired with over the LAN (dotnet_SonicRelay#75).
class TrustedPublisher {
  const TrustedPublisher({
    required this.publisherDeviceId,
    required this.name,
    required this.pin,
    required this.credential,
    required this.lastEndpoints,
    this.lastSeenAt,
  });

  final String publisherDeviceId;
  final String name;

  /// base64url SHA-256 of the desktop certificate; the only certificate trusted.
  final String pin;

  /// Per-device LAN credential issued at pairing. Never logged.
  final String credential;

  /// Most recently working endpoints first.
  final List<String> lastEndpoints;
  final DateTime? lastSeenAt;

  String get hint => lanHint(publisherDeviceId);

  TrustedPublisher copyWith({
    String? name,
    String? pin,
    String? credential,
    List<String>? lastEndpoints,
    DateTime? lastSeenAt,
  }) => TrustedPublisher(
    publisherDeviceId: publisherDeviceId,
    name: name ?? this.name,
    pin: pin ?? this.pin,
    credential: credential ?? this.credential,
    lastEndpoints: lastEndpoints ?? this.lastEndpoints,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
  );

  Map<String, Object?> toJson() => {
    'publisherDeviceId': publisherDeviceId,
    'name': name,
    'pin': pin,
    'credential': credential,
    'lastEndpoints': lastEndpoints,
    if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toUtc().toIso8601String(),
  };

  static TrustedPublisher fromJson(Map<String, dynamic> json) => TrustedPublisher(
    publisherDeviceId: json['publisherDeviceId'] as String,
    name: json['name'] as String,
    pin: json['pin'] as String,
    credential: json['credential'] as String,
    lastEndpoints: (json['lastEndpoints'] as List).cast<String>(),
    lastSeenAt: json['lastSeenAt'] == null
        ? null
        : DateTime.parse(json['lastSeenAt'] as String),
  );
}
