import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/app/di/lan_providers.dart';
import 'package:sonic_relay/features/lan/data/lan_pairing_api.dart';
import 'package:sonic_relay/features/lan/data/lan_platform_contract.dart';
import 'package:sonic_relay/features/lan/domain/lan_pairing_offer.dart';
import 'package:sonic_relay/features/lan/presentation/lan_pairing_view_model.dart';

void main() {
  const pin = 'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E';
  const offer = LanPairingOffer(
    pairingId: '11111111-2222-3333-4444-555555555555',
    secret: 'ECAwQFBgcICQoA',
    pin: pin,
    publisherDeviceId: '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
    name: 'DESKTOP-01',
    endpoints: ['192.168.1.20:47321'],
  );
  const okBody = {
    'credential': 'cred',
    'publisherDeviceId': '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
    'publisherName': 'DESKTOP-01',
    'pin': pin,
  };

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ProviderContainer container(LanPost post) {
    final c = ProviderContainer(
      overrides: [
        lanPairingApiProvider.overrideWithValue(LanPairingApi(post: post)),
        deviceDisplayNameProvider.overrideWithValue(() async => 'Pixel 9'),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('pairing from a QR offer stores the desktop and lists it', () async {
    Map<String, Object?>? sent;
    final c = container((endpoint, body, pin) async {
      sent = body;
      return const LanHttpResponse(200, okBody);
    });

    final ok = await c
        .read(lanPairingViewModelProvider.notifier)
        .pairOffer(offer);

    expect(ok, isTrue);
    expect(sent!['viewerName'], 'Pixel 9');
    expect(c.read(lanPairingViewModelProvider).status, LanPairingStatus.paired);
    expect(
      (await c.read(trustedPublishersProvider.future)).single.name,
      'DESKTOP-01',
    );
  });

  test('manual pairing validates the address and the code', () async {
    final c = container((_, _, _) async => const LanHttpResponse(200, okBody));
    final vm = c.read(lanPairingViewModelProvider.notifier);

    expect(
      await vm.pairManual('not an address', '0E85-HHQJ-20G3-0G2G'),
      isFalse,
    );
    expect(
      c.read(lanPairingViewModelProvider).errorMessage,
      contains('address'),
    );

    expect(await vm.pairManual('192.168.2.20:47321', 'short'), isFalse);
    expect(c.read(lanPairingViewModelProvider).errorMessage, contains('code'));
  });

  test('manual pairing over a routed subnet succeeds', () async {
    final c = container((endpoint, body, pin) async {
      expect(endpoint, '192.168.2.20:47321');
      return const LanHttpResponse(200, okBody);
    });

    expect(
      await c
          .read(lanPairingViewModelProvider.notifier)
          .pairManual('192.168.2.20:47321', '0E85-HHQJ-20G3-0G2G'),
      isTrue,
    );
  });

  test('a failure is explained with its diagnostic code', () async {
    final c = container(
      (_, _, _) async =>
          throw const LanTransportException(LanTransportFailure.unreachable),
    );

    await c.read(lanPairingViewModelProvider.notifier).pairOffer(offer);

    final state = c.read(lanPairingViewModelProvider);
    expect(state.status, LanPairingStatus.failed);
    expect(state.errorMessage, contains('lan.unreachable'));
  });

  test('forget removes the desktop', () async {
    final c = container((_, _, _) async => const LanHttpResponse(200, okBody));
    final vm = c.read(lanPairingViewModelProvider.notifier);
    await vm.pairOffer(offer);

    await vm.forget(offer.publisherDeviceId);

    expect(await c.read(trustedPublishersProvider.future), isEmpty);
  });
}
