import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/env/app_config.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/sonic_button.dart';
import '../../../../core/widgets/sonic_text_field.dart';

/// Lets the user view and change the SonicRelay server URL. Saving persists the
/// URL and rebuilds the HTTP/WebSocket clients so the next request targets it.
class ServerUrlField extends ConsumerStatefulWidget {
  const ServerUrlField({super.key});

  @override
  ConsumerState<ServerUrlField> createState() => _ServerUrlFieldState();
}

class _ServerUrlFieldState extends ConsumerState<ServerUrlField> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(serverUrlProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isValid(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _save() async {
    final url = AppConfig.normalizeServerUrl(_controller.text);
    if (!_isValid(url)) {
      setState(() {
        _error = 'Enter a valid URL, e.g. https://sonicrelay-api.hugodotnet.dev';
      });
      return;
    }
    setState(() => _error = null);
    _controller.text = url;
    await ref.read(serverUrlProvider.notifier).update(url);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Server URL saved.')));
  }

  Future<void> _resetToDefault() async {
    await ref.read(serverUrlProvider.notifier).reset();
    if (!mounted) return;
    _controller.text = ref.read(serverUrlProvider);
    setState(() => _error = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Restored default server.')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        SonicTextField(
          label: 'Server URL',
          controller: _controller,
          keyboardType: TextInputType.url,
          prefixIcon: Icons.dns_outlined,
          errorText: _error,
          hintText: AppConfig.defaultServerUrl,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SonicButton(
                label: 'Save server URL',
                icon: Icons.save_outlined,
                onPressed: _save,
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            IconButton(
              tooltip: 'Restore default',
              onPressed: _resetToDefault,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
          ],
        ),
      ],
    );
  }
}
