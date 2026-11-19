/// The public "radio" room's current availability. Discovered through a code-free,
/// auto-pairing endpoint that is separate from [DiscoverableSession]'s list: that list only
/// ever contains sessions of publishers this device is already paired with, while the public
/// room needs no prior pairing at all — fetching this info is what creates the pairing,
/// server-side, as a side effect. [sessionId] is null whenever [enabled] is false.
class PublicRoomInfo {
  const PublicRoomInfo({
    required this.enabled,
    required this.sessionId,
    required this.maxViewers,
  });

  const PublicRoomInfo.disabled() : enabled = false, sessionId = null, maxViewers = 0;

  factory PublicRoomInfo.fromJson(Map<String, Object?> json) => PublicRoomInfo(
    enabled: json['enabled'] as bool? ?? false,
    sessionId: json['sessionId'] as String?,
    maxViewers: (json['maxViewers'] as num?)?.toInt() ?? 0,
  );

  final bool enabled;
  final String? sessionId;
  final int maxViewers;
}
