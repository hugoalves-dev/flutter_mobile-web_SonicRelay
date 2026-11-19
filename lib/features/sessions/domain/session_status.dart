enum SessionStatus {
  waiting,
  connecting,
  connected;

  /// Maps a backend session `status` string (`waiting`, `active`, `ended`,
  /// `expired`) to a viewer-facing status. A freshly joined session is either
  /// `waiting` (no publisher yet) or `active` (publisher streaming).
  static SessionStatus fromWire(String value) =>
      value.toLowerCase() == 'active'
      ? SessionStatus.connected
      : SessionStatus.waiting;
}
