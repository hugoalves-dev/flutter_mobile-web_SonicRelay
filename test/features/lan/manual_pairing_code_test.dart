import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/features/lan/domain/manual_pairing_code.dart';

void main() {
  // Shared vector with the desktop (tests/SonicRelay.Windows.Lan.Tests/ManualPairingCodeTests.cs).
  const pin = 'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E';
  const secret = [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90, 0xA0];
  const vector = '0E85-HHQJ-20G3-0G2G';
  const pinPrefix = [0x03, 0x90, 0x58, 0xC6, 0xF2];

  test('manual code round trip matches desktop vector', () {
    expect(ManualPairingCode.encode(pin, secret), vector);

    final decoded = ManualPairingCode.tryDecode(vector)!;
    expect(decoded.pinPrefix, pinPrefix);
    expect(decoded.secret, secret.sublist(0, 5));
  });

  for (final typed in [
    '0e85-hhqj-20g3-0g2g',
    '0E85HHQJ20G30G2G',
    'OE85-HHQJ-2OG3-OG2G',
    ' 0E85 HHQJ 20G3 0G2G ',
  ]) {
    test('decoding is lenient: "$typed"', () {
      expect(ManualPairingCode.tryDecode(typed)!.pinPrefix, pinPrefix);
    });
  }

  for (final typed in [
    '',
    '0E85-HHQJ-20G3',
    '0E85-HHQJ-20G3-0G2U',
    '0E85-HHQJ-20G3-0G2G-0000',
  ]) {
    test('rejects malformed "$typed"', () {
      expect(ManualPairingCode.tryDecode(typed), isNull);
    });
  }

  test('normalize formats a typed code as XXXX-XXXX-XXXX-XXXX', () {
    expect(ManualPairingCode.normalize('oe85hhqj2og3og2g'), vector);
  });
}
