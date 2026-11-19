import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/lan_providers.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/diagnostics/sonic_log.dart';
import '../../../core/widgets/sonic_card.dart';
import '../../sessions/presentation/join_session_view_model.dart';
import '../data/lan_discovery_service.dart';
import '../domain/trusted_publisher.dart';

/// Desktops paired over the LAN, offered first on the join page
/// (dotnet_SonicRelay#75). While visible it browses mDNS and announces this
/// phone; "On this network" is only a hint — the pinned TLS handshake decides.
class LanPublishersCard extends ConsumerStatefulWidget {
  const LanPublishersCard({super.key});

  @override
  ConsumerState<LanPublishersCard> createState() => _LanPublishersCardState();
}

class _LanPublishersCardState extends ConsumerState<LanPublishersCard> {
  LanDiscoveryService? _discovery;
  StreamSubscription<List<DiscoveredPublisher>>? _changes;

  @override
  void initState() {
    super.initState();
    unawaited(_startDiscovery());
  }

  Future<void> _startDiscovery() async {
    try {
      final discovery = ref.read(lanDiscoveryServiceProvider);
      _discovery = discovery;
      _changes = discovery.changes.listen((_) {
        if (mounted) setState(() {});
      });
      final viewerId = await ref
          .read(trustedPublisherStoreProvider)
          .viewerDeviceId();
      await discovery.start(viewerHint: lanHint(viewerId));
    } on Object catch (error) {
      sonicLog('LAN', 'discovery not started: $error');
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    unawaited(_discovery?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final publishers = ref.watch(trustedPublishersProvider).value ?? const [];
    final joining = ref.watch(joinSessionViewModelProvider).isJoining;

    return SonicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Desktops on this network', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          if (publishers.isEmpty)
            Text(
              'Pair a desktop by scanning its QR code, or in Settings → Local network.',
              style: theme.textTheme.bodySmall,
            ),
          for (final publisher in publishers)
            ListTile(
              key: Key('lan-publisher-${publisher.publisherDeviceId}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.computer_outlined),
              title: Text(publisher.name),
              subtitle: Text(
                _discovery?.findTrusted(publisher) != null
                    ? 'On this network'
                    : 'Last seen at ${publisher.lastEndpoints.isEmpty ? '—' : publisher.lastEndpoints.first}',
              ),
              trailing: FilledButton(
                onPressed: joining
                    ? null
                    : () => ref
                          .read(joinSessionViewModelProvider.notifier)
                          .joinLan(publisher),
                child: const Text('Listen'),
              ),
            ),
        ],
      ),
    );
  }
}
