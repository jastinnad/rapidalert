import '../models/responder_models.dart';

abstract class ResponderService {
  Stream<List<IncidentReport>> get reportsStream;
  Stream<List<CoordinationEvent>> get eventsStream;
  Stream<GeoPoint> get responderTrackingStream;
  Stream<List<ChatMessage>> get chatStream;

  List<IncidentReport> get reports;

  /// Whether the assigned-report list is loaded and whether its last
  /// refresh failed, so an empty or old list is never shown as current.
  Stream<ReportListStatus> get reportListStatusStream;
  ReportListStatus get reportListStatus;

  /// Loads the assigned-report list now (e.g. from a Retry button).
  Future<void> refreshReports();

  /// The backend's assignment notification for each report newly assigned
  /// while the app is open, each at most once.
  Stream<AssignmentAlert> get assignmentAlerts;
  /// Null until the device has a real GPS fix.
  GeoPoint? get currentResponderPoint;

  /// Whether this phone is sharing its location right now (only while a
  /// report is en route/on scene). When false, [currentResponderPoint] is
  /// only a last known position.
  bool get isSharingLocation;

  List<ChatMessage> messagesFor(String reportId);

  /// Loads one report's chat now. Throws when it can't (no connection,
  /// server error), so the chat screen can say so instead of looking empty.
  Future<void> loadMessages(String reportId);

  Future<void> updateReportStatus(String reportId, ReportStatus status);

  Future<void> sendResponderMessage({
    required String reportId,
    required int receiverId,
    required String text,
  });

  Stream<List<FollowUp>> get followUpsStream;
  List<FollowUp> get followUps;

  Future<void> createFollowUp({
    required String reportId,
    required String reason,
    String? notes,
    required DateTime scheduledAt,
    required FollowUpPriority priority,
  });

  Future<void> completeFollowUp(String followUpId);

  Stream<List<EvacuationRecordEntry>> get evacuationRecordsStream;
  List<EvacuationRecordEntry> get evacuationRecords;

  Future<void> saveEvacuationRecord({
    required String trackingId,
    required String hazardType,
    required String barangay,
    required String centerName,
    required EvacStatus status,
    required int totalEvacuees,
    required int maleCount,
    required int femaleCount,
    required int childrenCount,
    required int seniorsCount,
    required int pregnantCount,
    required int pwdCount,
    String? fieldNotes,
  });

  Stream<List<Announcement>> get announcementsStream;
  List<Announcement> get announcements;

  Stream<List<ResourceRequestEntry>> get resourceRequestsStream;
  List<ResourceRequestEntry> get resourceRequests;

  Future<void> createResourceRequest({
    required String reportId,
    required String category,
    required String itemName,
    required int quantityRequested,
    String? unit,
    required ResourcePriority priority,
    String? locationHint,
    String? notes,
  });

  void dispose();
}
