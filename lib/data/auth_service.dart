import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'offline_cache.dart';

class UserSession {
  const UserSession({
    required this.token,
    required this.responderUserId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
  });

  final String token;

  /// The account's numeric user id (named for its original responder-only
  /// origin; holds the id for reporter accounts too).
  final int responderUserId;
  final String firstName;
  final String lastName;
  final String email;

  /// `'reporter'` or `'responder'`.
  final String role;

  String get fullName => '$firstName $lastName'.trim();
  bool get isReporter => role == 'reporter';
  bool get isResponder => role == 'responder';
}

class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static const _storage = FlutterSecureStorage();

  static const _requestTimeout = Duration(seconds: 20);

  /// What a user sees for a failed sign-in/registration. A 4xx `message` is
  /// written for users ("These credentials do not match…"); a 5xx one can be
  /// a raw server error (SQL, hosts), so it is never shown.
  static String failureMessage(int statusCode, String? serverMessage, String action) {
    if (statusCode >= 500) {
      return 'Rapid Alert is having trouble right now. Please try again in a moment.';
    }
    if (statusCode == 429) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    final message = serverMessage?.trim();
    return message != null && message.isNotEmpty ? message : '$action failed. Please check your details and try again.';
  }

  static const _tokenKey = 'rapid_alert_token';
  static const _userIdKey = 'rapid_alert_user_id';
  static const _firstNameKey = 'rapid_alert_first_name';
  static const _lastNameKey = 'rapid_alert_last_name';
  static const _emailKey = 'rapid_alert_email';
  static const _roleKey = 'rapid_alert_role';

  static Future<UserSession> login(String email, String password) async {
    final endpoint = Uri.parse('${AppConfig.apiBaseUrl}/api/auth/login');

    late final http.Response response;
    try {
      response = await http
          .post(
            endpoint,
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password, 'device_name': 'flutter-mobile-app'}),
          )
          .timeout(_requestTimeout);
    } catch (_) {
      throw AuthException('Unable to reach the server. Check your connection.');
    }

    final body = _tryDecode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(failureMessage(response.statusCode, body?['message'] as String?, 'Sign in'));
    }

    if (body == null) {
      throw AuthException('Unexpected response from server.');
    }

    final session = _sessionFromResponse(body, fallbackEmail: email);
    await _persist(session);
    return session;
  }

  /// Reporter self-registration. Responder accounts are admin-provisioned
  /// only, both on web and mobile.
  ///
  /// The home address is identified by PSGC codes ([provinceCode] is empty
  /// for a city directly under its region, e.g. NCR); [barangay] is the
  /// display name and is not what the server trusts.
  static Future<UserSession> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String houseNo,
    required String purok,
    required String regionCode,
    required String provinceCode,
    required String cityCode,
    required String barangayCode,
    required String barangay,
    String? landmark,
  }) async {
    final endpoint = Uri.parse('${AppConfig.apiBaseUrl}/api/auth/register');

    late final http.Response response;
    try {
      response = await http
          .post(
            endpoint,
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'first_name': firstName,
              'last_name': lastName,
              'email': email,
              'phone': phone,
              'password': password,
              'password_confirmation': password,
              'house_no': houseNo,
              'purok': purok,
              'region_code': regionCode,
              'province_code': provinceCode,
              'city_code': cityCode,
              'barangay_code': barangayCode,
              'barangay': barangay,
              if (landmark != null && landmark.isNotEmpty) 'landmark': landmark,
            }),
          )
          .timeout(_requestTimeout);
    } catch (_) {
      throw AuthException('Unable to reach the server. Check your connection.');
    }

    final body = _tryDecode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Field errors come with 4xx validation responses only.
      final errors = response.statusCode < 500 ? (body?['errors'] as Map<String, dynamic>?) : null;
      final firstError = errors?.values.first is List ? (errors!.values.first as List).first?.toString() : null;
      throw AuthException(
        firstError ?? failureMessage(response.statusCode, body?['message'] as String?, 'Registration'),
      );
    }

    if (body == null) {
      throw AuthException('Unexpected response from server.');
    }

    final session = _sessionFromResponse(body, fallbackEmail: email);
    await _persist(session);
    return session;
  }

  static Future<UserSession?> restoreSession() async {
    final token = await _storage.read(key: _tokenKey);
    final userId = await _storage.read(key: _userIdKey);
    if (token == null || token.isEmpty || userId == null) {
      return null;
    }

    return UserSession(
      token: token,
      responderUserId: int.tryParse(userId) ?? 0,
      firstName: await _storage.read(key: _firstNameKey) ?? '',
      lastName: await _storage.read(key: _lastNameKey) ?? '',
      email: await _storage.read(key: _emailKey) ?? '',
      role: await _storage.read(key: _roleKey) ?? 'responder',
    );
  }

  static Future<void> logout(UserSession? session) async {
    if (session != null) {
      final endpoint = Uri.parse('${AppConfig.apiBaseUrl}/api/auth/logout');
      try {
        await http.post(endpoint, headers: {'Accept': 'application/json', 'Authorization': 'Bearer ${session.token}'});
      } catch (_) {
        // Best-effort: still clear the local session even if this fails.
      }
    }

    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _userIdKey),
      _storage.delete(key: _firstNameKey),
      _storage.delete(key: _lastNameKey),
      _storage.delete(key: _emailKey),
      _storage.delete(key: _roleKey),
      // Saved report and evacuation data belongs to the signed-out account.
      OfflineCache(storage: _storage).clearAll(),
    ]);
  }

  static UserSession _sessionFromResponse(Map<String, dynamic> body, {required String fallbackEmail}) {
    final token = body['token'] as String;
    final user = body['user'] as Map<String, dynamic>;

    return UserSession(
      token: token,
      responderUserId: (user['id'] as num).toInt(),
      firstName: user['first_name']?.toString() ?? '',
      lastName: user['last_name']?.toString() ?? '',
      email: user['email']?.toString() ?? fallbackEmail,
      role: user['role']?.toString() ?? 'responder',
    );
  }

  static Future<void> _persist(UserSession session) async {
    await Future.wait([
      _storage.write(key: _tokenKey, value: session.token),
      _storage.write(key: _userIdKey, value: session.responderUserId.toString()),
      _storage.write(key: _firstNameKey, value: session.firstName),
      _storage.write(key: _lastNameKey, value: session.lastName),
      _storage.write(key: _emailKey, value: session.email),
      _storage.write(key: _roleKey, value: session.role),
    ]);
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
