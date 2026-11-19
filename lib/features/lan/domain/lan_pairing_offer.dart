/// The LAN half of a version-2 pairing QR (dotnet_SonicRelay#75): everything
/// needed to pair with a SonicRelay Desktop offline.
class LanPairingOffer {
  const LanPairingOffer({
    required this.pairingId,
    required this.secret,
    required this.pin,
    required this.publisherDeviceId,
    required this.name,
    required this.endpoints,
  });

  /// Single-use pairing window id.
  final String pairingId;

  /// base64url 80-bit single-use secret.
  final String secret;

  /// base64url SHA-256 of the desktop certificate DER — the TLS pin.
  final String pin;
  final String publisherDeviceId;
  final String name;

  /// `host:port` endpoints, IPv6 bracketed, in the desktop's preference order.
  final List<String> endpoints;
}

/// A `host:port` endpoint: IPv4, bracketed IPv6 or a hostname, port 1–65535.
final lanEndpointPattern = RegExp(
  r'^(\[[0-9a-fA-F:.%]+\]|[0-9]{1,3}(\.[0-9]{1,3}){3}|[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*):([0-9]{1,5})$',
);

bool isLanEndpoint(String value) {
  final match = lanEndpointPattern.firstMatch(value.trim());
  if (match == null) return false;
  final port = int.parse(match.group(match.groupCount)!);
  return port >= 1 && port <= 65535;
}
