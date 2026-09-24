class AppConfig {
  const AppConfig._();

  // Example local Laravel URL from Android emulator: http://10.0.2.2:8000
  static const apiBaseUrl = String.fromEnvironment(
    'RAPID_ALERT_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const useApi = bool.fromEnvironment(
    'RAPID_ALERT_USE_API',
    defaultValue: false,
  );

  static const responderUserId = int.fromEnvironment(
    'RAPID_ALERT_RESPONDER_USER_ID',
    defaultValue: 0,
  );

  // Temporary bootstrap token until login endpoint is wired in backend API.
  static const bearerToken = String.fromEnvironment(
    'RAPID_ALERT_TOKEN',
    defaultValue: '',
  );
}
