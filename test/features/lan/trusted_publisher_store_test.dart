import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/features/lan/data/trusted_publisher_store.dart';
import 'package:sonic_relay/features/lan/domain/trusted_publisher.dart';

void main() {
  const storage = FlutterSecureStorage();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  TrustedPublisher publisher({
    String id = '8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e',
  }) => TrustedPublisher(
    publisherDeviceId: id,
    name: 'DESKTOP-01',
    pin: 'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E',
    credential: 'secret-credential',
    lastEndpoints: const ['192.168.1.20:47321'],
    lastSeenAt: DateTime.utc(2026, 11, 17),
  );

  test('store round trip', () async {
    const store = TrustedPublisherStore(storage);

    await store.save(publisher());

    final listed = await store.list();
    expect(listed.single.credential, 'secret-credential');
    expect(listed.single.lastEndpoints, ['192.168.1.20:47321']);
    expect(listed.single.hint, hasLength(6));
  });

  test('saving the same publisher replaces it', () async {
    const store = TrustedPublisherStore(storage);
    await store.save(publisher());

    await store.save(publisher().copyWith(credential: 'renewed'));

    expect((await store.list()).single.credential, 'renewed');
  });

  test('remove forgets credential', () async {
    const store = TrustedPublisherStore(storage);
    await store.save(publisher());

    await store.remove('8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e');

    expect(await store.list(), isEmpty);
  });

  test(
    'updateEndpoints keeps the newest first without duplicates, max 4',
    () async {
      const store = TrustedPublisherStore(storage);
      await store.save(publisher());

      await store.updateEndpoints('8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e', [
        '10.0.0.5:47321',
        '192.168.1.20:47321',
        'a.local:1',
        'b.local:1',
        'c.local:1',
      ]);

      final endpoints = (await store.list()).single.lastEndpoints;
      expect(endpoints.first, '10.0.0.5:47321');
      expect(endpoints, hasLength(4));
      expect(endpoints.toSet(), hasLength(4));
    },
  );

  test('a corrupt store reads as empty', () async {
    await storage.write(key: 'lan.trustedPublishers', value: '{oops');

    expect(await const TrustedPublisherStore(storage).list(), isEmpty);
  });

  test('viewer device id is a stable uuid', () async {
    const store = TrustedPublisherStore(storage);

    final first = await store.viewerDeviceId();
    final second = await store.viewerDeviceId();

    expect(first, second);
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(first),
      isTrue,
    );
  });

  test('hint matches the desktop formula', () {
    // sha256("8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e")[0..6] — same as LanIdentity.ComputeHint.
    expect(lanHint('8f14e45f-ceea-467e-9b4a-1f3a2b6c7d8e'), hasLength(6));
    expect(lanHint('a'), 'ca9781');
  });
}
