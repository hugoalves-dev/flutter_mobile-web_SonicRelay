/// The viewer's auto-connect preference: one paired publisher whose sessions are joined
/// without a code while the join page is open (issue #65). Off by default.
class AutoConnectSettings {
  const AutoConnectSettings({
    this.enabled = false,
    this.publisherDeviceId,
    this.publisherDeviceName,
  });

  static const off = AutoConnectSettings();

  final bool enabled;
  final String? publisherDeviceId;

  /// Remembered for display only, so status text can name the device before discovery
  /// returns it (or after its pairing was revoked).
  final String? publisherDeviceName;

  /// Whether auto-connect should actually act: switched on and a device chosen.
  bool get isActive => enabled && publisherDeviceId != null;

  /// A human label for the selected device, falling back to its id.
  String? get displayName {
    final name = publisherDeviceName;
    return name != null && name.trim().isNotEmpty ? name : publisherDeviceId;
  }

  AutoConnectSettings copyWith({
    bool? enabled,
    String? publisherDeviceId,
    String? publisherDeviceName,
  }) => AutoConnectSettings(
    enabled: enabled ?? this.enabled,
    publisherDeviceId: publisherDeviceId ?? this.publisherDeviceId,
    publisherDeviceName: publisherDeviceName ?? this.publisherDeviceName,
  );
}
