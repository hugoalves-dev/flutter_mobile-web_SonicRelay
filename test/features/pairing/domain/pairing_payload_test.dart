import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/features/pairing/domain/pairing_payload.dart';

void main() {
  const challengeId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const pid = '11111111-2222-3333-4444-555555555555';
  const did = '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e';

  Map<String, Object?> lanBlock() => {
    'pid': pid,
    'sec': 'ECAwQFBgcICQoA',
    'pin': 'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E',
    'did': did,
    'name': 'DESKTOP-01',
    'ep': ['192.168.1.20:47321', '[fd00::20]:47321', 'desk.local:47321'],
  };

  test('legacy cloud payload still parses', () {
    final payload = PairingPayload.parse(
      jsonEncode({'challengeId': challengeId, 'code': ' 123456 '}),
    );

    expect(payload.cloud!.challengeId, challengeId);
    expect(payload.cloud!.code, '123456');
    expect(payload.lan, isNull);
  });

  test('v2 with both blocks', () {
    final payload = PairingPayload.parse(
      jsonEncode({
        'v': 2,
        'cloud': {'challengeId': challengeId, 'code': '123456'},
        'lan': lanBlock(),
      }),
    );

    expect(payload.cloud!.code, '123456');
    final lan = payload.lan!;
    expect(lan.pairingId, pid);
    expect(lan.secret, 'ECAwQFBgcICQoA');
    expect(lan.publisherDeviceId, did);
    expect(lan.name, 'DESKTOP-01');
    expect(lan.endpoints, hasLength(3));
  });

  test('v2 lan only', () {
    final payload = PairingPayload.parse(jsonEncode({'v': 2, 'lan': lanBlock()}));

    expect(payload.cloud, isNull);
    expect(payload.lan!.pin, startsWith('A5BY'));
  });

  test('rejects v2 with no blocks', () {
    expect(
      () => PairingPayload.parse(jsonEncode({'v': 2})),
      throwsFormatException,
    );
  });

  test('rejects an unknown version', () {
    expect(
      () => PairingPayload.parse(jsonEncode({'v': 3, 'lan': lanBlock()})),
      throwsFormatException,
    );
  });

  test('rejects malformed endpoints', () {
    final bad = lanBlock()..['ep'] = ['not an endpoint', '1.2.3.4'];

    expect(
      () => PairingPayload.parse(jsonEncode({'v': 2, 'lan': bad})),
      throwsFormatException,
    );
  });

  test('rejects a lan block with a short pin or missing secret', () {
    final shortPin = lanBlock()..['pin'] = 'abc';
    final noSecret = lanBlock()..remove('sec');

    expect(
      () => PairingPayload.parse(jsonEncode({'v': 2, 'lan': shortPin})),
      throwsFormatException,
    );
    expect(
      () => PairingPayload.parse(jsonEncode({'v': 2, 'lan': noSecret})),
      throwsFormatException,
    );
  });

  test('rejects non-json', () {
    expect(() => PairingPayload.parse('hello'), throwsFormatException);
  });
}
