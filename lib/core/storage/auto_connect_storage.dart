import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auto_connect/domain/auto_connect_settings.dart';

/// Persists [AutoConnectSettings] across app restarts. Absent values read as off: the
/// feature must never switch itself on.
class AutoConnectStorage {
  const AutoConnectStorage(this._storage);

  static const _enabledKey = 'autoConnect.enabled';
  static const _deviceIdKey = 'autoConnect.publisherDeviceId';
  static const _deviceNameKey = 'autoConnect.publisherDeviceName';

  final FlutterSecureStorage _storage;

  Future<AutoConnectSettings> read() async {
    final enabled = await _storage.read(key: _enabledKey);
    final deviceId = await _storage.read(key: _deviceIdKey);
    final deviceName = await _storage.read(key: _deviceNameKey);
    return AutoConnectSettings(
      enabled: enabled == 'true',
      publisherDeviceId: deviceId,
      publisherDeviceName: deviceName,
    );
  }

  Future<void> write(AutoConnectSettings settings) async {
    await _storage.write(
      key: _enabledKey,
      value: settings.enabled ? 'true' : 'false',
    );
    await _writeOrDelete(_deviceIdKey, settings.publisherDeviceId);
    await _writeOrDelete(_deviceNameKey, settings.publisherDeviceName);
  }

  Future<void> _writeOrDelete(String key, String? value) => value == null
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value);
}
