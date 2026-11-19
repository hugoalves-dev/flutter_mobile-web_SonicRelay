/// Which signaling transports a session may use (dotnet_SonicRelay#75). Independent of
/// [RelayModes], which only governs TURN for cloud-signaled sessions. The literals match the
/// desktop's `ConnectivityModes` string for string; they are local preferences and never reach
/// the backend.
class ConnectivityModes {
  const ConnectivityModes._();

  /// A trusted publisher reachable on the LAN is tried first; RelayControl otherwise.
  static const auto = 'auto';

  /// Never contacts RelayControl, STUN or TURN.
  static const lanOnly = 'lanOnly';

  /// Today's behaviour: RelayControl only.
  static const cloudOnly = 'cloudOnly';

  static bool isValid(String? value) =>
      value == auto || value == lanOnly || value == cloudOnly;

  static bool allowsLan(String mode) => mode == auto || mode == lanOnly;

  static bool allowsCloud(String mode) => mode == auto || mode == cloudOnly;
}
