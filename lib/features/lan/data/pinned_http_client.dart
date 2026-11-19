import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// base64url (no padding) SHA-256 of a certificate's DER — the desktop's pin format.
String certificatePin(X509Certificate certificate) =>
    base64Url.encode(sha256.convert(certificate.der).bytes).replaceAll('=', '');

/// Whether [certificate] is the pinned desktop. With a full [pin] the whole
/// digest must match; with only [pinPrefix] (manual-code pairing) its first
/// bytes must. With neither, nothing is trusted.
bool pinMatches(
  X509Certificate certificate, {
  String? pin,
  List<int>? pinPrefix,
}) {
  if (pin != null) return certificatePin(certificate) == pin;
  if (pinPrefix == null || pinPrefix.isEmpty) return false;
  final digest = sha256.convert(certificate.der).bytes;
  for (var i = 0; i < pinPrefix.length; i++) {
    if (digest[i] != pinPrefix[i]) return false;
  }
  return true;
}

/// An [HttpClient] that trusts no CA and accepts exactly the pinned desktop
/// certificate (dotnet_SonicRelay#75). [onCertificate] observes the presented
/// certificate's pin so the caller can bind what it stores to what it saw.
HttpClient createPinnedHttpClient({
  String? pin,
  List<int>? pinPrefix,
  void Function(String pin)? onCertificate,
}) {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..connectionTimeout = const Duration(seconds: 3)
    ..badCertificateCallback = (certificate, host, port) {
      final ok = pinMatches(certificate, pin: pin, pinPrefix: pinPrefix);
      if (ok) onCertificate?.call(certificatePin(certificate));
      return ok;
    };
  return client;
}
