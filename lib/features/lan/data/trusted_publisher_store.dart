import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../domain/trusted_publisher.dart';

/// Desktops this phone paired with over the LAN, in secure storage
/// (dotnet_SonicRelay#75). "Forget" removes the credential; the desktop can
/// independently revoke it.
class TrustedPublisherStore {
  const TrustedPublisherStore(this._storage);

  static const _publishersKey = 'lan.trustedPublishers';
  static const _viewerIdKey = 'lan.viewerDeviceId';
  static const maxEndpoints = 4;

  final FlutterSecureStorage _storage;

  Future<List<TrustedPublisher>> list() async {
    final raw = await _storage.read(key: _publishersKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(TrustedPublisher.fromJson)
          .toList();
    } on Object {
      // Unreadable trust means nothing is trusted: fail closed and re-pair.
      return [];
    }
  }

  Future<void> save(TrustedPublisher publisher) async {
    final all = await list();
    all.removeWhere((p) => p.publisherDeviceId == publisher.publisherDeviceId);
    all.add(publisher);
    await _write(all);
  }

  Future<void> remove(String publisherDeviceId) async {
    final all = await list();
    all.removeWhere((p) => p.publisherDeviceId == publisherDeviceId);
    await _write(all);
  }

  /// Moves [endpoints] to the front (newest first), de-duplicated, capped.
  Future<void> updateEndpoints(
    String publisherDeviceId,
    List<String> endpoints,
  ) async {
    final all = await list();
    final index = all.indexWhere(
      (p) => p.publisherDeviceId == publisherDeviceId,
    );
    if (index < 0) return;
    final merged = <String>{
      ...endpoints,
      ...all[index].lastEndpoints,
    }.take(maxEndpoints).toList();
    all[index] = all[index].copyWith(
      lastEndpoints: merged,
      lastSeenAt: DateTime.now().toUtc(),
    );
    await _write(all);
  }

  /// A random UUID identifying this phone to LAN publishers, independent of
  /// the cloud device identity. Created once and kept.
  Future<String> viewerDeviceId() async {
    final existing = await _storage.read(key: _viewerIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await _storage.write(key: _viewerIdKey, value: created);
    return created;
  }

  Future<void> _write(List<TrustedPublisher> publishers) => _storage.write(
    key: _publishersKey,
    value: jsonEncode(publishers.map((p) => p.toJson()).toList()),
  );
}
