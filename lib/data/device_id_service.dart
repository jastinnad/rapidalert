import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// A stable per-install device ID, used to track hazard reports submitted
/// without an account (guest reporting) — reused as the API's
/// `client_report_id`, since IP-address tracking is unreliable on mobile
/// (many phones share one carrier NAT address).
class DeviceIdService {
  DeviceIdService._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'rapid_alert_device_id';
  static const _uuid = Uuid();

  static String? _cached;

  static Future<String> getOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;

    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) {
      _cached = existing;
      return existing;
    }

    final generated = _uuid.v4();
    await _storage.write(key: _key, value: generated);
    _cached = generated;
    return generated;
  }
}
