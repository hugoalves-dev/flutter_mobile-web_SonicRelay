import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/widgets/sonic_card.dart';
import '../join_session_view_model.dart';

/// The always-on public "radio" room, offered as a code-free, no-pairing-required join —
/// deliberately a separate card from [DiscoveredSessionsList], which only ever shows sessions
/// of publishers this device is already paired with. Renders nothing while loading, on a
/// fetch failure, or when the room is disabled, mirroring [DiscoveredSessionsList]'s silence
/// in those same cases.
class PublicRoomCard extends ConsumerWidget {
  const PublicRoomCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publicRoom = ref.watch(publicRoomProvider);
    return publicRoom.when(
      data: (info) {
        if (!info.enabled || info.sessionId == null) return const SizedBox.shrink();
        return SonicCard(
          padding: EdgeInsets.zero,
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: Icon(
                Icons.radio_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Public Radio'),
              subtitle: Text('Tap to listen · up to ${info.maxViewers} listeners'),
              onTap: () => ref
                  .read(joinSessionViewModelProvider.notifier)
                  .joinPublicRoom(info.sessionId!),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
