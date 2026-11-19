/// A session of a publisher this device is actively paired with, offered for a code-free
/// join. The backend deliberately never includes the join code here — it is a separate
/// short-lived secret, and discovery must not become a way to read it.
class DiscoverableSession {
  const DiscoverableSession({
    required this.sessionId,
    required this.publisherDeviceName,
    required this.status,
    required this.viewerCount,
    required this.maxViewers,
    this.publisherDeviceId = '',
    this.createdAt,
  });

  factory DiscoverableSession.fromJson(Map<String, Object?> json) =>
      DiscoverableSession(
        sessionId: json['sessionId'] as String? ?? '',
        publisherDeviceId: json['publisherDeviceId'] as String? ?? '',
        publisherDeviceName: json['publisherDeviceName'] as String? ?? '',
        status: json['status'] as String? ?? 'waiting',
        viewerCount: (json['viewerCount'] as num?)?.toInt() ?? 0,
        maxViewers: (json['maxViewers'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );

  final String sessionId;

  /// The publisher's durable device id. Empty from a backend that predates it, which
  /// simply never matches an auto-connect selection.
  final String publisherDeviceId;
  final DateTime? createdAt;
  final String publisherDeviceName;
  final String status;
  final int viewerCount;
  final int maxViewers;

  bool get isFull => maxViewers > 0 && viewerCount >= maxViewers;
}
