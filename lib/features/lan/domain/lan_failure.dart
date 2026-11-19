/// Why a LAN pairing or connection attempt failed (dotnet_SonicRelay#75). Each
/// maps to a stable diagnostic code shared with the desktop's troubleshooting
/// table (`docs/lan-mode.md`).
enum LanFailureCode {
  unreachable('lan.unreachable'),
  isolationSuspected('lan.isolation_suspected'),
  pinMismatch('lan.pin_mismatch'),
  pairingInvalid('lan.pairing_invalid'),
  pairingExpired('lan.pairing_expired'),
  rateLimited('lan.rate_limited'),
  revoked('lan.revoked'),
  unauthorized('lan.unauthorized'),
  sessionUnavailable('lan.session_unavailable'),
  needsPairing('lan.needs_pairing'),
  noDirectRoute('ice.no_direct_route');

  const LanFailureCode(this.diagnosticCode);

  final String diagnosticCode;
}

class LanFailure implements Exception {
  const LanFailure(this.code, [this.detail]);

  final LanFailureCode code;
  final String? detail;

  /// A short, actionable explanation for the user.
  String get message => switch (code) {
    LanFailureCode.unreachable =>
      'The desktop could not be reached on the local network. Check that both devices have a route to each other and that the desktop firewall allows SonicRelay.',
    LanFailureCode.isolationSuspected =>
      'The desktop is visible on the network but refuses connections. The Wi-Fi probably isolates clients from each other.',
    LanFailureCode.pinMismatch =>
      'A different computer answered at this address. Pair again with the desktop you trust.',
    LanFailureCode.pairingInvalid =>
      'The pairing code is wrong or was already used. Create a new local pairing code on the desktop.',
    LanFailureCode.pairingExpired =>
      'The pairing code expired. Create a new local pairing code on the desktop.',
    LanFailureCode.rateLimited =>
      'Too many attempts. Wait a minute before trying again.',
    LanFailureCode.revoked =>
      'This phone was removed on the desktop. Pair again to listen.',
    LanFailureCode.unauthorized =>
      'The desktop no longer recognizes this phone. Pair again.',
    LanFailureCode.sessionUnavailable =>
      'The desktop has no live session, or it is full.',
    LanFailureCode.needsPairing =>
      'Pair with a desktop on this network first (QR or local pairing code).',
    LanFailureCode.noDirectRoute =>
      'Signaling worked but audio cannot flow directly between the devices: a firewall, network ACL or client isolation blocks UDP.',
  };

  @override
  String toString() => '${code.diagnosticCode}${detail == null ? '' : ': $detail'}';
}
