import 'dart:convert';

/// The typed LAN pairing code (dotnet_SonicRelay#75): 16 Crockford base32
/// characters, shown as `XXXX-XXXX-XXXX-XXXX`, encoding the first 40 bits of
/// the desktop's certificate pin followed by 40 bits of the pairing secret.
/// Byte-for-byte compatible with the desktop's `ManualPairingCode`.
class ManualPairingCode {
  const ManualPairingCode._();

  static const partLength = 5;
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static String encode(String pin, List<int> secret) {
    final pinBytes = decodeBase64Url(pin);
    final data = [...pinBytes.take(partLength), ...secret.take(partLength)];
    var value = BigInt.zero;
    for (final b in data) {
      value = (value << 8) | BigInt.from(b);
    }
    final chars = List.filled(16, '0');
    for (var i = 15; i >= 0; i--) {
      chars[i] = _alphabet[(value & BigInt.from(31)).toInt()];
      value >>= 5;
    }
    final text = chars.join();
    return '${text.substring(0, 4)}-${text.substring(4, 8)}-'
        '${text.substring(8, 12)}-${text.substring(12)}';
  }

  /// Case-insensitive; ignores spaces and dashes; maps O→0 and I/L→1.
  static ({List<int> pinPrefix, List<int> secret})? tryDecode(String? code) {
    final normalized = _normalizeChars(code);
    if (normalized == null) return null;
    var value = BigInt.zero;
    for (final c in normalized.split('')) {
      value = (value << 5) | BigInt.from(_alphabet.indexOf(c));
    }
    final data = List<int>.filled(partLength * 2, 0);
    for (var i = data.length - 1; i >= 0; i--) {
      data[i] = (value & BigInt.from(0xFF)).toInt();
      value >>= 8;
    }
    return (
      pinPrefix: data.sublist(0, partLength),
      secret: data.sublist(partLength),
    );
  }

  /// The canonical `XXXX-XXXX-XXXX-XXXX` form of a typed code, or null.
  static String? normalize(String? code) {
    final normalized = _normalizeChars(code);
    if (normalized == null) return null;
    return '${normalized.substring(0, 4)}-${normalized.substring(4, 8)}-'
        '${normalized.substring(8, 12)}-${normalized.substring(12)}';
  }

  static String? _normalizeChars(String? code) {
    if (code == null) return null;
    final buffer = StringBuffer();
    for (final raw in code.toUpperCase().split('')) {
      if (raw == ' ' || raw == '-') continue;
      final c = switch (raw) {
        'O' => '0',
        'I' || 'L' => '1',
        _ => raw,
      };
      if (!_alphabet.contains(c)) return null;
      buffer.write(c);
    }
    final result = buffer.toString();
    return result.length == 16 ? result : null;
  }
}

/// base64url without padding, as the desktop emits it.
List<int> decodeBase64Url(String value) =>
    base64Url.decode(value.padRight((value.length + 3) ~/ 4 * 4, '='));
