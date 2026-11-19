import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/features/lan/data/lan_pairing_api.dart';
import 'package:sonic_relay/features/lan/data/lan_platform_contract.dart';
import 'package:sonic_relay/features/lan/domain/lan_failure.dart';
import 'package:sonic_relay/features/lan/domain/lan_pairing_offer.dart';

void main() {
  const pin = 'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E';
  const viewerId = '11111111-1111-1111-1111-111111111111';
  const offer = LanPairingOffer(
    pairingId: '11111111-2222-3333-4444-555555555555',
    secret: 'ECAwQFBgcICQoA',
    pin: pin,
    publisherDeviceId: '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
    name: 'DESKTOP-01',
    endpoints: ['192.168.1.20:47321', '192.168.2.20:47321'],
  );

  const okBody = {
    'credential': 'cred-cred-cred',
    'publisherDeviceId': '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
    'publisherName': 'DESKTOP-01',
    'pin': pin,
  };

  Future<LanFailureCode> failureOf(Future<Object?> future) async {
    try {
      await future;
    } on LanFailure catch (failure) {
      return failure.code;
    }
    fail('expected a LanFailure');
  }

  test(
    'pairs over the first reachable endpoint and returns a trusted publisher',
    () async {
      final calls = <String>[];
      final api = LanPairingApi(
        post: (endpoint, body, pinPolicy) async {
          calls.add(endpoint);
          if (endpoint.startsWith('192.168.1.'))
            throw const LanTransportException(
              LanTransportFailure.unreachable,
              'no route',
            );
          expect(pinPolicy.pin, pin);
          expect(body['pid'], offer.pairingId);
          expect(body['sec'], offer.secret);
          expect(body['viewerDeviceId'], viewerId);
          return const LanHttpResponse(200, okBody);
        },
      );

      final publisher = await api.pair(
        endpoints: offer.endpoints,
        offer: offer,
        viewerDeviceId: viewerId,
        viewerName: 'Pixel',
        platform: 'android',
      );

      expect(calls, ['192.168.1.20:47321', '192.168.2.20:47321']);
      expect(publisher.credential, 'cred-cred-cred');
      expect(publisher.pin, pin);
      expect(publisher.lastEndpoints.first, '192.168.2.20:47321');
    },
  );

  test('manual code pairing pins only the prefix and sends the code', () async {
    final api = LanPairingApi(
      post: (endpoint, body, pinPolicy) async {
        expect(pinPolicy.pin, isNull);
        expect(pinPolicy.pinPrefix, [0x03, 0x90, 0x58, 0xC6, 0xF2]);
        expect(body['code'], '0E85-HHQJ-20G3-0G2G');
        return const LanHttpResponse(200, okBody);
      },
    );

    final publisher = await api.pair(
      endpoints: ['192.168.2.20:47321'],
      manualCode: 'oe85 hhqj 2og3 og2g',
      viewerDeviceId: viewerId,
      viewerName: 'Pixel',
      platform: 'android',
    );

    expect(publisher.pin, pin);
  });

  test(
    'a response pin that contradicts the manual prefix is rejected',
    () async {
      final foreign = Map<String, dynamic>.of(okBody)
        ..['pin'] = 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz';
      final api = LanPairingApi(
        post: (endpoint, body, pinPolicy) async =>
            LanHttpResponse(200, foreign),
      );

      expect(
        await failureOf(
          api.pair(
            endpoints: ['10.0.0.1:1'],
            manualCode: '0E85-HHQJ-20G3-0G2G',
            viewerDeviceId: viewerId,
            viewerName: 'Pixel',
            platform: 'android',
          ),
        ),
        LanFailureCode.pinMismatch,
      );
    },
  );

  test('pair maps 400/410/429', () async {
    for (final (status, code) in [
      (400, LanFailureCode.pairingInvalid),
      (410, LanFailureCode.pairingExpired),
      (429, LanFailureCode.rateLimited),
    ]) {
      final api = LanPairingApi(
        post: (_, _, _) async => LanHttpResponse(status, const {}),
      );
      expect(
        await failureOf(
          api.pair(
            endpoints: ['10.0.0.1:1'],
            offer: offer,
            viewerDeviceId: viewerId,
            viewerName: 'Pixel',
            platform: 'android',
          ),
        ),
        code,
      );
    }
  });

  test(
    'a TLS handshake failure is a pin mismatch and is not retried elsewhere',
    () async {
      var calls = 0;
      final api = LanPairingApi(
        post: (_, _, _) async {
          calls++;
          throw const LanTransportException(
            LanTransportFailure.tlsRejected,
            'bad certificate',
          );
        },
      );

      expect(
        await failureOf(
          api.pair(
            endpoints: offer.endpoints,
            offer: offer,
            viewerDeviceId: viewerId,
            viewerName: 'Pixel',
            platform: 'android',
          ),
        ),
        LanFailureCode.pinMismatch,
      );
      expect(calls, 1);
    },
  );

  test('every endpoint unreachable is unreachable', () async {
    final api = LanPairingApi(
      post: (_, _, _) async => throw const LanTransportException(
        LanTransportFailure.unreachable,
        'timeout',
      ),
    );

    expect(
      await failureOf(
        api.pair(
          endpoints: offer.endpoints,
          offer: offer,
          viewerDeviceId: viewerId,
          viewerName: 'Pixel',
          platform: 'android',
        ),
      ),
      LanFailureCode.unreachable,
    );
  });
}
