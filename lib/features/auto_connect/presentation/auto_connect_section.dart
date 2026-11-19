import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pairing/domain/device_pairing.dart';
import '../domain/auto_connect_settings.dart';
import 'auto_connect_settings_notifier.dart';
import 'paired_publishers_provider.dart';

/// Settings → Auto-connect: one global switch plus the single paired publisher to join
/// automatically (issue #65). Off by default.
class AutoConnectSection extends ConsumerStatefulWidget {
  const AutoConnectSection({super.key});

  @override
  ConsumerState<AutoConnectSection> createState() => _AutoConnectSectionState();
}

class _AutoConnectSectionState extends ConsumerState<AutoConnectSection> {
  bool _needsDevice = false;

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(autoConnectSettingsProvider).value ?? AutoConnectSettings.off;
    final publishers = ref.watch(pairedPublishersProvider);
    final notifier = ref.read(autoConnectSettingsProvider.notifier);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.isActive,
          title: const Text('Automatically connect to selected device'),
          subtitle: const Text(
            'Joins the chosen PC without a code when it is streaming and '
            'this screen is open.',
          ),
          onChanged: (value) {
            if (value && settings.publisherDeviceId == null) {
              setState(() => _needsDevice = true);
              return;
            }
            setState(() => _needsDevice = false);
            notifier.setEnabled(value);
          },
        ),
        if (_needsDevice)
          Text(
            'Choose a device first.',
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        switch (publishers) {
          AsyncData(:final value) => _PublisherList(
            publishers: value,
            selectedId: settings.publisherDeviceId,
            onSelected: (pairing) {
              setState(() => _needsDevice = false);
              notifier.select(pairing.publisherDeviceId, _label(pairing));
            },
          ),
          AsyncError() => Text(
            'Could not load paired devices.',
            style: textTheme.bodySmall,
          ),
          _ => const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }

  static String _label(DevicePairing pairing) => pairing.hasPublisherDeviceName
      ? pairing.publisherDeviceName!
      : pairing.publisherDeviceId;
}

class _PublisherList extends StatelessWidget {
  const _PublisherList({
    required this.publishers,
    required this.selectedId,
    required this.onSelected,
  });

  final List<DevicePairing> publishers;
  final String? selectedId;
  final ValueChanged<DevicePairing> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (publishers.isEmpty) {
      return Text(
        'Pair with a PC to use auto-connect.',
        style: textTheme.bodySmall,
      );
    }
    final revoked =
        selectedId != null &&
        publishers.every((p) => p.publisherDeviceId != selectedId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (revoked)
          Text(
            'Pairing revoked — choose another device',
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        Material(
          color: Colors.transparent,
          child: RadioGroup<String>(
            groupValue: selectedId,
            onChanged: (id) => onSelected(
              publishers.firstWhere((p) => p.publisherDeviceId == id),
            ),
            child: Column(
              children: [
                for (final pairing in publishers)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: pairing.publisherDeviceId,
                    title: Text(_AutoConnectSectionState._label(pairing)),
                    subtitle: Text(pairing.publisherDeviceId),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
