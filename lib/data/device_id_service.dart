import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// A stable per-install device ID: created once, kept for the life of the
/// installation.
///
/// It identifies the device, not a report — reports carry their own
/// `client_report_id` (see `ReportSubmissionIds`). App versions before
/// per-report IDs sent this value as every report's `client_report_id`, so
/// it also finds the report such an install already submitted.
class DeviceIdService {
  DeviceIdService._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'rapid_alert_device_id';
  static const _uuid = Uuid();

  static String? _cached;

  static Future<String> getOrCreate() async {
    final existing = await DeviceIdService.existing();
    if (existing != null) return existing;

    final generated = _uuid.v4();
    await _storage.write(key: _key, value: generated);
    _cached = generated;
    return generated;
  }

  /// The stored device ID, or null if this install hasn't created one yet.
  static Future<String?> existing() async {
    final cached = _cached;
    if (cached != null) return cached;

    final stored = await _storage.read(key: _key);
    if (stored == null || stored.isEmpty) return null;
    _cached = stored;
    return stored;
  }
}
