/// Strips secrets, SDP/ICE payloads and emails out of log lines before they
/// reach memory or disk. Mirrors windows_SonicRelay's DiagnosticRedactor rules.
///
/// Note: Dart's RegExp (ECMAScript-flavored) has no inline `(?i)` case flag —
/// unlike .NET's regex engine that windows_SonicRelay's redactor uses. Each
/// case-insensitive pattern here uses the `caseSensitive: false` constructor
/// parameter instead.
class DiagnosticRedactor {
  const DiagnosticRedactor._();

  static const _redacted = '[REDACTED]';

  // Matches both the plain `Bearer <token>` scheme and this app's
  // `DeviceBearer <token>` scheme (device-identity access tokens). `\b`
  // alone would not match "Bearer" glued onto "Device" since there is no
  // word boundary between two letters, so the optional prefix is spelled
  // out explicitly instead of relying on the boundary to separate them.
  static final _bearerToken = RegExp(
    r'\b(?:device)?bearer\s+[^\s,;]+',
    caseSensitive: false,
  );
  static final _jwt = RegExp(
    r'\bey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
  );
  static final _email = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final _sdpPayload = RegExp(r'\bsdp\s*=\s*.*', caseSensitive: false);
  static final _iceCandidate = RegExp(
    r'candidate:[^\r\n]+',
    caseSensitive: false,
  );
  static final _sensitiveAssignment = RegExp(
    r'\b(password|access[_-]?token|refresh[_-]?token|token|code|credential|sec)\s*=\s*[^\s&]+',
    caseSensitive: false,
  );
  static final _sensitiveKey = RegExp(
    r'^(password|access[_-]?token|refresh[_-]?token|token|authorization|credential|sec|sdp|ice[_-]?candidate)$',
    caseSensitive: false,
  );

  // LAN pairing (dotnet_SonicRelay#75): the device credential header, JSON
  // secrets and typed local pairing codes.
  static final _lanAuthorization = RegExp(
    r'\bSonicRelay-Lan\s+[^\s,;]+',
    caseSensitive: false,
  );
  static final _jsonSecret = RegExp(
    r'"(credential|sec|code)"\s*:\s*"[^"]*"',
    caseSensitive: false,
  );
  static final _manualPairingCode = RegExp(
    r'\b[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}\b',
    caseSensitive: false,
  );

  static String redact(String? value) {
    if (value == null || value.isEmpty) return value ?? '';
    var result = value.replaceAllMapped(
      _sensitiveAssignment,
      (match) => '${match[1]}=$_redacted',
    );
    result = result.replaceAll(_bearerToken, 'Bearer $_redacted');
    result = result.replaceAll(_lanAuthorization, 'SonicRelay-Lan $_redacted');
    result = result.replaceAllMapped(
      _jsonSecret,
      (match) => '"${match[1]}":"$_redacted"',
    );
    result = result.replaceAll(_manualPairingCode, _redacted);
    result = result.replaceAll(_jwt, _redacted);
    result = result.replaceAll(_email, _redacted);
    result = result.replaceAll(_sdpPayload, 'sdp=$_redacted');
    result = result.replaceAll(_iceCandidate, _redacted);
    return result;
  }

  static bool isSensitiveKey(String key) => _sensitiveKey.hasMatch(key);
}
