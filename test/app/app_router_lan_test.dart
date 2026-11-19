import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/app/di/lan_providers.dart';
import 'package:sonic_relay/app/router/app_router.dart';
import 'package:sonic_relay/core/webrtc/connectivity_modes.dart';
import 'package:sonic_relay/features/device_identity/data/device_identity_session.dart';

class ForbiddenIdentity implements DeviceIdentitySession {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('lanOnly must not bootstrap the cloud identity');
  }
}

String? redirect(DeviceReadinessState readiness, String location) =>
    deviceIdentityRedirect(
      readiness,
      location,
      onboardingCompleted: true,
      lanOnly: true,
    );

void main() {
  test('router lanOnly bypasses the cloud identity gate', () {
    expect(
      redirect(const DeviceReadinessState.restoring(), '/loading'),
      '/join',
    );
    expect(redirect(const DeviceReadinessState.restoring(), '/join'), isNull);
    expect(redirect(const DeviceReadinessState.deviceSetup(), '/join'), isNull);
    expect(
      redirect(const DeviceReadinessState.pairingRequired(), '/join'),
      isNull,
    );
    expect(
      redirect(const DeviceReadinessState.restoring(), '/device-setup'),
      '/join',
    );
    expect(redirect(const DeviceReadinessState.restoring(), '/pair'), isNull);
    expect(
      redirect(const DeviceReadinessState.restoring(), '/listener'),
      isNull,
    );
  });

  test('lanOnly still shows first-use onboarding', () {
    expect(
      deviceIdentityRedirect(
        const DeviceReadinessState.restoring(),
        '/join',
        onboardingCompleted: false,
        lanOnly: true,
      ),
      '/onboarding',
    );
  });

  test('without lanOnly the cloud gate is unchanged', () {
    expect(
      deviceIdentityRedirect(
        const DeviceReadinessState.restoring(),
        '/join',
        onboardingCompleted: true,
      ),
      '/loading',
    );
  });

  test('lanOnly never bootstraps the cloud device identity', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final identity = ForbiddenIdentity();
    final container = ProviderContainer(
      overrides: [
        connectivityModeProvider.overrideWith(
          () => ConnectivityModeNotifier(ConnectivityModes.lanOnly),
        ),
        deviceIdentitySessionProvider.overrideWithValue(identity),
      ],
    );
    addTearDown(container.dispose);

    container.read(deviceReadinessProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(identity.calls, 0);
  });
}
