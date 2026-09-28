// Firebase Cloud Messaging integration for the responder app.
//
// NOT WIRED IN YET. This file is self-contained and ready to use, but
// intentionally not called from main.dart/auth_gate.dart, because doing so
// would call Firebase.initializeApp() before the native Android side is
// configured (google-services.json + applying the Gradle plugin in
// android/app/build.gradle.kts), which would crash the app at startup.
//
// Once google-services.json is dropped into android/app/ and the plugin line
// in android/app/build.gradle.kts is uncommented, wire this up:
//   1. In main.dart: `await Firebase.initializeApp();` before `runApp(...)`,
//      and `FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);`
//   2. In auth_gate.dart, after a successful login/session restore:
//      `PushNotificationService.registerDevice(baseUrl: ..., bearerToken: ...);`
//   3. In auth_gate.dart's `_handleLogout`, before clearing the session:
//      `await PushNotificationService.unregisterDevice(baseUrl: ..., bearerToken: session.token);`
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

import 'backend_features.dart';

/// Must be a top-level (or static) function — FCM invokes this in a
/// separate isolate when a data message arrives while the app is
/// backgrounded or terminated.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // Intentionally minimal: the OS already shows the notification tray entry
  // for notification-type messages. Add background data handling here later
  // if the app needs to react (e.g. refresh local cache) while backgrounded.
}

class PushNotificationService {
  PushNotificationService._();

  /// Requests notification permission, retrieves the FCM token, registers it
  /// with the backend, and subscribes to future token refreshes. Safe to
  /// call once per app session (e.g. right after login or session restore).
  static Future<void> registerDevice({
    required String baseUrl,
    required String bearerToken,
  }) async {
    // Until /api/device-token is deployed there is nowhere to register the
    // token, so don't ask for notification permission or call the backend.
    if (!BackendFeatures.pushRegistration) return;

    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await messaging.getToken();
    if (token != null) {
      await _sendTokenToBackend(baseUrl: baseUrl, bearerToken: bearerToken, token: token);
    }

    messaging.onTokenRefresh.listen((newToken) {
      _sendTokenToBackend(baseUrl: baseUrl, bearerToken: bearerToken, token: newToken);
    });

    FirebaseMessaging.onMessage.listen((message) {
      // Foreground messages don't show a system tray notification by
      // default. Hook this into a snackbar/in-app banner once wired up.
    });
  }

  /// Removes this device's current token registration, typically called on
  /// sign-out so a shared/reset device stops receiving pushes for the
  /// account that just logged out.
  static Future<void> unregisterDevice({
    required String baseUrl,
    required String bearerToken,
  }) async {
    if (!BackendFeatures.pushRegistration) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      return;
    }

    try {
      await http.delete(
        Uri.parse('$baseUrl/api/device-token'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $bearerToken',
        },
        body: jsonEncode({'token': token}),
      );
    } catch (_) {
      // Best-effort: local sign-out should still proceed even if this fails.
    }
  }

  static Future<void> _sendTokenToBackend({
    required String baseUrl,
    required String bearerToken,
    required String token,
  }) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/device-token'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $bearerToken',
        },
        body: jsonEncode({
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        }),
      );
    } catch (_) {
      // Best-effort: token registration retries naturally on next app
      // launch or token refresh.
    }
  }
}
