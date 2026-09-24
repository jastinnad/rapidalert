import '../models/responder_models.dart';

abstract class ResponderService {
  Stream<List<IncidentReport>> get reportsStream;
  Stream<List<CoordinationEvent>> get eventsStream;
  Stream<GeoPoint> get responderTrackingStream;
  Stream<List<ChatMessage>> get chatStream;

  List<IncidentReport> get reports;
  GeoPoint get currentResponderPoint;

  List<ChatMessage> messagesFor(String reportId);

  Future<void> updateReportStatus(String reportId, ReportStatus status);

  Future<void> sendResponderMessage({
    required String reportId,
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
