import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/app/router/app_router.dart';

String? _redirect(
  DeviceReadinessState readiness,
  String location, {
  bool onboardingCompleted = true,
}) => deviceIdentityRedirect(
  readiness,
  location,
  onboardingCompleted: onboardingCompleted,
);

void main() {
  test('restoring identity stays on loading', () {
    expect(
      _redirect(const DeviceReadinessState.restoring(), '/join'),
      '/loading',
    );
    expect(
      _redirect(const DeviceReadinessState.restoring(), '/loading'),
      isNull,
    );
  });

  test('missing or invalid credential goes to device setup', () {
    expect(
      _redirect(const DeviceReadinessState.deviceSetup(), '/join'),
      '/device-setup',
    );
  });

  test('ready unpaired device goes to pairing', () {
    expect(
      _redirect(const DeviceReadinessState.pairingRequired(), '/join'),
      '/pair',
    );
  });

  test('paired device leaves onboarding for session join', () {
    expect(
      _redirect(const DeviceReadinessState.ready(), '/loading'),
      '/join',
    );
    expect(_redirect(const DeviceReadinessState.ready(), '/pair'), isNull);
    expect(_redirect(const DeviceReadinessState.ready(), '/settings'), isNull);
  });

  test('production router exposes device-first routes without login', () {
    final container = ProviderContainer(
      overrides: [
        deviceReadinessProvider.overrideWith(_ReadyReadinessNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);
    final paths = router.configuration.routes
        .whereType<GoRoute>()
        .map((route) => route.path)
        .toSet();

    expect(
      paths,
      containsAll(<String>{
        '/device-setup',
        '/pair',
        '/join',
        '/session/waiting',
        '/listener',
        '/settings',
        '/onboarding',
        '/how-to-use',
      }),
    );
    expect(paths, isNot(contains('/login')));
  });

  test('unpaired device can still reach settings', () {
    expect(
      _redirect(const DeviceReadinessState.pairingRequired(), '/settings'),
      isNull,
    );
  });

  test('unpaired device is still redirected away from other pages', () {
    expect(
      _redirect(const DeviceReadinessState.pairingRequired(), '/join'),
      '/pair',
    );
  });

  test(
    'unpaired device can still reach the session flow the Public Radio entry point on '
    '/pair joins into, since that join auto-pairs server-side without a local DevicePairing',
    () {
      expect(
        _redirect(const DeviceReadinessState.pairingRequired(), '/session/waiting'),
        isNull,
      );
      expect(
        _redirect(const DeviceReadinessState.pairingRequired(), '/listener'),
        isNull,
      );
    },
  );

  group('first-use onboarding gate', () {
    test('an unpaired device with pending onboarding is sent there first', () {
      expect(
        _redirect(
          const DeviceReadinessState.pairingRequired(),
          '/pair',
          onboardingCompleted: false,
        ),
        '/onboarding',
      );
      expect(
        _redirect(
          const DeviceReadinessState.pairingRequired(),
          '/join',
          onboardingCompleted: false,
        ),
        '/onboarding',
      );
    });

    test('a paired device with pending onboarding is sent there first', () {
      expect(
        _redirect(
          const DeviceReadinessState.ready(),
          '/join',
          onboardingCompleted: false,
        ),
        '/onboarding',
      );
    });

    test('onboarding itself is not redirected away while pending', () {
      expect(
        _redirect(
          const DeviceReadinessState.pairingRequired(),
          '/onboarding',
          onboardingCompleted: false,
        ),
        isNull,
      );
      expect(
        _redirect(
          const DeviceReadinessState.ready(),
          '/onboarding',
          onboardingCompleted: false,
        ),
        isNull,
      );
    });

    test('settings and how-to-use stay reachable even with pending onboarding', () {
      expect(
        _redirect(
          const DeviceReadinessState.pairingRequired(),
          '/settings',
          onboardingCompleted: false,
        ),
        isNull,
      );
      expect(
        _redirect(
          const DeviceReadinessState.pairingRequired(),
          '/how-to-use',
          onboardingCompleted: false,
        ),
        isNull,
      );
      expect(
        _redirect(
          const DeviceReadinessState.ready(),
          '/how-to-use',
          onboardingCompleted: false,
        ),
        isNull,
      );
    });

    test('a completed onboarding no longer gates navigation', () {
      expect(
        _redirect(
          const DeviceReadinessState.pairingRequired(),
          '/join',
          onboardingCompleted: true,
        ),
        '/pair',
      );
      expect(
        _redirect(
          const DeviceReadinessState.ready(),
          '/pair',
          onboardingCompleted: true,
        ),
        isNull,
      );
    });

    test('revisiting /onboarding once completed leaves it', () {
      expect(
        _redirect(
          const DeviceReadinessState.pairingRequired(),
          '/onboarding',
          onboardingCompleted: true,
        ),
        '/pair',
      );
      expect(
        _redirect(
          const DeviceReadinessState.ready(),
          '/onboarding',
          onboardingCompleted: true,
        ),
        '/join',
      );
    });
  });
}

class _ReadyReadinessNotifier extends DeviceReadinessNotifier {
  @override
  DeviceReadinessState build() => const DeviceReadinessState.ready();
}
