import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pairing/domain/device_pairing.dart';
import '../../pairing/presentation/pairing_view_model.dart';

/// The public radio room's virtual publisher (`PublicRoomSeeder.VirtualPublisherDeviceId`
/// in dotnet_SonicRelay). Every device is auto-paired with it, but it is not a PC the
/// user owns, so it is never offered as an auto-connect target.
const publicRadioPublisherDeviceId = '0b1e5a7a-0000-4000-8000-000000000001';

/// Active pairings in which [currentDeviceId] is the viewer, excluding Public Radio.
List<DevicePairing> selectPairedPublishers(
  List<DevicePairing> pairings, {
  required String currentDeviceId,
}) => pairings
    .where(
      (p) =>
          p.status == 'active' &&
          p.viewerDeviceId == currentDeviceId &&
          p.publisherDeviceId != publicRadioPublisherDeviceId,
    )
    .toList();

/// Publishers this device can choose for auto-connect. Loaded while Settings is open.
final pairedPublishersProvider =
    FutureProvider.autoDispose<List<DevicePairing>>((ref) async {
      final deviceId = await ref.read(currentPairingDeviceIdProvider)();
      if (deviceId == null) return const [];
      final pairings = await ref.read(pairingRepositoryProvider).list(deviceId);
      return selectPairedPublishers(pairings, currentDeviceId: deviceId);
    });
