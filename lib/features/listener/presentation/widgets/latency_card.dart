import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/sonic_colors.dart';
import '../../../../core/webrtc/rtc_peer_connection_factory.dart';
import '../../../../core/widgets/sonic_card.dart';

/// Shows the live quality metrics for the session: estimated round-trip time,
/// inbound jitter, recent packet loss, and the transport mode
/// (direct/relay/unknown). Any metric that is not yet available renders as
/// "—".
class LatencyCard extends StatelessWidget {
  const LatencyCard({
    required this.rttMs,
    required this.jitterMs,
    required this.transport,
    this.packetLossPercent,
    super.key,
  });

  final double? rttMs;
  final double? jitterMs;
  final RtcTransportMode transport;

  /// Packet loss over the last stats interval, as a percentage.
  final double? packetLossPercent;

  @override
  Widget build(BuildContext context) {
    return SonicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Quality',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _TransportChip(transport: transport),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Latency',
                  value: _formatMs(rttMs),
                  icon: Icons.speed_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Metric(
                  label: 'Jitter',
                  value: _formatMs(jitterMs),
                  icon: Icons.show_chart_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Metric(
                  label: 'Loss',
                  value: _formatPercent(packetLossPercent),
                  icon: Icons.signal_cellular_connected_no_internet_0_bar_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatMs(double? value) {
    if (value == null) return '—';
    return '${value.round()} ms';
  }

  static String _formatPercent(double? value) {
    if (value == null) return '—';
    return '${value.toStringAsFixed(1)}%';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(label, style: textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _TransportChip extends StatelessWidget {
  const _TransportChip({required this.transport});

  final RtcTransportMode transport;

  @override
  Widget build(BuildContext context) {
    final sonicColors = context.sonicColors;
    final (label, color) = switch (transport) {
      RtcTransportMode.direct => ('Direct', sonicColors.success),
      RtcTransportMode.relay => ('Relay', sonicColors.warning),
      RtcTransportMode.unknown => (
        'Unknown',
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };
    return Semantics(
      label: 'Transport mode: $label',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
