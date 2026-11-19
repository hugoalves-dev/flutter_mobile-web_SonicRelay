import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/connectivity_mode_storage.dart';
import '../../core/webrtc/connectivity_modes.dart';
import '../../features/lan/data/lan_discovery_service.dart';
import '../../features/lan/data/lan_pairing_api.dart';
import '../../features/lan/data/lan_platform.dart';
import '../../features/lan/data/lan_platform_contract.dart';
import '../../features/lan/data/lan_session_connector.dart';
import '../../features/lan/data/trusted_publisher_store.dart';
import '../../features/lan/domain/trusted_publisher.dart';
import 'app_providers.dart';

/// LAN mode wiring (dotnet_SonicRelay#75). Kept apart from the cloud providers
/// so the whole feature is visible in one place.

final connectivityModeStorageProvider = Provider<ConnectivityModeStorage>(
  (ref) => ConnectivityModeStorage(ref.watch(secureStorageProvider)),
);

/// This device's connectivity mode; local only, never sent to the backend.
final connectivityModeProvider =
    NotifierProvider<ConnectivityModeNotifier, String>(
      ConnectivityModeNotifier.new,
    );

class ConnectivityModeNotifier extends Notifier<String> {
  ConnectivityModeNotifier([this._initial = ConnectivityModes.auto]);

  final String _initial;

  @override
  String build() => _initial;

  Future<void> set(String mode) async {
    await ref.read(connectivityModeStorageProvider).write(mode);
    state = mode;
  }
}

final lanPlatformProvider = Provider<LanPlatform>((_) => createLanPlatform());

/// True when the app must not reach RelayControl at all: `lanOnly` on a
/// platform that supports LAN (on the web LAN is unsupported, so the cloud
/// flow stays the only one).
final lanOnlyActiveProvider = Provider<bool>(
  (ref) =>
      ref.watch(lanPlatformProvider).isSupported &&
      ref.watch(connectivityModeProvider) == ConnectivityModes.lanOnly,
);

/// Whether LAN features should be offered at all: supported platform (not the
/// web) and a mode that allows LAN.
final lanEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(lanPlatformProvider).isSupported &&
      ConnectivityModes.allowsLan(ref.watch(connectivityModeProvider)),
);

final trustedPublisherStoreProvider = Provider<TrustedPublisherStore>(
  (ref) => TrustedPublisherStore(ref.watch(secureStorageProvider)),
);

/// Desktops paired over the LAN. Refresh with `ref.invalidate` after a pair or forget.
final trustedPublishersProvider = FutureProvider<List<TrustedPublisher>>(
  (ref) => ref.watch(trustedPublisherStoreProvider).list(),
);

final lanPairingApiProvider = Provider<LanPairingApi>(
  (ref) => LanPairingApi(post: ref.watch(lanPlatformProvider).pairingPost),
);

final lanDiscoveryServiceProvider = Provider<LanDiscoveryService>((ref) {
  final service = LanDiscoveryService(
    ref.watch(lanPlatformProvider).createBrowser(),
  );
  ref.onDispose(service.dispose);
  return service;
});

final lanSessionConnectorProvider = Provider<LanSessionConnector>(
  (ref) => LanSessionConnector(
    platform: ref.watch(lanPlatformProvider),
    store: ref.watch(trustedPublisherStoreProvider),
  ),
);
