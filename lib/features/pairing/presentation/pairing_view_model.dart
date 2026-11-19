import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';
import '../../../app/di/lan_providers.dart';
import '../../../core/webrtc/connectivity_modes.dart';
import '../../lan/presentation/lan_pairing_view_model.dart';
import '../data/pairing_repository.dart';
import '../domain/device_pairing.dart';
import '../domain/pairing_challenge_payload.dart';
import '../domain/pairing_payload.dart';

export '../../../app/di/app_providers.dart' show pairingRepositoryProvider;

enum PairingStatus { idle, loading, submitting, paired, failed }

class PairingState {
  const PairingState({
    this.challengeId = '',
    this.pairingCode = '',
    this.status = PairingStatus.idle,
    this.pairings = const [],
    this.revokingPairingIds = const {},
    this.errorMessage,
  });

  final String challengeId;
  final String pairingCode;
  final PairingStatus status;
  final List<DevicePairing> pairings;
  final Set<String> revokingPairingIds;
  final String? errorMessage;

  bool get isBusy =>
      status == PairingStatus.loading || status == PairingStatus.submitting;
}

typedef CurrentPairingDeviceIdLoader = Future<String?> Function();

final currentPairingDeviceIdProvider = Provider<CurrentPairingDeviceIdLoader>((
  ref,
) {
  final identitySession = ref.watch(deviceIdentitySessionProvider);
  final credentialStorage = ref.watch(deviceCredentialStorageProvider);
  return () async {
    await identitySession.accessToken();
    return (await credentialStorage.read())?.deviceId;
  };
});

final pairingViewModelProvider =
    NotifierProvider<PairingViewModel, PairingState>(PairingViewModel.new);

class PairingViewModel extends Notifier<PairingState> {
  late final PairingRepository _repository;
  late final CurrentPairingDeviceIdLoader _currentDeviceId;
  bool _scanSubmissionInFlight = false;

  @override
  PairingState build() {
    _repository = ref.watch(pairingRepositoryProvider);
    _currentDeviceId = ref.watch(currentPairingDeviceIdProvider);
    return const PairingState();
  }

  void updateChallengeId(String value) {
    state = PairingState(
      challengeId: value.trim(),
      pairingCode: state.pairingCode,
      pairings: state.pairings,
      revokingPairingIds: state.revokingPairingIds,
    );
  }

  void updatePairingCode(String value) {
    state = PairingState(
      challengeId: state.challengeId,
      pairingCode: value.trim().toUpperCase(),
      pairings: state.pairings,
      revokingPairingIds: state.revokingPairingIds,
    );
  }

  Future<void> completeManual() async {
    PairingChallengePayload payload;
    try {
      payload = PairingChallengePayload.parse(
        jsonEncode({
          'challengeId': state.challengeId,
          'code': state.pairingCode,
        }),
      );
    } on FormatException {
      state = PairingState(
        challengeId: state.challengeId,
        pairingCode: state.pairingCode,
        pairings: state.pairings,
        revokingPairingIds: state.revokingPairingIds,
        status: PairingStatus.failed,
        errorMessage: 'Enter a valid challenge ID and pairing code.',
      );
      return;
    }
    await _complete(payload);
  }

  Future<bool> completeScanned(String raw) async {
    if (_scanSubmissionInFlight) return false;

    PairingPayload payload;
    try {
      payload = PairingPayload.parse(raw);
    } on FormatException {
      state = PairingState(
        challengeId: state.challengeId,
        pairingCode: state.pairingCode,
        pairings: state.pairings,
        revokingPairingIds: state.revokingPairingIds,
        status: PairingStatus.failed,
        errorMessage: 'Scan a valid SonicRelay pairing QR code.',
      );
      return false;
    }

    _scanSubmissionInFlight = true;
    try {
      return await _completeScannedPayload(payload);
    } finally {
      _scanSubmissionInFlight = false;
    }
  }

  /// A version-2 QR can pair over the LAN, the cloud, or both
  /// (dotnet_SonicRelay#75). Each block runs only when the connectivity mode
  /// allows its transport; the scan succeeds if any block paired.
  Future<bool> _completeScannedPayload(PairingPayload payload) async {
    final mode = ref.read(connectivityModeProvider);
    var lanPaired = false;
    String? lanError;
    final lan = payload.lan;
    if (lan != null && ref.read(lanEnabledProvider)) {
      final lanPairing = ref.read(lanPairingViewModelProvider.notifier);
      lanPaired = await lanPairing.pairOffer(lan);
      if (!lanPaired) {
        lanError = ref.read(lanPairingViewModelProvider).errorMessage;
      }
    }

    final cloud = payload.cloud;
    if (cloud != null && ConnectivityModes.allowsCloud(mode)) {
      final cloudPaired = await _complete(cloud);
      if (cloudPaired || !lanPaired) return cloudPaired || lanPaired;
    }

    if (lanPaired) {
      state = PairingState(
        status: PairingStatus.paired,
        pairings: state.pairings,
        revokingPairingIds: state.revokingPairingIds,
      );
      return true;
    }
    _setFailure(
      lanError ?? 'This QR code cannot pair in the current connectivity mode.',
    );
    return false;
  }

  Future<void> load(String deviceId) async {
    state = PairingState(
      challengeId: state.challengeId,
      pairingCode: state.pairingCode,
      pairings: state.pairings,
      revokingPairingIds: state.revokingPairingIds,
      status: PairingStatus.loading,
    );
    try {
      final pairings = await _repository.list(deviceId);
      state = PairingState(
        pairings: pairings,
        revokingPairingIds: state.revokingPairingIds,
      );
    } on PairingFailure catch (error) {
      _setFailure(error.message);
    } catch (_) {
      _setFailure('Unable to load device pairings. Please retry.');
    }
  }

  Future<void> loadCurrentPairings() async {
    try {
      final deviceId = await _currentDeviceId();
      if (deviceId != null) await load(deviceId);
    } catch (_) {
      _setFailure('Unable to load device pairings. Please retry.');
    }
  }

  Future<void> revoke(String pairingId) async {
    if (state.revokingPairingIds.contains(pairingId)) return;
    state = PairingState(
      challengeId: state.challengeId,
      pairingCode: state.pairingCode,
      status: state.status,
      pairings: state.pairings,
      revokingPairingIds: Set.unmodifiable({
        ...state.revokingPairingIds,
        pairingId,
      }),
      errorMessage: state.errorMessage,
    );

    String? failureMessage;
    try {
      await _repository.revoke(pairingId);
    } on PairingFailure catch (error) {
      failureMessage = error.message;
    } catch (_) {
      failureMessage = 'Unable to revoke device pairing. Please retry.';
    }

    final remaining = Set<String>.of(state.revokingPairingIds)
      ..remove(pairingId);
    state = PairingState(
      challengeId: state.challengeId,
      pairingCode: state.pairingCode,
      status: failureMessage == null ? state.status : PairingStatus.failed,
      pairings: failureMessage == null
          ? state.pairings
                .where((pairing) => pairing.pairingId != pairingId)
                .toList(growable: false)
          : state.pairings,
      revokingPairingIds: Set.unmodifiable(remaining),
      errorMessage: failureMessage ?? state.errorMessage,
    );
  }

  Future<bool> _complete(PairingChallengePayload payload) async {
    if (state.status == PairingStatus.submitting) return false;
    state = PairingState(
      challengeId: state.challengeId,
      pairingCode: state.pairingCode,
      pairings: state.pairings,
      revokingPairingIds: state.revokingPairingIds,
      status: PairingStatus.submitting,
    );
    try {
      final pairing = await _repository.complete(payload);
      final pairings = [
        pairing,
        ...state.pairings.where(
          (existing) => existing.pairingId != pairing.pairingId,
        ),
      ];
      state = PairingState(
        status: PairingStatus.paired,
        pairings: pairings,
        revokingPairingIds: state.revokingPairingIds,
      );
      return true;
    } on PairingFailure catch (error) {
      _setFailure(error.message);
      return false;
    } catch (_) {
      _setFailure('Unable to pair this device. Please retry.');
      return false;
    }
  }

  void _setFailure(String message) {
    state = PairingState(
      challengeId: state.challengeId,
      pairingCode: state.pairingCode,
      pairings: state.pairings,
      revokingPairingIds: state.revokingPairingIds,
      status: PairingStatus.failed,
      errorMessage: message,
    );
  }
}
