import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';
import '../../../app/theme/app_spacing.dart';
import 'auto_connect_controller.dart';

/// Lives on the join page and is the only thing that drives auto-connect: it feeds
/// discovery results to [AutoConnectController], refreshes discovery on app resume and
/// network recovery, and shows the auto-connect status. Being on the join page is what
/// keeps auto-connect from ever replacing a session that is already playing.
class AutoConnectBanner extends ConsumerStatefulWidget {
  const AutoConnectBanner({super.key});

  @override
  ConsumerState<AutoConnectBanner> createState() => _AutoConnectBannerState();
}

class _AutoConnectBannerState extends ConsumerState<AutoConnectBanner>
    with WidgetsBindingObserver {
  late final AutoConnectController _controller;
  StreamSubscription<bool>? _network;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(autoConnectControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(discoverableSessionsProvider, (_, next) {
      if (next case AsyncData(:final value)) {
        unawaited(_controller.onDiscovery(value));
      }
    }, fireImmediately: true);
    _network = ref.read(networkMonitorProvider).onChanged.listen((online) {
      if (online) _refreshDiscovery();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_network?.cancel());
    _controller.cancelPending();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDiscovery();
  }

  void _refreshDiscovery() {
    if (mounted) ref.invalidate(discoverableSessionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(autoConnectControllerProvider);
    if (status.phase == AutoConnectPhase.off) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final device = status.deviceName ?? 'the selected device';
    final (icon, title) = switch (status.phase) {
      AutoConnectPhase.connecting => (
        Icons.sync_rounded,
        'Connecting to $device…',
      ),
      AutoConnectPhase.paused => (
        Icons.pause_circle_outline_rounded,
        'Auto-connect paused (you left the session)',
      ),
      AutoConnectPhase.error => (
        Icons.error_outline_rounded,
        status.message ?? 'Auto-connect stopped.',
      ),
      _ => (Icons.autorenew_rounded, 'Auto-connect: waiting for $device'),
    };
    final detail = status.phase == AutoConnectPhase.waiting
        ? status.message
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (detail != null)
                  Text(detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (status.phase == AutoConnectPhase.paused)
            TextButton(
              onPressed: _controller.resume,
              child: const Text('Resume'),
            ),
        ],
      ),
    );
  }
}
