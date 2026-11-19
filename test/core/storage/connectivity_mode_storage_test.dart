import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/storage/connectivity_mode_storage.dart';
import 'package:sonic_relay/core/webrtc/connectivity_modes.dart';

void main() {
  const secureStorage = FlutterSecureStorage();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('defaults to auto with nothing stored', () async {
    expect(
      await const ConnectivityModeStorage(secureStorage).read(),
      ConnectivityModes.auto,
    );
  });

  test('round trips a written mode', () async {
    const storage = ConnectivityModeStorage(secureStorage);

    await storage.write(ConnectivityModes.lanOnly);

    expect(await storage.read(), ConnectivityModes.lanOnly);
  });

  test('an invalid stored value falls back to auto', () async {
    await secureStorage.write(key: 'connectivity.mode', value: 'lan');

    expect(
      await const ConnectivityModeStorage(secureStorage).read(),
      ConnectivityModes.auto,
    );
  });

  test('literals match the desktop client string for string', () {
    expect(ConnectivityModes.auto, 'auto');
    expect(ConnectivityModes.lanOnly, 'lanOnly');
    expect(ConnectivityModes.cloudOnly, 'cloudOnly');
    expect(ConnectivityModes.isValid('LANONLY'), isFalse);
    expect(ConnectivityModes.allowsLan(ConnectivityModes.cloudOnly), isFalse);
    expect(ConnectivityModes.allowsCloud(ConnectivityModes.lanOnly), isFalse);
  });

  test('writing an invalid mode throws', () async {
    expect(
      () => const ConnectivityModeStorage(secureStorage).write('lan'),
      throwsArgumentError,
    );
  });
}
