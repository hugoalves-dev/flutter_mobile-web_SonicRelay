import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';
import '../../../app/di/lan_providers.dart';
import '../../../core/platform/host_platform.dart';
import '../domain/lan_failure.dart';
import '../domain/lan_pairing_offer.dart';
import '../domain/manual_pairing_code.dart';

enum LanPairingStatus { idle, pairing, paired, failed }

class LanPairingState {
  const LanPairingState({
    this.status = LanPairingStatus.idle,
    this.errorMessage,
    this.pairedName,
  });

  final LanPairingStatus status;
  final String? errorMessage;
  final String? pairedName;

  bool get isBusy => status == LanPairingStatus.pairing;
}

final lanPairingViewModelProvider =
    NotifierProvider<LanPairingViewModel, LanPairingState>(
      LanPairingViewModel.new,
    );

/// Offline pairing with a SonicRelay Desktop (dotnet_SonicRelay#75): from the
/// LAN block of a scanned QR, or from an address plus the typed code for a
/// desktop on another subnet. Also forgets paired desktops.
class LanPairingViewModel extends Notifier<LanPairingState> {
  @override
  LanPairingState build() => const LanPairingState();

  Future<bool> pairOffer(LanPairingOffer offer) =>
      _pair(endpoints: offer.endpoints, offer: offer);

  Future<bool> pairManual(String endpoint, String code) async {
    final address = endpoint.trim();
    if (!isLanEndpoint(address)) {
      state = const LanPairingState(
        status: LanPairingStatus.failed,
        errorMessage:
            'Enter the desktop address as host:port, e.g. 192.168.1.20:47321.',
      );
      return false;
    }
    if (ManualPairingCode.normalize(code) == null) {
      state = const LanPairingState(
        status: LanPairingStatus.failed,
        errorMessage:
            'Enter the 16-character local pairing code shown on the desktop.',
      );
      return false;
    }
    return _pair(endpoints: [address], manualCode: code);
  }

  Future<void> forget(String publisherDeviceId) async {
    await ref.read(trustedPublisherStoreProvider).remove(publisherDeviceId);
    ref.invalidate(trustedPublishersProvider);
  }

  Future<bool> _pair({
    required List<String> endpoints,
    LanPairingOffer? offer,
    String? manualCode,
  }) async {
    state = const LanPairingState(status: LanPairingStatus.pairing);
    final store = ref.read(trustedPublisherStoreProvider);
    try {
      final publisher = await ref
          .read(lanPairingApiProvider)
          .pair(
            endpoints: endpoints,
            offer: offer,
            manualCode: manualCode,
            viewerDeviceId: await store.viewerDeviceId(),
            viewerName: await _deviceName(),
            platform: hostPlatformName,
          );
      await store.save(publisher);
      ref.invalidate(trustedPublishersProvider);
      state = LanPairingState(
        status: LanPairingStatus.paired,
        pairedName: publisher.name,
      );
      return true;
    } on LanFailure catch (failure) {
      state = LanPairingState(
        status: LanPairingStatus.failed,
        errorMessage: '${failure.message} (${failure.code.diagnosticCode})',
      );
      return false;
    }
  }

  Future<String> _deviceName() async {
    try {
      return await ref.read(deviceDisplayNameProvider)() ?? 'SonicRelay phone';
    } on Object {
      return 'SonicRelay phone';
    }
  }
}
