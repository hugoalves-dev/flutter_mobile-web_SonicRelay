import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/app/di/lan_providers.dart';
import 'package:sonic_relay/core/webrtc/connectivity_modes.dart';
import 'package:sonic_relay/features/lan/data/lan_pairing_api.dart';
import 'package:sonic_relay/features/pairing/data/pairing_repository.dart';
import 'package:sonic_relay/features/pairing/domain/device_pairing.dart';
import 'package:sonic_relay/features/pairing/domain/pairing_challenge_payload.dart';
import 'package:sonic_relay/features/pairing/presentation/pairing_view_model.dart';

class RecordingRepository implements PairingRepository {
  bool strict = false;
  PairingChallengePayload? completed;

  @override
  Future<DevicePairing> complete(PairingChallengePayload payload) async {
    if (strict) throw StateError('cloud pairing must not run');
    completed = payload;
    return DevicePairing(
      pairingId: 'p',
      publisherDeviceId: 'pub',
      viewerDeviceId: 'v',
      status: 'active',
      createdAt: DateTime.utc(2026, 11, 17),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const pin = 'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E';
  final lanBlock = {
    'pid': '11111111-2222-3333-4444-555555555555',
    'sec': 'ECAwQFBgcICQoA',
    'pin': pin,
    'did': '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
    'name': 'DESKTOP-01',
    'ep': ['192.168.1.20:47321'],
  };
  const cloudBlock = {
    'challengeId': '00000000-0000-0000-0000-000000000001',
    'code': '123456',
  };

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ProviderContainer container(RecordingRepository repository, String mode) {
    final c = ProviderContainer(
      overrides: [
        pairingRepositoryProvider.overrideWithValue(repository),
        connectivityModeProvider.overrideWith(
          () => ConnectivityModeNotifier(mode),
        ),
        lanPairingApiProvider.overrideWithValue(
          LanPairingApi(
            post: (_, _, _) async => const LanHttpResponse(200, {
              'credential': 'cred',
              'publisherDeviceId': '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
              'publisherName': 'DESKTOP-01',
              'pin': pin,
            }),
          ),
        ),
        deviceDisplayNameProvider.overrideWithValue(() async => 'Pixel'),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('qr v2 with only a lan block pairs locally', () async {
    final repository = RecordingRepository()..strict = true;
    final c = container(repository, ConnectivityModes.auto);

    final ok = await c
        .read(pairingViewModelProvider.notifier)
        .completeScanned(jsonEncode({'v': 2, 'lan': lanBlock}));

    expect(ok, isTrue);
    expect(c.read(pairingViewModelProvider).status, PairingStatus.paired);
    expect((await c.read(trustedPublishersProvider.future)).single.pin, pin);
  });

  test('qr v2 pairs both blocks in auto', () async {
    final repository = RecordingRepository();
    final c = container(repository, ConnectivityModes.auto);

    await c
        .read(pairingViewModelProvider.notifier)
        .completeScanned(
          jsonEncode({'v': 2, 'cloud': cloudBlock, 'lan': lanBlock}),
        );

    expect(repository.completed!.code, '123456');
    expect(await c.read(trustedPublishersProvider.future), hasLength(1));
  });

  test('lanOnly skips the cloud block', () async {
    final repository = RecordingRepository()..strict = true;
    final c = container(repository, ConnectivityModes.lanOnly);

    final ok = await c
        .read(pairingViewModelProvider.notifier)
        .completeScanned(
          jsonEncode({'v': 2, 'cloud': cloudBlock, 'lan': lanBlock}),
        );

    expect(ok, isTrue);
  });

  test('cloudOnly skips the lan block', () async {
    final repository = RecordingRepository();
    final c = container(repository, ConnectivityModes.cloudOnly);

    await c
        .read(pairingViewModelProvider.notifier)
        .completeScanned(
          jsonEncode({'v': 2, 'cloud': cloudBlock, 'lan': lanBlock}),
        );

    expect(repository.completed, isNotNull);
    expect(await c.read(trustedPublishersProvider.future), isEmpty);
  });
}
