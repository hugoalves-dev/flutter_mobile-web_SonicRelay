class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.webSocketBaseUrl});

  /// The default server URL. Can be overridden at build time with
  /// `--dart-define=SONIC_RELAY_API_URL=...` and at runtime by the user
  /// through the in-app server URL field.
  static const defaultServerUrl = String.fromEnvironment(
    'SONIC_RELAY_API_URL',
    defaultValue: 'https://sonicrelay-api.hugodotnet.dev',
  );

  /// Default TURN URI shown on the first launch before the app makes any
  /// network request. Forks can point this at their own relay at build time.
  static const defaultTurnUrl = String.fromEnvironment(
    'SONIC_RELAY_TURN_URL',
    defaultValue: 'turn:sonicrelay-turn.hugodotnet.dev:3478?transport=udp',
  );

  /// The published SonicRelay privacy policy. Google Play requires the policy to
  /// be reachable from inside the app, not only from the store listing, so the
  /// settings screen links here. Overridable at build time for a staging site.
  static const privacyPolicyUrl = String.fromEnvironment(
    'SONIC_RELAY_PRIVACY_POLICY_URL',
    defaultValue: 'https://hugodotnet.dev/sonicrelay/privacy-policy',
  );

  /// The Buy Me a Coffee page that funds this project. SonicRelay runs on
  /// signaling and TURN servers paid for out of pocket, so the app asks for
  /// support instead of charging or shipping ads. Overridable at build time so
  /// a fork can point at its own maintainer.
  static const donationUrl = String.fromEnvironment(
    'SONIC_RELAY_DONATION_URL',
    defaultValue: 'https://www.buymeacoffee.com/vitorhugo1207',
  );

  factory AppConfig.fromEnvironment() =>
      AppConfig.fromServerUrl(defaultServerUrl);

  /// Builds the config from a single user-facing server URL. The WebSocket
  /// base URL is derived from the API URL by swapping the scheme
  /// (`https` -> `wss`, `http` -> `ws`). The host is preserved exactly as
  /// entered (unlike `Uri`, which would lowercase it).
  factory AppConfig.fromServerUrl(String serverUrl) {
    final apiBaseUrl = normalizeServerUrl(serverUrl);
    final String webSocketBaseUrl;
    if (apiBaseUrl.startsWith('https://')) {
      webSocketBaseUrl = 'wss://${apiBaseUrl.substring('https://'.length)}';
    } else if (apiBaseUrl.startsWith('http://')) {
      webSocketBaseUrl = 'ws://${apiBaseUrl.substring('http://'.length)}';
    } else {
      webSocketBaseUrl = 'wss://$apiBaseUrl';
    }
    return AppConfig(
      apiBaseUrl: apiBaseUrl,
      webSocketBaseUrl: webSocketBaseUrl,
    );
  }

  /// Trims surrounding whitespace and removes any trailing slash so URLs are
  /// stored and compared in a consistent form.
  static String normalizeServerUrl(String url) {
    var value = url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  final String apiBaseUrl;
  final String webSocketBaseUrl;

  /// The fixed signaling endpoint (`/ws/signaling`) built from
  /// [webSocketBaseUrl]. The backend returns no signaling URL on join; the
  /// client constructs it here and the signaling client appends the
  /// `sessionId`/`deviceId` query parameters.
  Uri get signalingUri {
    final base = webSocketBaseUrl.endsWith('/')
        ? webSocketBaseUrl.substring(0, webSocketBaseUrl.length - 1)
        : webSocketBaseUrl;
    return Uri.parse('$base/ws/signaling');
  }
}
