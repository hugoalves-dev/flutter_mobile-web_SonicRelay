import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/app/router/app_router.dart';
import 'package:sonic_relay/features/device_identity/data/device_credential_storage.dart';
import 'package:sonic_relay/features/device_identity/data/device_identity_api.dart';
import 'package:sonic_relay/features/device_identity/data/device_identity_session.dart';
import 'package:sonic_relay/features/device_identity/data/dto/bootstrap_device_request.dart';
import 'package:sonic_relay/features/device_identity/data/dto/bootstrap_device_response.dart';
import 'package:sonic_relay/features/device_identity/data/dto/device_token_request.dart';
import 'package:sonic_relay/features/device_identity/data/dto/device_token_response.dart';
import 'package:sonic_relay/features/device_identity/domain/device_credential.dart';
import 'package:sonic_relay/features/pairing/data/pairing_repository.dart';
import 'package:sonic_relay/features/pairing/domain/device_pairing.dart';
import 'package:sonic_relay/features/pairing/domain/pairing_challenge_payload.dart';

const _credential = DeviceCredential(
  deviceId: 'viewer-1',
  credentialSecret: 'secret-1',
  credentialVersion: 1,
  deviceType: 'flutter_viewer',
  platform: 'android',
);

void main() {
  test('device identity session is shared by the provider container', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      identical(
        container.read(deviceIdentitySessionProvider),
        container.read(deviceIdentitySessionProvider),
      ),
      isTrue,
    );
  });

  test(
    'missing credential stays in setup until bootstrap and pairing check finish',
    () async {
      final access = Completer<String>();
      final storage = _MemoryCredentialStorage();
      final session = _FakeDeviceIdentitySession(
        access: access,
        onAccess: () => storage.credential = _credential,
      );
      final repository = _FakePairingRepository();
      final container = ProviderContainer(
        overrides: [
          deviceCredentialStorageProvider.overrideWithValue(storage),
          deviceIdentitySessionProvider.overrideWithValue(session),
          pairingRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(deviceReadinessProvider).status,
        DeviceReadinessStatus.restoring,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(deviceReadinessProvider).status,
        DeviceReadinessStatus.deviceSetup,
      );

      access.complete('device-token');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(repository.listedDeviceId, 'viewer-1');
      expect(
        container.read(deviceReadinessProvider).status,
        DeviceReadinessStatus.pairingRequired,
      );
    },
  );

  test('active pairing makes the device ready for session join', () async {
    final storage = _MemoryCredentialStorage()..credential = _credential;
    final repository = _FakePairingRepository()
      ..pairings = [
        DevicePairing(
          pairingId: 'pairing-1',
          publisherDeviceId: 'publisher-1',
          viewerDeviceId: 'viewer-1',
          status: 'active',
          createdAt: DateTime.utc(2026, 7, 29),
        ),
      ];
    final container = ProviderContainer(
      overrides: [
        deviceCredentialStorageProvider.overrideWithValue(storage),
        deviceIdentitySessionProvider.overrideWithValue(
          _FakeDeviceIdentitySession.completed(),
        ),
        pairingRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    container.read(deviceReadinessProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(deviceReadinessProvider).status,
      DeviceReadinessStatus.ready,
    );
  });

  test(
    'retry resets an invalid credential before bootstrapping again',
    () async {
      final storage = _MemoryCredentialStorage()
        ..readError = const DeviceCredentialStorageException('invalid');
      final session = _FakeDeviceIdentitySession.completed(
        onAccess: () => storage.credential = _credential,
        onReset: () => storage.readError = null,
      );
      final container = ProviderContainer(
        overrides: [
          deviceCredentialStorageProvider.overrideWithValue(storage),
          deviceIdentitySessionProvider.overrideWithValue(session),
          pairingRepositoryProvider.overrideWithValue(_FakePairingRepository()),
        ],
      );
      addTearDown(container.dispose);

      container.read(deviceReadinessProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(deviceReadinessProvider).requiresReset, isTrue);

      await container.read(deviceReadinessProvider.notifier).retry();

      expect(session.resetCalls, 1);
      expect(
        container.read(deviceReadinessProvider).status,
        DeviceReadinessStatus.pairingRequired,
      );
    },
  );

  for (final action in ['retry', 'resetAndInitialize']) {
    test('$action returns to resettable setup when secure clear fails', () async {
      final storage = _MemoryCredentialStorage()..credential = _credential;
      final session = _FakeDeviceIdentitySession.completed(
        onReset: () => throw const DeviceCredentialStorageException(
          'clear failed',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          deviceCredentialStorageProvider.overrideWithValue(storage),
          deviceIdentitySessionProvider.overrideWithValue(session),
          pairingRepositoryProvider.overrideWithValue(_FakePairingRepository()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(deviceReadinessProvider.notifier);
      container.read(deviceReadinessProvider);
      await Future<void>.delayed(Duration.zero);
      notifier.requireDeviceSetup('Reset required.');

      if (action == 'retry') {
        await notifier.retry();
      } else {
        await notifier.resetAndInitialize();
      }

      final readiness = container.read(deviceReadinessProvider);
      expect(readiness.status, DeviceReadinessStatus.deviceSetup);
      expect(readiness.requiresReset, isTrue);
      expect(readiness.errorMessage, isNotEmpty);
      expect(session.resetCalls, 1);
    });
  }

  test(
    'token revocation redirects an active listener when cleanup fails',
    () async {
      final storage = _MemoryCredentialStorage()
        ..credential = _credential
        ..clearFailuresRemaining = 1;
      final api = _RevocableDeviceIdentityApi();
      final repository = _FakePairingRepository()
        ..pairings = [
          DevicePairing(
            pairingId: 'pairing-1',
            publisherDeviceId: 'publisher-1',
            viewerDeviceId: 'viewer-1',
            status: 'active',
            createdAt: DateTime.utc(2026, 7, 29),
          ),
        ];
      final container = ProviderContainer(
        overrides: [
          deviceCredentialStorageProvider.overrideWithValue(storage),
          deviceIdentityApiProvider.overrideWithValue(api),
          pairingRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      container.read(deviceReadinessProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(deviceReadinessProvider).status,
        DeviceReadinessStatus.ready,
      );

      api.revoked = true;
      await expectLater(
        container
            .read(deviceIdentitySessionProvider)
            .accessToken(forceRefresh: true),
        throwsA(isA<DeviceIdentitySessionInvalidatedException>()),
      );
      await Future<void>.delayed(Duration.zero);

      final readiness = container.read(deviceReadinessProvider);
      expect(readiness.status, DeviceReadinessStatus.deviceSetup);
      expect(readiness.requiresReset, isTrue);
      expect(
        deviceIdentityRedirect(
          readiness,
          '/listener',
          onboardingCompleted: true,
        ),
        '/device-setup',
      );

      await expectLater(
        container.read(deviceIdentitySessionProvider).accessToken(),
        throwsA(isA<DeviceIdentitySessionInvalidatedException>()),
      );
    },
  );
}

class _MemoryCredentialStorage implements DeviceCredentialStorage {
  DeviceCredential? credential;
  Object? readError;
  int clearFailuresRemaining = 0;

  @override
  Future<void> clear() async {
    if (clearFailuresRemaining > 0) {
      clearFailuresRemaining--;
      throw const DeviceCredentialStorageException('clear failed');
    }
    credential = null;
  }

  @override
  Future<DeviceCredential?> read() async {
    if (readError case final error?) throw error;
    return credential;
  }

  @override
  Future<void> write(DeviceCredential value) async => credential = value;
}

class _FakeDeviceIdentitySession implements DeviceIdentitySession {
  _FakeDeviceIdentitySession({
    required Completer<String> access,
    required this.onAccess,
  }) : _access = access,
       onReset = _noop;

  _FakeDeviceIdentitySession.completed({
    this.onAccess = _noop,
    this.onReset = _noop,
  }) : _access = (Completer<String>()..complete('device-token')),
       resetCalls = 0;

  final Completer<String> _access;
  final void Function() onAccess;
  final void Function() onReset;
  int resetCalls = 0;

  @override
  Future<String> accessToken({bool forceRefresh = false}) {
    onAccess();
    return _access.future;
  }

  @override
  Future<void> reset() async {
    resetCalls += 1;
    onReset();
  }
}

void _noop() {}

class _FakePairingRepository implements PairingRepository {
  List<DevicePairing> pairings = const [];
  String? listedDeviceId;

  @override
  Future<DevicePairing> complete(PairingChallengePayload payload) =>
      throw UnimplementedError();

  @override
  Future<List<DevicePairing>> list(String deviceId) async {
    listedDeviceId = deviceId;
    return pairings;
  }

  @override
  Future<void> revoke(String pairingId) => throw UnimplementedError();
}

class _RevocableDeviceIdentityApi implements DeviceIdentityApi {
  bool revoked = false;

  @override
  Future<BootstrapDeviceResponse> bootstrap(BootstrapDeviceRequest request) =>
      throw UnimplementedError();

  @override
  Future<DeviceTokenResponse> token(DeviceTokenRequest request) async {
    if (revoked) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/devices/token'),
        response: Response<void>(
          requestOptions: RequestOptions(path: '/api/devices/token'),
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return DeviceTokenResponse(
      accessToken: 'device-token',
      expiresAt: DateTime.utc(2026, 7, 29, 14),
      scopes: const ['stream:listen'],
    );
  }
}
