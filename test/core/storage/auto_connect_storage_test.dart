import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/core/storage/auto_connect_storage.dart';
import 'package:sonic_relay/features/auto_connect/domain/auto_connect_settings.dart';

void main() {
  const secureStorage = FlutterSecureStorage();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('defaults to off with nothing stored', () async {
    final settings = await const AutoConnectStorage(secureStorage).read();

    expect(settings.enabled, isFalse);
    expect(settings.publisherDeviceId, isNull);
    expect(settings.isActive, isFalse);
  });

  test('round trips an enabled selection', () async {
    const storage = AutoConnectStorage(secureStorage);

    await storage.write(
      const AutoConnectSettings(
        enabled: true,
        publisherDeviceId: 'pub-1',
        publisherDeviceName: 'Home PC',
      ),
    );
    final settings = await storage.read();

    expect(settings.enabled, isTrue);
    expect(settings.publisherDeviceId, 'pub-1');
    expect(settings.publisherDeviceName, 'Home PC');
    expect(settings.isActive, isTrue);
  });

  test('enabled without a selected device is not active', () async {
    const storage = AutoConnectStorage(secureStorage);

    await storage.write(const AutoConnectSettings(enabled: true));

    expect((await storage.read()).isActive, isFalse);
  });

  test('clearing the selection removes the stored device', () async {
    const storage = AutoConnectStorage(secureStorage);
    await storage.write(
      const AutoConnectSettings(enabled: true, publisherDeviceId: 'pub-1'),
    );

    await storage.write(AutoConnectSettings.off);

    expect((await storage.read()).publisherDeviceId, isNull);
  });
}
