/// Mirrors the backend's real StatusMachine vocabulary exactly
/// (assigned/en_route/on_scene/resolved/completed). `needHelp` is a
/// separate `bool` field on [IncidentReport], not a status value.
enum ReportStatus { assigned, enRoute, onScene, resolved, completed }

enum CoordinationPriority { normal, important, urgent, critical }

class IncidentReport {
  const IncidentReport({
    required this.id,
    required this.hazard,
    required this.location,
    required this.reporterName,
    required this.status,
    required this.needHelp,
    required this.updated,
    required this.reporterLat,
    required this.reporterLng,
    this.reporterUserId,
    this.trackingId = '',
    this.city = '',
    this.particular = '',
    this.particularDetail = '',
    this.currentSituation = const [],
    this.needs = const [],
    this.pregnantCount = 0,
    this.elderlyCount = 0,
    this.childCount = 0,
    this.pwdCount = 0,
    this.purok = '',
    this.houseNo = '',
    this.landmark = '',
    this.phone = '',
    this.alternateContact = '',
    this.imageUrl = '',
    this.reportedAt,
    this.reporterOnline,
  });

  /// The backend's numeric report id (used in API calls).
  final String id;
  final String hazard;

  /// Barangay, or the city when the barangay is missing.
  final String location;
  final String reporterName;
  final ReportStatus status;
  final bool needHelp;
  final DateTime updated;
  /// The report's own GPS position; null when the report was submitted
  /// without one. Never replaced by a default location.
  final double? reporterLat;
  final double? reporterLng;

  /// Who to message; null for a guest's report (no account, no inbox).
  final int? reporterUserId;

  /// The Tracking ID the reporter sees (e.g. RA-20260930-ABC123); empty
  /// when the backend didn't send one.
  final String trackingId;
  final String city;

  /// Report details the backend shares with the assigned responder (the
  /// same ones the website's responder queue shows). Empty when not given.
  final String particular;
  final String particularDetail;
  final List<String> currentSituation;
  final List<String> needs;
  final int pregnantCount;
  final int elderlyCount;
  final int childCount;
  final int pwdCount;
  final String purok;
  final String houseNo;
  final String landmark;
  final String phone;
  final String alternateContact;
  final String imageUrl;
  final DateTime? reportedAt;

  /// The backend's presence flag for the reporter's account: true/false from
  /// its 10-minute online marker, null when unknown (guest report, or not
  /// sent). Never guessed from timestamps.
  final bool? reporterOnline;

  bool get isGuestReport => reporterUserId == null;

  /// What to show people: the Tracking ID, or the report id when missing.
  String get displayId => trackingId.isNotEmpty ? trackingId : id;

  IncidentReport copyWith({
    ReportStatus? status,
    bool? needHelp,
    DateTime? updated,
  }) {
    return IncidentReport(
      id: id,
      hazard: hazard,
      location: location,
      reporterName: reporterName,
      status: status ?? this.status,
      needHelp: needHelp ?? this.needHelp,
      updated: updated ?? this.updated,
      reporterLat: reporterLat,
      reporterLng: reporterLng,
      reporterUserId: reporterUserId,
      trackingId: trackingId,
      city: city,
      particular: particular,
      particularDetail: particularDetail,
      currentSituation: currentSituation,
      needs: needs,
      pregnantCount: pregnantCount,
      elderlyCount: elderlyCount,
      childCount: childCount,
      pwdCount: pwdCount,
      purok: purok,
      houseNo: houseNo,
      landmark: landmark,
      phone: phone,
      alternateContact: alternateContact,
      imageUrl: imageUrl,
      reportedAt: reportedAt,
      reporterOnline: reporterOnline,
    );
  }
}

/// The one forward step a responder can take from a status, matching the
/// backend's StatusMachine; `resolved`/`completed` have none.
(String, ReportStatus)? responderNextStep(ReportStatus status) {
  return switch (status) {
    ReportStatus.assigned => ('Start — En Route', ReportStatus.enRoute),
    ReportStatus.enRoute => ('Arrived — On Scene', ReportStatus.onScene),
    ReportStatus.onScene => ('Mark Resolved', ReportStatus.resolved),
    ReportStatus.resolved || ReportStatus.completed => null,
  };
}

class CoordinationEvent {
  const CoordinationEvent({
    required this.id,
    required this.title,
    required this.message,
    required this.priority,
    required this.time,
  });

  final String id;
  final String title;
  final String message;
  final CoordinationPriority priority;
  final DateTime time;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.reportId,
    required this.sender,
    required this.message,
    required this.time,
    required this.isResponder,
  });

  final String id;
  final String reportId;
  final String sender;
  final String message;
  final DateTime time;
  final bool isResponder;
}

class GeoPoint {
  const GeoPoint({required this.lat, required this.lng, this.recordedAt});

  final double lat;
  final double lng;

  /// When this position was fixed, if known — lets a screen tell a current
  /// position from a last known one.
  final DateTime? recordedAt;
}

/// A report the current responder is actively `en_route`/`on_scene` for —
/// tells [ApiResponderService] which reports to push GPS pings to.
class ActiveTrackingAssignment {
  const ActiveTrackingAssignment({
    required this.reportId,
    required this.trackingId,
    required this.status,
  });

  final int reportId;
  final String trackingId;
  final String status;

  factory ActiveTrackingAssignment.fromApi(Map<String, dynamic> json) {
    return ActiveTrackingAssignment(
      reportId: (json['reportId'] as num?)?.toInt() ?? 0,
      trackingId: json['trackingId']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }
}

/// A stored backend notification (`/api/reports/notifications`) telling this
/// responder that [reportId] was assigned to them.
class AssignmentAlert {
  const AssignmentAlert({required this.notificationId, required this.reportId, required this.message});

  final int notificationId;
  final String reportId;
  final String message;
}

/// How the last load of the assigned-report list went.
class ReportListStatus {
  const ReportListStatus({this.lastLoadedAt, this.errorMessage});

  /// Null until the list has loaded successfully at least once.
  final DateTime? lastLoadedAt;

  /// Plain-language reason the most recent load failed; null when it worked.
  final String? errorMessage;

  bool get loaded => lastLoadedAt != null;
}

enum FollowUpPriority { high, medium, low }

class FollowUp {
  const FollowUp({
    required this.id,
    required this.reportId,
    required this.trackingId,
    required this.hazard,
    required this.reason,
    this.notes,
    required this.scheduledAt,
    required this.priority,
    required this.isCompleted,
  });

  final String id;
  final String reportId;
  final String trackingId;
  final String hazard;
  final String reason;
  final String? notes;
  final DateTime scheduledAt;
  final FollowUpPriority priority;
  final bool isCompleted;

  bool get isOverdue => !isCompleted && scheduledAt.isBefore(DateTime.now());
}

enum EvacStatus { preparing, ongoing, completed, needsSupport }

const List<String> evacuationHazardTypes = ['flood', 'earthquake', 'fire', 'typhoon', 'landslide'];

const List<String> evacuationCenterNames = [
  'Lipa City Hall Evacuation Site',
  'Lipa City Public Gym',
  'Lipa City Kapitolyo Open Grounds',
  'Lipa South Central School',
];

class EvacuationRecordEntry {
  const EvacuationRecordEntry({
    required this.trackingId,
    required this.hazardType,
    required this.barangay,
    required this.centerName,
    required this.status,
    required this.totalEvacuees,
    required this.maleCount,
    required this.femaleCount,
    required this.childrenCount,
    required this.seniorsCount,
    required this.pregnantCount,
    required this.pwdCount,
    this.fieldNotes,
    required this.updatedAt,
  });

  final String trackingId;
  final String hazardType;
  final String barangay;
  final String centerName;
  final EvacStatus status;
  final int totalEvacuees;
  final int maleCount;
  final int femaleCount;
  final int childrenCount;
  final int seniorsCount;
  final int pregnantCount;
  final int pwdCount;
  final String? fieldNotes;
  final DateTime updatedAt;

  int get vulnerableCount => childrenCount + seniorsCount + pwdCount;
}

enum AnnouncementPriority { low, normal, high }

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.message,
    required this.priority,
    required this.hazardType,
    required this.publishedAt,
    required this.publishedAgo,
  });

  final String id;
  final String title;
  final String message;
  final AnnouncementPriority priority;
  final String hazardType;
  final DateTime publishedAt;
  final String publishedAgo;
}

enum ResourcePriority { low, normal, high, critical }

enum ResourceStatus { pending, approved, inProgress, fulfilled, cancelled }

const List<String> resourceCategories = [
  'medical',
  'food',
  'water',
  'shelter',
  'transport',
  'rescue',
  'communications',
  'other',
];

class ResourceRequestEntry {
  const ResourceRequestEntry({
    required this.id,
    required this.reportId,
    required this.trackingId,
    required this.category,
    required this.itemName,
    required this.quantityRequested,
    required this.quantityFulfilled,
    this.unit,
    required this.priority,
    required this.status,
    this.locationHint,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String reportId;
  final String trackingId;
  final String category;
  final String itemName;
  final int quantityRequested;
  final int quantityFulfilled;
  final String? unit;
  final ResourcePriority priority;
  final ResourceStatus status;
  final String? locationHint;
  final String? notes;
  final DateTime createdAt;
}
