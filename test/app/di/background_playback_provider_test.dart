import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/core/storage/background_playback_storage.dart';

class _FakeBackgroundPlaybackStorage extends BackgroundPlaybackStorage {
  _FakeBackgroundPlaybackStorage() : super(const FlutterSecureStorage());

  bool? written;

  @override
  Future<void> write(bool value) async => written = value;
}

void main() {
  test('BackgroundPlaybackNotifier defaults to on and persists changes', () async {
    final storage = _FakeBackgroundPlaybackStorage();
    final container = ProviderContainer(
      overrides: [
        backgroundPlaybackStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(backgroundPlaybackEnabledProvider), isTrue);

    await container.read(backgroundPlaybackEnabledProvider.notifier).set(false);

    expect(container.read(backgroundPlaybackEnabledProvider), isFalse);
    expect(storage.written, isFalse);
  });
}
