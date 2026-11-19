import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/features/sessions/data/dto/discoverable_session.dart';

void main() {
  test('parses the publisher device id and creation time', () {
    final session = DiscoverableSession.fromJson({
      'sessionId': 's1',
      'publisherDeviceId': 'pub-1',
      'publisherDeviceName': 'Home PC',
      'status': 'waiting',
      'viewerCount': 0,
      'maxViewers': 2,
      'createdAt': '2026-11-17T10:00:00Z',
    });

    expect(session.publisherDeviceId, 'pub-1');
    expect(session.createdAt, DateTime.utc(2026, 11, 17, 10));
  });

  test('an older backend without the new fields never matches a device', () {
    final session = DiscoverableSession.fromJson({'sessionId': 's1'});

    expect(session.publisherDeviceId, '');
    expect(session.createdAt, isNull);
  });
}
