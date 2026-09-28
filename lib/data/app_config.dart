import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  /// Production API. Release builds use it by default so a store build can't
  /// ship pointing at a dev machine or in mock mode.
  static const productionApiBaseUrl = 'https://rapid-alert.site';

  // Debug default is the Android emulator's alias for the host machine; pass
  // --dart-define=RAPID_ALERT_API_BASE_URL=... to point elsewhere.
  static const apiBaseUrl = String.fromEnvironment(
    'RAPID_ALERT_API_BASE_URL',
    defaultValue: kReleaseMode ? productionApiBaseUrl : 'http://10.0.2.2:8000',
  );

  static const useApi = bool.fromEnvironment(
    'RAPID_ALERT_USE_API',
    defaultValue: kReleaseMode,
  );

  // Dev-only bootstrap session (skips login). Never honoured in release.
  static const responderUserId = kReleaseMode
      ? 0
      : int.fromEnvironment('RAPID_ALERT_RESPONDER_USER_ID', defaultValue: 0);

  static const bearerToken = kReleaseMode
      ? ''
      : String.fromEnvironment('RAPID_ALERT_TOKEN', defaultValue: '');
}
