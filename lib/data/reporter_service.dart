import '../models/reporter_models.dart';
import 'offline_cache.dart' show CachedCopy;
import '../models/responder_models.dart' show ChatMessage;

abstract class ReporterService {
  /// The logged-in reporter's numeric account id, or `null` for a guest
  /// (no session). Used to tell "my messages" apart from the responder's
  /// in a chat thread, and to hide chat entirely for guests.
  int? get currentUserId;

  Future<ReportFormOptions> loadHazardOptions();

  Future<ReportSubmitResult> submitReport({
    required String hazardType,
    required String particular,
    required String particularColor,
    required String particularDetail,
    required String region,
    required String province,
    required String city,
    required String barangay,
    required String purok,
    required String houseNo,
    String? landmark,
    double? latitude,
    double? longitude,
    int pregnantCount = 0,
    int elderlyCount = 0,
    int childCount = 0,
    int pwdCount = 0,
    bool needHelp = false,
    List<String> needs = const [],
    List<String> currentSituation = const [],
    String? imagePath,
    String? clientReportId,
    /// Required by the backend when submitting without an account.
    String? phone,
  });

  Future<TrackedReport?> trackReport({String? trackingId, String? clientReportId});

  /// The last report [trackReport] found for this account, if it matches
  /// [trackingId] (any report when null). For display while offline only.
  Future<CachedCopy<TrackedReport>?> cachedTrackedReport({String? trackingId});

  /// The account's own notifications about one report, newest first.
  /// Signed-in accounts only; the backend has no read/unread state.
  Future<List<ReportNotification>> loadReportNotifications(int reportId);

  /// Whether a report of the caller's is already stored under
  /// [clientReportId]. Read-only. Throws [ReportSubmitException] when the
  /// answer is unknown (no connection, server error, unexpected reply).
  Future<bool> submittedReportExists(String clientReportId);

  Future<ReporterProfile> loadProfile();

  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    String? gender,
    required String houseNo,
    required String purok,
    required String barangay,
    String? landmark,
  });

  Future<CheckInStatus> setCheckInStatus(CheckInStatus status);

  Future<CheckInStatus> loadCheckInStatus();

  /// [fromUserLocation] is false when [lat]/[lon] are a fallback rather than
  /// the device's real position; the offline copy then keeps no distances
  /// or ETAs, since they aren't measured from the user.
  Future<EvacuationRankedResult> loadNearestEvacuationCenters({
    required double lat,
    required double lon,
    int groupSize = 1,
    bool fromUserLocation = true,
  });

  /// The last list [loadNearestEvacuationCenters] returned for this account.
  /// For display while offline only.
  Future<CachedCopy<EvacuationRankedResult>?> cachedEvacuationCenters();

  Future<GeofenceArrivalResult> confirmEvacuationArrival({
    required int areaId,
    int? reportId,
  });

  Future<List<ChatMessage>> loadReportMessages(int reportId);

  Future<void> sendReportMessage({
    required int reportId,
    required int receiverId,
    required String text,
  });
}
