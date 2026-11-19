import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A user-supplied TURN URL that replaces the one the backend hands out, or null to use the
/// backend's. Deliberately never pre-filled with the backend's value: the deployment's relay
/// host is not disclosed through this UI, and blank means "use whatever the server sends".
///
/// The TURN credential is signed by the backend as
/// `HMAC-SHA1(TURN_STATIC_AUTH_SECRET, "expiry:deviceId")` and this override reuses it, so
/// it only authenticates against a coturn sharing that same static secret — another host or
/// port of the same relay deployment, not a third-party TURN server.
class CoturnOverrideStorage {
  const CoturnOverrideStorage(this._storage);

  static const _key = 'webrtc.coturnUrlOverride';
  static const _pendingSyncKey = 'webrtc.coturnUrlOverridePendingSync';

  final FlutterSecureStorage _storage;

  /// Whether the stored override was chosen before the device could reach the backend (the
  /// first-run setup) and still has to be pushed, so a later pull must not overwrite it.
  Future<bool> readPendingSync() async =>
      (await _storage.read(key: _pendingSyncKey)) == 'true';

  Future<void> writePendingSync(bool pending) => pending
      ? _storage.write(key: _pendingSyncKey, value: 'true')
      : _storage.delete(key: _pendingSyncKey);

  Future<String?> read() async {
    final stored = await _storage.read(key: _key);
    if (stored == null || stored.trim().isEmpty) return null;
    return stored;
  }

  Future<void> write(String? url) async {
    final normalized = url?.trim();
    if (normalized == null || normalized.isEmpty) {
      await _storage.delete(key: _key);
      return;
    }
    await _storage.write(key: _key, value: normalized);
  }
}
