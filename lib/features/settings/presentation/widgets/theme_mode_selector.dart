import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';

/// Lets the viewer pick System, Light, or Dark appearance. Local-only and
/// applied immediately — see [themeModeProvider].
class ThemeModeSelector extends ConsumerWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    Future<void> select(ThemeMode? mode) async {
      if (mode == null) return;
      try {
        await ref.read(themeModeProvider.notifier).set(mode);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not save the appearance setting. Please try again.'),
            ),
          );
      }
    }

    return RadioGroup<ThemeMode>(
      groupValue: themeMode,
      onChanged: select,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioListTile<ThemeMode>(
            contentPadding: EdgeInsets.zero,
            value: ThemeMode.system,
            title: Text('System'),
            subtitle: Text("Match this device's appearance setting."),
          ),
          RadioListTile<ThemeMode>(
            contentPadding: EdgeInsets.zero,
            value: ThemeMode.light,
            title: Text('Light'),
          ),
          RadioListTile<ThemeMode>(
            contentPadding: EdgeInsets.zero,
            value: ThemeMode.dark,
            title: Text('Dark'),
          ),
        ],
      ),
    );
  }
}
