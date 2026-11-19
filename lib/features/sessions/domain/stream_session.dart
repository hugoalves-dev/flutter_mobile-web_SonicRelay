import '../../lan/domain/lan_session_target.dart';
import 'session_status.dart';

class StreamSession {
  const StreamSession({
    required this.sessionId,
    required this.signalingUrl,
    this.status = SessionStatus.waiting,
    this.lan,
  });

  final String sessionId;
  final Uri signalingUrl;
  final SessionStatus status;

  /// Set when this session is signaled through a desktop's LAN host instead of
  /// RelayControl (dotnet_SonicRelay#75).
  final LanSessionTarget? lan;

  bool get isLan => lan != null;
}
