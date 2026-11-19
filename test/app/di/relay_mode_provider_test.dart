import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/core/storage/relay_mode_storage.dart';
import 'package:sonic_relay/core/webrtc/relay_modes.dart';

class _FakeRelayModeStorage extends RelayModeStorage {
  _FakeRelayModeStorage() : super(const FlutterSecureStorage());

  String? written;
  String stored = RelayModes.automatic;

  @override
  Future<String> read() async => stored;

  @override
  Future<void> write(String mode) async {
    written = mode;
    stored = mode;
  }
}

void main() {
  test(
    'RelayModeNotifier.set writes the chosen mode to local storage and applies it directly, '
    "with no server round-trip — it's a per-device preference now",
    () async {
      final storage = _FakeRelayModeStorage();
      final container = ProviderContainer(
        overrides: [relayModeStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      expect(container.read(relayModeProvider), RelayModes.automatic);

      await container.read(relayModeProvider.notifier).set(RelayModes.forceRelay);

      expect(container.read(relayModeProvider), RelayModes.forceRelay);
      expect(storage.written, RelayModes.forceRelay);
    },
  );
}
