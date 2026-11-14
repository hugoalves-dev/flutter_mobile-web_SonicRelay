import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Records that the user reviewed the API and TURN addresses on first launch.
class InitialServerSetupStorage {
  const InitialServerSetupStorage(this._storage);

  static const _key = 'server.initialSetupCompleted';

  final FlutterSecureStorage _storage;

  Future<bool> read() async => (await _storage.read(key: _key)) == 'true';

  Future<void> write(bool completed) =>
      _storage.write(key: _key, value: completed.toString());
}
