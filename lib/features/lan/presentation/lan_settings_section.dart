import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/lan_providers.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/webrtc/connectivity_modes.dart';
import 'lan_pairing_view_model.dart';

/// Settings → Local network (dotnet_SonicRelay#75): the connectivity mode,
/// pairing with a desktop by address + typed code (for another subnet), and
/// the desktops paired on the LAN. Not shown on the web, where LAN is
/// unsupported.
class LanSettingsSection extends ConsumerStatefulWidget {
  const LanSettingsSection({super.key});

  @override
  ConsumerState<LanSettingsSection> createState() => _LanSettingsSectionState();
}

class _LanSettingsSectionState extends ConsumerState<LanSettingsSection> {
  final _address = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _setMode(String? mode) async {
    if (mode == null) return;
    try {
      await ref.read(connectivityModeProvider.notifier).set(mode);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save the connectivity mode. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _pair() async {
    final ok = await ref
        .read(lanPairingViewModelProvider.notifier)
        .pairManual(_address.text, _code.text);
    if (ok) _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(lanPlatformProvider).isSupported) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final mode = ref.watch(connectivityModeProvider);
    final pairing = ref.watch(lanPairingViewModelProvider);
    final publishers = ref.watch(trustedPublishersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: AppSpacing.xl),
        Text('Local network', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Listen to a paired desktop on the same network, even without internet.',
          style: theme.textTheme.bodySmall,
        ),
        Material(
          color: Colors.transparent,
          child: RadioGroup<String>(
            groupValue: mode,
            onChanged: _setMode,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RadioListTile<String>(
                  key: Key('connectivity-auto'),
                  contentPadding: EdgeInsets.zero,
                  value: ConnectivityModes.auto,
                  title: Text('Automatic'),
                  subtitle: Text(
                    'Local network first for paired desktops; RelayControl otherwise.',
                  ),
                ),
                RadioListTile<String>(
                  key: Key('connectivity-lanOnly'),
                  contentPadding: EdgeInsets.zero,
                  value: ConnectivityModes.lanOnly,
                  title: Text('Local network only'),
                  subtitle: Text('Never contacts RelayControl, STUN or TURN.'),
                ),
                RadioListTile<String>(
                  key: Key('connectivity-cloudOnly'),
                  contentPadding: EdgeInsets.zero,
                  value: ConnectivityModes.cloudOnly,
                  title: Text('RelayControl only'),
                  subtitle: Text(
                    'The previous behaviour; no local network discovery.',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (ConnectivityModes.allowsLan(mode)) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Pair over the local network',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'For a desktop on another subnet: type the address and the local pairing code shown on '
            'the desktop (Pairing → Pair over the local network).',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('lan-address'),
            controller: _address,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Desktop address',
              hintText: '192.168.1.20:47321',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('lan-code'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Local pairing code',
              hintText: 'XXXX-XXXX-XXXX-XXXX',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const Key('lan-pair'),
              onPressed: pairing.isBusy ? null : _pair,
              child: Text(pairing.isBusy ? 'Pairing…' : 'Pair'),
            ),
          ),
          if (pairing.errorMessage case final message?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (pairing.status == LanPairingStatus.paired)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Paired with ${pairing.pairedName}.'),
            ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Desktops paired on this network',
            style: theme.textTheme.titleSmall,
          ),
          ...switch (publishers) {
            AsyncData(value: final list) when list.isEmpty => [
              Text('None yet.', style: theme.textTheme.bodySmall),
            ],
            AsyncData(value: final list) => [
              for (final publisher in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.computer_outlined),
                  title: Text(publisher.name),
                  subtitle: Text(publisher.lastEndpoints.join(', ')),
                  trailing: TextButton(
                    onPressed: () => ref
                        .read(lanPairingViewModelProvider.notifier)
                        .forget(publisher.publisherDeviceId),
                    child: const Text('Forget'),
                  ),
                ),
            ],
            _ => const [SizedBox.shrink()],
          },
        ],
      ],
    );
  }
}
