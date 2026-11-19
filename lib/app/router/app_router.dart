import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/listener/presentation/listener_page.dart';
import '../../features/onboarding/presentation/how_to_use_page.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../../features/pairing/presentation/pairing_page.dart';
import '../../features/pairing/presentation/pairing_view_model.dart';
import '../../features/sessions/presentation/join_session_page.dart';
import '../../features/sessions/presentation/session_waiting_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../di/app_providers.dart';
import '../di/lan_providers.dart';

String? deviceIdentityRedirect(
  DeviceReadinessState readiness,
  String location, {
  required bool onboardingCompleted,
  bool lanOnly = false,
}) {
  // lanOnly (dotnet_SonicRelay#75) never touches RelayControl, so the cloud
  // identity is not a precondition: the app behaves as ready and LAN pairing
  // and listening stay reachable even with no server at all.
  if (lanOnly) {
    if (location == '/settings' || location == '/how-to-use') return null;
    if (!onboardingCompleted) {
      return location == '/onboarding' ? null : '/onboarding';
    }
    if (location == '/loading' ||
        location == '/device-setup' ||
        location == '/onboarding') {
      return '/join';
    }
    return null;
  }
  switch (readiness.status) {
    case DeviceReadinessStatus.restoring:
      return location == '/loading' ? null : '/loading';
    case DeviceReadinessStatus.deviceSetup:
      return location == '/device-setup' ? null : '/device-setup';
    case DeviceReadinessStatus.pairingRequired:
    case DeviceReadinessStatus.ready:
      // Settings and How to use must stay reachable in both these states: Settings holds the
      // server URL field, and a device pointed at the wrong backend can never pair, so
      // redirecting Settings back to /pair left no way to fix it from inside the app. How to
      // use is the permanent onboarding reference reachable from the pairing screen's "?"
      // button, and must not be blocked by the first-use onboarding gate below. The
      // restoring/deviceSetup branches are deliberately unchanged — before a device credential
      // exists there is no authenticated client for Settings to talk to, and _DeviceSetupPage
      // already owns that retry path.
      if (location == '/settings' || location == '/how-to-use') return null;
      if (!onboardingCompleted) {
        return location == '/onboarding' ? null : '/onboarding';
      }
      if (readiness.status == DeviceReadinessStatus.pairingRequired) {
        // /session/waiting and /listener must stay reachable too: the Public Radio entry
        // point on /pair joins a session (and, server-side, auto-pairs the device) without
        // ever going through a real DevicePairing, so this device can still be
        // pairingRequired locally when it navigates into the session flow. /join stays
        // gated — the public-radio join skips it entirely and goes straight to
        // /session/waiting, so nothing needs it reachable here.
        const allowedWhilePairingRequired = {
          '/pair',
          '/session/waiting',
          '/listener',
        };
        return allowedWhilePairingRequired.contains(location) ? null : '/pair';
      }
      if (location == '/loading' ||
          location == '/device-setup' ||
          location == '/onboarding') {
        return '/join';
      }
      return null;
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/loading',
    redirect: (context, state) => deviceIdentityRedirect(
      ref.read(deviceReadinessProvider),
      state.matchedLocation,
      onboardingCompleted: ref.read(onboardingCompletedProvider),
      lanOnly: ref.read(lanOnlyActiveProvider),
    ),
    routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/device-setup',
        builder: (context, state) => const _DeviceSetupPage(),
      ),
      GoRoute(path: '/pair', builder: (context, state) => const PairingPage()),
      GoRoute(
        path: '/join',
        builder: (context, state) => const JoinSessionPage(),
      ),
      GoRoute(
        path: '/session/waiting',
        builder: (context, state) => const SessionWaitingPage(),
      ),
      GoRoute(
        path: '/listener',
        builder: (context, state) => const ListenerPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/how-to-use',
        builder: (context, state) => const HowToUsePage(),
      ),
    ],
  );
  // The splash stays up at least this long even when device identity
  // restores almost instantly, so its animation never just flashes for a
  // frame before the redirect above whisks it away.
  const minimumSplashDuration = Duration(seconds: 1);
  DateTime? restoringSince =
      ref.read(deviceReadinessProvider).status ==
          DeviceReadinessStatus.restoring
      ? DateTime.now()
      : null;
  Timer? splashHoldTimer;

  ref.listen(lanOnlyActiveProvider, (_, _) => router.refresh());
  ref.listen(deviceReadinessProvider, (_, next) {
    if (next.status == DeviceReadinessStatus.restoring) {
      restoringSince ??= DateTime.now();
      router.refresh();
      return;
    }
    final since = restoringSince;
    restoringSince = null;
    splashHoldTimer?.cancel();
    if (since == null) {
      router.refresh();
      return;
    }
    final remaining = minimumSplashDuration - DateTime.now().difference(since);
    if (remaining <= Duration.zero) {
      router.refresh();
    } else {
      splashHoldTimer = Timer(remaining, router.refresh);
    }
  });
  ref.listen(pairingViewModelProvider, (previous, next) {
    // Only emissions that carry an authoritative pairing list may drive readiness.
    // A transient loading/submitting emission — and a failed load, whose list can be
    // stale-empty — used to flip readiness to pairingRequired the moment the user
    // opened "Manage pairings", and the redirect above then trapped every route at
    // /pair with no way back to the dashboard.
    if (next.status == PairingStatus.idle ||
        next.status == PairingStatus.paired) {
      ref.read(deviceReadinessProvider.notifier).syncPairings(next.pairings);
    }
    if (previous?.status != PairingStatus.paired &&
        next.status == PairingStatus.paired) {
      router.go('/join');
    }
  });
  ref.listen(onboardingCompletedProvider, (_, next) {
    if (next) router.refresh();
  });
  ref.onDispose(() {
    splashHoldTimer?.cancel();
    router.dispose();
  });
  return router;
});

class _DeviceSetupPage extends ConsumerWidget {
  const _DeviceSetupPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(deviceReadinessProvider);
    final error = readiness.errorMessage;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up this device')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phonelink_lock_rounded, size: 56),
                  const SizedBox(height: 20),
                  Text(
                    error ?? 'Preparing a secure identity for this device…',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (error == null)
                    const CircularProgressIndicator()
                  else
                    FilledButton(
                      onPressed: () =>
                          ref.read(deviceReadinessProvider.notifier).retry(),
                      child: Text(
                        readiness.requiresReset
                            ? 'Reset device identity'
                            : 'Retry device setup',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
