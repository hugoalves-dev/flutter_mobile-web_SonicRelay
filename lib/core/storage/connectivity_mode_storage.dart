import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../webrtc/connectivity_modes.dart';

/// Persists this device's connectivity mode (dotnet_SonicRelay#75). Defaults to
/// [ConnectivityModes.auto]; an unrecognized stored value also reads as auto.
class ConnectivityModeStorage {
  const ConnectivityModeStorage(this._storage);

  static const _key = 'connectivity.mode';

  final FlutterSecureStorage _storage;

  Future<String> read() async {
    final stored = await _storage.read(key: _key);
    return ConnectivityModes.isValid(stored) ? stored! : ConnectivityModes.auto;
  }

  Future<void> write(String mode) {
    if (!ConnectivityModes.isValid(mode)) {
      throw ArgumentError.value(mode, 'mode', 'Unknown connectivity mode');
    }
    return _storage.write(key: _key, value: mode);
  }
}
