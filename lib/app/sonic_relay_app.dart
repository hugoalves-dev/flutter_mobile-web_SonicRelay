import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/diagnostics/sonic_log.dart';
import '../core/widgets/sonic_text_field.dart';
import '../features/listener/presentation/listener_view_model.dart';
import 'di/app_providers.dart';
import 'env/app_config.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class SonicRelayApp extends ConsumerStatefulWidget {
  const SonicRelayApp({super.key});

  @override
  ConsumerState<SonicRelayApp> createState() => _SonicRelayAppState();
}

class _SonicRelayAppState extends ConsumerState<SonicRelayApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Send the tagged signaling/WebRTC/background lines to the log the user can
    // export, not just to logcat — which is out of reach on the phone that has
    // actually been streaming unattended.
    final diagnosticLog = ref.read(diagnosticLogProvider);
    setSonicLogSink(
      (tag, message) => unawaited(diagnosticLog.write(tag, message)),
    );
  }

  @override
  void dispose() {
    setSonicLogSink(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive/hidden/paused/detached must only ever update UI/service
    // visibility (via the lifecycle controller below), never be treated as an
    // explicit leave — only a user-initiated Stop/Leave, logout, or terminal
    // connection state closes the active stream.
    if (!ref.read(initialServerSetupCompletedProvider)) return;
    unawaited(
      ref
          .read(diagnosticLogProvider)
          .write('Lifecycle', 'app lifecycle -> $state'),
    );
    final inForeground = state == AppLifecycleState.resumed;
    ref
        .read(streamLifecycleControllerProvider)
        .onAppForegroundChanged(inForeground);
    if (inForeground) {
      // Coming back to the foreground is the one moment we can be sure the
      // process is running, so it is the moment to re-check a connection whose
      // recovery may not have survived being backgrounded: Android freezes a
      // process with no foreground service, and a pending reconnect `Timer`
      // does not come back with it. A real outage ended exactly there — the
      // socket's last retry, then nothing across both a network change and a
      // foreground resume, until the user restarted the session by hand.
      ref.read(listenerViewModelProvider.notifier).resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialSetupCompleted = ref.watch(
      initialServerSetupCompletedProvider,
    );
    if (!initialSetupCompleted) {
      return MaterialApp(
        title: 'SonicRelay',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ref.watch(themeModeProvider),
        home: _InitialServerSetupPage(onComplete: () => setState(() {})),
      );
    }
    ref.watch(deviceReadinessProvider);
    return MaterialApp.router(
      title: 'SonicRelay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}

class _InitialServerSetupPage extends ConsumerStatefulWidget {
  const _InitialServerSetupPage({required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<_InitialServerSetupPage> createState() =>
      _InitialServerSetupPageState();
}

class _InitialServerSetupPageState
    extends ConsumerState<_InitialServerSetupPage> {
  late final TextEditingController _apiController;
  late final TextEditingController _turnController;
  String? _apiError;
  String? _turnError;
  String? _saveError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _apiController = TextEditingController(text: ref.read(serverUrlProvider));
    _turnController = TextEditingController(
      text: ref.read(coturnOverrideProvider) ?? AppConfig.defaultTurnUrl,
    );
  }

  @override
  void dispose() {
    _apiController.dispose();
    _turnController.dispose();
    super.dispose();
  }

  bool _isValidApiUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  bool _isValidTurnUrl(String value) =>
      RegExp(r'^turns?:[^\s:]+').hasMatch(value.trim());

  Future<void> _save() async {
    final apiUrl = AppConfig.normalizeServerUrl(_apiController.text);
    final turnUrl = _turnController.text.trim();
    setState(() {
      _apiError = _isValidApiUrl(apiUrl)
          ? null
          : 'Enter a valid HTTP or HTTPS URL.';
      _turnError = _isValidTurnUrl(turnUrl)
          ? null
          : 'Enter a valid TURN URL, e.g. turn:relay.example.com:3478';
      _saveError = null;
    });
    if (_apiError != null || _turnError != null) return;

    setState(() => _saving = true);
    try {
      await ref.read(serverUrlProvider.notifier).update(apiUrl);
      await ref.read(coturnOverrideProvider.notifier).set(turnUrl);
      await ref.read(initialServerSetupCompletedProvider.notifier).complete();
      if (!mounted) return;
      widget.onComplete();
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError = 'Unable to save these addresses. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AlertDialog(
                title: const Text('Server setup'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Review the API and TURN server addresses. SonicRelay will '
                      'connect only after you save them.',
                    ),
                    const SizedBox(height: 16),
                    SonicTextField(
                      label: 'API URL',
                      controller: _apiController,
                      keyboardType: TextInputType.url,
                      prefixIcon: Icons.dns_outlined,
                      errorText: _apiError,
                    ),
                    const SizedBox(height: 12),
                    SonicTextField(
                      label: 'COTURN URL',
                      controller: _turnController,
                      keyboardType: TextInputType.url,
                      prefixIcon: Icons.sensors_outlined,
                      errorText: _turnError,
                    ),
                    if (_saveError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _saveError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save and continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
