import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/connection_badge.dart';
import '../../../../core/widgets/sonic_card.dart';

/// A card that lists the two transport layers behind the audio session — the
/// signaling socket and the WebRTC/ICE peer connection — each as a coloured
/// status row.
class IceStatePanel extends StatelessWidget {
  const IceStatePanel({
    required this.signalingLabel,
    required this.signalingStatus,
    required this.iceLabel,
    required this.iceStatus,
    this.pathLabel,
    super.key,
  });

  final String signalingLabel;
  final ConnectionStatus signalingStatus;
  final String iceLabel;
  final ConnectionStatus iceStatus;

  /// The path the audio took (`LAN · P2P direct`, ...); hidden until known.
  final String? pathLabel;

  @override
  Widget build(BuildContext context) {
    return SonicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          _StatusRow(
            icon: Icons.cell_tower_rounded,
            label: 'Signaling',
            value: signalingLabel,
            status: signalingStatus,
          ),
          const SizedBox(height: AppSpacing.sm),
          _StatusRow(
            icon: Icons.hub_outlined,
            label: 'WebRTC / ICE',
            value: iceLabel,
            status: iceStatus,
          ),
          if (pathLabel case final path?) ...[
            const SizedBox(height: AppSpacing.sm),
            _StatusRow(
              icon: Icons.alt_route_rounded,
              label: 'Path',
              value: path,
              status: ConnectionStatus.connected,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.status,
  });

  final IconData icon;
  final String label;
  final String value;
  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$label status: $value',
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: textTheme.bodyMedium)),
          ConnectionBadge(label: value, status: status),
        ],
      ),
    );
  }
}
