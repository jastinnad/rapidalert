import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// A copy of the last good server answer, shown when the server can't be
/// reached. Always displayed with its [savedAt] time and an OFFLINE badge,
/// never as live data.
class CachedCopy<T> {
  const CachedCopy(this.value, this.savedAt);

  final T value;
  final DateTime savedAt;
}

/// Keeps the last tracked report and the last evacuation-center list per
/// account, in secure storage (they include locations). Cleared on sign-out.
class OfflineCache {
  OfflineCache({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _prefix = 'offline_cache.';

  Future<void> save(String key, Map<String, dynamic> json) async {
    try {
      await _storage.write(
        key: '$_prefix$key',
        value: jsonEncode({'saved_at': DateTime.now().toUtc().toIso8601String(), 'data': json}),
      );
    } catch (_) {
      // Best-effort: the live data is already on screen.
    }
  }

  Future<CachedCopy<Map<String, dynamic>>?> load(String key) async {
    try {
      final raw = await _storage.read(key: '$_prefix$key');
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
      final data = json['data'];
      if (savedAt == null || data is! Map<String, dynamic>) return null;
      return CachedCopy(data, savedAt.toLocal());
    } catch (_) {
      return null;
    }
  }

  Future<void> clearAll() async {
    try {
      final all = await _storage.readAll();
      await Future.wait([
        for (final key in all.keys)
          if (key.startsWith(_prefix)) _storage.delete(key: key),
      ]);
    } catch (_) {
      // Nothing more to do; the next save overwrites per key anyway.
    }
  }
}

/// True when the request never got an answer from the server (no network,
/// DNS failure, timeout) — as opposed to the server answering with an error.
bool isNetworkError(Object error) =>
    error is http.ClientException || error is IOException || error is TimeoutException;
