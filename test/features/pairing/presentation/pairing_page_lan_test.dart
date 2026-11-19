import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_relay/app/di/app_providers.dart';
import 'package:sonic_relay/app/di/lan_providers.dart';
import 'package:sonic_relay/core/webrtc/connectivity_modes.dart';
import 'package:sonic_relay/features/pairing/presentation/pairing_page.dart';
import 'package:sonic_relay/features/pairing/presentation/pairing_view_model.dart';
import 'package:sonic_relay/features/sessions/data/dto/public_room_info.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('lanOnly pairing page never reaches RelayControl', (
    tester,
  ) async {
    var cloudCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityModeProvider.overrideWith(
            () => ConnectivityModeNotifier(ConnectivityModes.lanOnly),
          ),
          currentPairingDeviceIdProvider.overrideWithValue(() async {
            cloudCalls++;
            return null;
          }),
          publicRoomProvider.overrideWith((ref) {
            cloudCalls++;
            return Stream.value(const PublicRoomInfo.disabled());
          }),
        ],
        child: const MaterialApp(home: PairingPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(cloudCalls, 0);
    expect(find.text('Scan QR code'), findsOneWidget);
    expect(find.byKey(const Key('pairing-challenge-id')), findsNothing);
  });
}
