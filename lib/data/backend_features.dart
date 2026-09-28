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
}
