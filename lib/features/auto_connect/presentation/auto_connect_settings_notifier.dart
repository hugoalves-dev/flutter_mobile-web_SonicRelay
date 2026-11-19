import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';
import '../domain/auto_connect_settings.dart';

final autoConnectSettingsProvider =
    AsyncNotifierProvider<AutoConnectSettingsNotifier, AutoConnectSettings>(
      AutoConnectSettingsNotifier.new,
    );

/// Loads and saves the auto-connect preference. Every change is persisted before the
/// state updates, so what the UI shows is what survives a restart.
class AutoConnectSettingsNotifier extends AsyncNotifier<AutoConnectSettings> {
  @override
  Future<AutoConnectSettings> build() =>
      ref.read(autoConnectStorageProvider).read();

  Future<void> setEnabled(bool enabled) =>
      _save(_current.copyWith(enabled: enabled));

  Future<void> select(String publisherDeviceId, String publisherDeviceName) =>
      _save(
        _current.copyWith(
          publisherDeviceId: publisherDeviceId,
          publisherDeviceName: publisherDeviceName,
        ),
      );

  AutoConnectSettings get _current => state.value ?? AutoConnectSettings.off;

  Future<void> _save(AutoConnectSettings settings) async {
    await ref.read(autoConnectStorageProvider).write(settings);
    state = AsyncData(settings);
  }
}
