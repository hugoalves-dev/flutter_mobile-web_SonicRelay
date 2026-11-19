import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/features/lan/data/pinned_http_client.dart';

class FakeCertificate implements X509Certificate {
  FakeCertificate(this.der);

  @override
  final Uint8List der;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // SHA-256([1,2,3]) as base64url — same vector as the desktop's LanIdentityStoreTests.
  const pin = 'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E';
  final cert = FakeCertificate(Uint8List.fromList([1, 2, 3]));
  final other = FakeCertificate(Uint8List.fromList([9, 9, 9]));

  test('accepts matching pin', () {
    expect(certificatePin(cert), pin);
    expect(pinMatches(cert, pin: pin), isTrue);
  });

  test('rejects other certificate', () {
    expect(pinMatches(other, pin: pin), isFalse);
  });

  test('prefix accepted only when given a prefix', () {
    const prefix = [0x03, 0x90, 0x58, 0xC6, 0xF2];

    expect(pinMatches(cert, pinPrefix: prefix), isTrue);
    expect(pinMatches(other, pinPrefix: prefix), isFalse);
    expect(pinMatches(cert), isFalse);
  });

  test('a pinned client rejects every untrusted root by default', () {
    final client = createPinnedHttpClient(pin: pin);
    addTearDown(client.close);

    expect(client.connectionTimeout, const Duration(seconds: 3));
  });
}
