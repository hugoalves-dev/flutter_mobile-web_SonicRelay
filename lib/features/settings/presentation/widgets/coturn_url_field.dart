import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/sonic_button.dart';
import '../../../../core/widgets/sonic_text_field.dart';

/// A TURN URI has the form `turn:host[:port][?transport=...]` (or `turns:` for the TLS
/// variant) — not a `Uri`-parseable http(s) URL, so this is a deliberately minimal sanity
/// check (scheme + non-empty host) rather than a full TURN URI grammar validator.
final _turnUrlPattern = RegExp(r'^turns?:[^\s:]+');

/// Lets the user set a local override for the coturn (TURN) server URL, replacing the one the
/// backend hands out for this device only. Unlike the API server URL, the field starts blank
/// and is never pre-filled with the backend's value — the deployment's relay host is not
/// disclosed through this UI, and blank means "use whatever the server sends".
class CoturnUrlField extends ConsumerStatefulWidget {
  const CoturnUrlField({super.key});

  @override
  ConsumerState<CoturnUrlField> createState() => _CoturnUrlFieldState();
}

class _CoturnUrlFieldState extends ConsumerState<CoturnUrlField> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(coturnOverrideProvider) ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isValid(String url) => _turnUrlPattern.hasMatch(url);

  Future<void> _save() async {
    final url = _controller.text.trim();
    if (url.isNotEmpty && !_isValid(url)) {
      setState(() {
        _error = 'Enter a valid TURN URL, e.g. turn:your-coturn-server.example.com:3478';
      });
      return;
    }
    await ref.read(coturnOverrideProvider.notifier).set(url);
    // Share the override with paired devices through the backend. Deliberately
    // not awaited: the local save is what the user is confirming, and the
    // best-effort push must not block the UI on a slow or offline backend.
    unawaited(ref.read(relaySettingsSyncProvider).pushCoturnUrl(url));
    if (!mounted) return;
    setState(() => _error = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(url.isEmpty ? 'Using the server relay.' : 'Coturn URL saved.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    // A pull from the backend (another paired device changed the override) must
    // reach the visible text field, not just the provider.
    ref.listen<String?>(coturnOverrideProvider, (_, next) {
      final value = next ?? '';
      if (_controller.text.trim() != value) _controller.text = value;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        SonicTextField(
          label: 'Coturn URL',
          controller: _controller,
          keyboardType: TextInputType.url,
          prefixIcon: Icons.dns_outlined,
          errorText: _error,
          hintText: 'turn:your-coturn-server.example.com:3478',
        ),
        const SizedBox(height: AppSpacing.md),
        SonicButton(label: 'Save coturn URL', icon: Icons.save_outlined, onPressed: _save),
      ],
    );
  }
}
