/// Mobile features whose backend endpoints are not deployed to production
/// yet. While a flag is false the app neither shows the feature nor calls its
/// endpoint, so it never polls a route that would only return 404.
///
/// Flip a flag to true in the same release that deploys its route.
class BackendFeatures {
  const BackendFeatures._();

  /// POST/DELETE /api/device-token (push notification registration).
  static const pushRegistration = false;

  /// GET /api/responder/coordination/events (responder "Live" tab).
  static const coordinationFeed = false;

  /// GET /api/responder/announcements.
  static const responderAnnouncements = false;

  /// /api/responder/follow-ups (Follow-Up Board).
  static const followUps = false;

  /// /api/responder/evacuation-records (Evacuation Tracker, Active Centers).
  static const evacuationRecords = false;

  /// /api/responder/resources (Resources).
  static const resources = false;

  /// Reporter tracking details: the incident's own coordinates from
  /// GET /api/reporter/reports/track (incident pin and road route on the
  /// reporter's map) and GET /api/reporter/reports/history (Status history).
  /// Off unless a build passes
  /// --dart-define=RAPID_ALERT_REPORTER_TRACKING_DETAILS=true, as a local
  /// build against a backend that has both does.
  static const reporterTrackingDetails = bool.fromEnvironment('RAPID_ALERT_REPORTER_TRACKING_DETAILS');
}
