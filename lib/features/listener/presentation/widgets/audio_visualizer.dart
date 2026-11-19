import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/sonic_colors.dart';

/// An equalizer-style visualizer for the live audio signal. The bars animate
/// while [active]; otherwise they settle into a dim, static preview.
class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({required this.active, super.key});

  final bool active;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  static const _barCount = 9;
  static const _baseHeights = [0.32, 0.55, 0.8, 0.46, 0.92, 0.65, 0.38, 0.74, 0.5];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Live signal', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.active ? 'Receiving remote audio' : 'Visualizer preview',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        ExcludeSemantics(
          child: Opacity(
            opacity: widget.active ? 1 : 0.4,
            child: SizedBox(
              height: 96,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < _barCount; i++)
                      Expanded(child: _bar(context, i)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bar(BuildContext context, int index) {
    final base = _baseHeights[index];
    double factor = 1;
    if (widget.active) {
      // Offset each bar's phase so they don't pulse in unison.
      final phase = _controller.value * 2 * math.pi + index * 0.7;
      factor = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(phase));
    }
    return Container(
      height: 96 * base * factor,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Theme.of(context).colorScheme.primary,
            context.sonicColors.relay,
          ],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
