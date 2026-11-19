import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/sonic_card.dart';
import '../domain/onboarding_content.dart';

/// The permanent "How to use" reference: the same walkthrough shown during
/// first-use onboarding, reachable afterwards from the pairing screen's "?"
/// button and from Settings, so the desktop-first flow stays explained even
/// once onboarding has been skipped or completed.
class HowToUsePage extends StatelessWidget {
  const HowToUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How to use')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'How to use SonicRelay',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'SonicRelay lets you listen on your phone to audio '
                    'playing on a computer, streamed live over WebRTC.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (var i = 0; i < onboardingSteps.length; i++) ...[
                    _HowToUseStep(index: i + 1, step: onboardingSteps[i]),
                    if (i != onboardingSteps.length - 1)
                      const SizedBox(height: AppSpacing.md),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  SonicCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Troubleshooting',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (final tip in onboardingTroubleshootingTips)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xs,
                            ),
                            child: Text('• $tip'),
                          ),
                      ],
                    ),
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

class _HowToUseStep extends StatelessWidget {
  const _HowToUseStep({required this.index, required this.step});

  final int index;
  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: AppColors.accent,
          child: Text(
            '$index',
            style: const TextStyle(
              color: AppColors.background,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(step.body, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
