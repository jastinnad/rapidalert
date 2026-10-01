class HazardOption {
  const HazardOption({
    required this.hazardType,
    required this.particular,
    required this.particularColor,
    required this.particularDetail,
  });

  final String hazardType;
  final String particular;

  /// `green` | `orange` | `red` — maps to severity.
  final String particularColor;
  final String particularDetail;

  factory HazardOption.fromApi(Map<String, dynamic> json) {
    return HazardOption(
      hazardType: json['hazard_type']?.toString() ?? '',
      particular: json['particular']?.toString() ?? '',
      particularColor: json['particular_color']?.toString() ?? 'green',
      particularDetail: json['particular_detail']?.toString() ?? '',
    );
  }
}

class CurrentSituationConfig {
  const CurrentSituationConfig({
    required this.labels,
    required this.detailMatrix,
    required this.defaultSet,
  });

  final Map<String, String> labels;

  /// Keyed `"hazardType|color|detail"` (all lowercase) -> situation keys.
  final Map<String, List<String>> detailMatrix;
  final List<String> defaultSet;

  static const empty = CurrentSituationConfig(labels: {}, detailMatrix: {}, defaultSet: []);

  factory CurrentSituationConfig.fromApi(Map<String, dynamic>? json) {
    if (json == null) return empty;

    final labels = (json['labels'] as Map<String, dynamic>? ?? const {}).map(
      (key, value) => MapEntry(key, value?.toString() ?? ''),
    );
    final detailMatrix = (json['detail_matrix'] as Map<String, dynamic>? ?? const {}).map(
      (key, value) => MapEntry(key, (value as List<dynamic>? ?? const []).map((v) => v.toString()).toList()),
    );
    final defaultSet = (json['default'] as List<dynamic>? ?? const []).map((v) => v.toString()).toList();

    return CurrentSituationConfig(labels: labels, detailMatrix: detailMatrix, defaultSet: defaultSet);
  }

  /// Mirrors the web form's `renderCurrentSituationOptions` resolution:
  /// exact hazard|color|detail match, else union of all entries for the
  /// hazard, else the generic default set.
  List<String> situationsFor({required String hazardType, required String color, required String detail}) {
    final key = '${hazardType.toLowerCase()}|${color.toLowerCase()}|${detail.toLowerCase()}';
    final exact = detailMatrix[key];
    if (exact != null) return exact;

    final prefix = '${hazardType.toLowerCase()}|';
    final union = <String>{};
    for (final entry in detailMatrix.entries) {
      if (entry.key.startsWith(prefix)) union.addAll(entry.value);
    }
    if (union.isNotEmpty) return union.toList();

    return defaultSet;
  }
}

class RapidAssessmentPrefill {
  const RapidAssessmentPrefill({
    required this.hazardType,
    required this.particular,
    required this.particularColor,
    required this.particularDetail,
    required this.currentSituation,
  });

  final String hazardType;
  final String particular;
  final String particularColor;
  final String particularDetail;
  final List<String> currentSituation;

  static RapidAssessmentPrefill? fromApi(Map<String, dynamic>? json) {
    if (json == null) return null;
    return RapidAssessmentPrefill(
      hazardType: json['hazard_type']?.toString() ?? '',
      particular: json['particular']?.toString() ?? '',
      particularColor: json['particular_color']?.toString() ?? 'green',
      particularDetail: json['particular_detail']?.toString() ?? '',
      currentSituation: (json['current_situation'] as List<dynamic>? ?? const []).map((v) => v.toString()).toList(),
    );
  }
}

class ReportFormOptions {
  const ReportFormOptions({
    required this.hazardOptions,
    required this.situationConfig,
    required this.rapidAssessment,
  });

  final List<HazardOption> hazardOptions;
  final CurrentSituationConfig situationConfig;
  final RapidAssessmentPrefill? rapidAssessment;
}

class TrackedReport {
  const TrackedReport({
    required this.id,
    required this.trackingId,
    required this.hazard,
    required this.city,
    required this.barangay,
    required this.status,
    required this.assignedResponderName,
    required this.createdAt,
    required this.updatedAt,
    required this.adminComment,
    this.responderLat,
    this.responderLng,
    this.responderLocationUpdatedAt,
    this.etaMinutes,
    this.assignedResponderUserId,
    this.latitude,
    this.longitude,
  });

  final int id;
  final String trackingId;
  final String hazard;
  final String city;
  final String barangay;
  final String status;
  final String? assignedResponderName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String adminComment;

  /// Present whenever a responder is assigned, regardless of status — used
  /// to know who to message (unlike [responderLat], not gated to
  /// en_route/on_scene).
  final int? assignedResponderUserId;

  /// Only ever non-null while [status] is `en_route`/`on_scene` — the
  /// backend strips these fields the instant a report leaves that window.
  final double? responderLat;
  final double? responderLng;
  final DateTime? responderLocationUpdatedAt;
  final int? etaMinutes;

  /// The incident's own GPS position (where help is going). Null when the
  /// report was sent without GPS or the backend withholds it; never a default.
  final double? latitude;
  final double? longitude;

  factory TrackedReport.fromApi(Map<String, dynamic> json) {
    return TrackedReport(
      id: (json['id'] as num?)?.toInt() ?? 0,
      trackingId: json['trackingId']?.toString() ?? '',
      hazard: json['hazard']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      barangay: json['barangay']?.toString() ?? '',
      status: json['status']?.toString() ?? 'reported',
      assignedResponderName: json['assignedResponderName']?.toString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num?)?.toInt() ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((json['updatedAt'] as num?)?.toInt() ?? 0),
      adminComment: json['adminComment']?.toString() ?? '',
      responderLat: (json['responderLat'] as num?)?.toDouble(),
      responderLng: (json['responderLng'] as num?)?.toDouble(),
      responderLocationUpdatedAt: json['responderLocationUpdatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['responderLocationUpdatedAt'] as num).toInt())
          : null,
      etaMinutes: (json['etaMinutes'] as num?)?.toInt(),
      assignedResponderUserId: (json['assignedResponderUserId'] as num?)?.toInt(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

/// One step of a report's lifecycle, from the backend's status-transition
/// records (`GET /api/reporter/reports/history`).
class StatusHistoryEntry {
  const StatusHistoryEntry({
    required this.fromStatus,
    required this.toStatus,
    required this.at,
    required this.actorRole,
    required this.actorName,
  });

  final String? fromStatus;
  final String toStatus;
  final DateTime? at;

  /// `dispatcher`, `responder`, … (dispatchers are never named).
  final String actorRole;
  final String? actorName;

  factory StatusHistoryEntry.fromApi(Map<String, dynamic> json) {
    final at = (json['at'] as num?)?.toInt();
    return StatusHistoryEntry(
      fromStatus: json['fromStatus']?.toString(),
      toStatus: json['toStatus']?.toString() ?? '',
      at: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      actorRole: json['actorRole']?.toString() ?? '',
      actorName: json['actorName']?.toString(),
    );
  }
}

class StatusHistory {
  const StatusHistory({required this.trackingId, required this.submittedAt, required this.transitions});

  final String trackingId;
  final DateTime? submittedAt;
  final List<StatusHistoryEntry> transitions;

  factory StatusHistory.fromApi(Map<String, dynamic> json) {
    final submitted = (json['submittedAt'] as num?)?.toInt();
    return StatusHistory(
      trackingId: json['trackingId']?.toString() ?? '',
      submittedAt: submitted == null ? null : DateTime.fromMillisecondsSinceEpoch(submitted),
      transitions: (json['transitions'] as List<dynamic>? ?? const [])
          .map((item) => StatusHistoryEntry.fromApi(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One row of `GET /api/reports/notifications` (IncidentNotification).
class ReportNotification {
  const ReportNotification({required this.id, required this.message, required this.status, required this.createdAt});

  final int id;
  final String message;

  /// The report status the notification was written for.
  final String status;
  final DateTime? createdAt;

  factory ReportNotification.fromApi(Map<String, dynamic> json) {
    return ReportNotification(
      id: (json['id'] as num?)?.toInt() ?? 0,
      message: json['message']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
    );
  }
}

class ReporterProfile {
  const ReporterProfile({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.gender,
    required this.houseNo,
    required this.purok,
    required this.barangay,
    required this.city,
    required this.province,
    required this.region,
    required this.landmark,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? gender;
  final String? houseNo;
  final String? purok;
  final String? barangay;
  final String? city;
  final String? province;
  final String? region;
  final String? landmark;

  factory ReporterProfile.fromApi(Map<String, dynamic> json) {
    return ReporterProfile(
      firstName: json['firstName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      gender: json['gender']?.toString(),
      houseNo: json['houseNo']?.toString(),
      purok: json['purok']?.toString(),
      barangay: json['barangay']?.toString(),
      city: json['city']?.toString(),
      province: json['province']?.toString(),
      region: json['region']?.toString(),
      landmark: json['landmark']?.toString(),
    );
  }
}

enum CheckInStatus { safe, needHelp }

extension CheckInStatusApi on CheckInStatus {
  String get apiValue => this == CheckInStatus.safe ? 'im_safe' : 'i_need_help';

  static CheckInStatus fromApi(String value) => value == 'i_need_help' ? CheckInStatus.needHelp : CheckInStatus.safe;
}

class EvacuationCenter {
  const EvacuationCenter({
    required this.areaId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.capacity,
    required this.occupied,
    required this.availableSlots,
    required this.status,
    required this.statusColor,
    required this.statusLabel,
    required this.distanceKm,
    required this.etaMinutes,
    required this.score,
    required this.isFull,
    required this.isGrey,
    required this.directionsUrl,
  });

  final int areaId;
  final String name;
  final double lat;
  final double lon;
  final int capacity;
  final int occupied;
  final int availableSlots;

  /// `green` | `orange` | `red` | `grey`.
  final String status;

  /// Hex color from the backend (e.g. `#22c55e`) — kept as-is rather than
  /// re-derived, so mobile badge colors stay identical to the website's.
  final String statusColor;
  final String statusLabel;
  /// From the point the list was ranked from; null when unknown, e.g. in an
  /// offline copy saved without the user's real location.
  final double? distanceKm;
  final int? etaMinutes;
  final double score;
  final bool isFull;
  final bool isGrey;
  final String directionsUrl;

  factory EvacuationCenter.fromApi(Map<String, dynamic> json) {
    return EvacuationCenter(
      areaId: (json['area_id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0,
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      occupied: (json['occupied'] as num?)?.toInt() ?? 0,
      availableSlots: (json['available_slots'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'grey',
      statusColor: json['status_color']?.toString() ?? '#9ca3af',
      statusLabel: json['status_label']?.toString() ?? 'Unknown',
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      etaMinutes: (json['eta_minutes'] as num?)?.toInt(),
      score: (json['score'] as num?)?.toDouble() ?? 0,
      isFull: json['is_full'] == true,
      isGrey: json['is_grey'] == true,
      directionsUrl: json['directions_url']?.toString() ?? '',
    );
  }
}

class EvacuationRankedResult {
  const EvacuationRankedResult({
    required this.centres,
    required this.impassableMunicipalities,
    required this.warning,
    required this.cachedAt,
  });

  final List<EvacuationCenter> centres;
  final List<String> impassableMunicipalities;
  final String? warning;
  final DateTime? cachedAt;

  factory EvacuationRankedResult.fromApi(Map<String, dynamic> json) {
    return EvacuationRankedResult(
      centres: (json['centres'] as List<dynamic>? ?? const [])
          .map((c) => EvacuationCenter.fromApi(c as Map<String, dynamic>))
          .toList(),
      impassableMunicipalities: (json['impassable_municipalities'] as List<dynamic>? ?? const [])
          .map((m) => m.toString())
          .toList(),
      warning: json['warning']?.toString(),
      cachedAt: DateTime.tryParse(json['cached_at']?.toString() ?? ''),
    );
  }
}

class GeofenceArrivalResult {
  const GeofenceArrivalResult({
    required this.success,
    required this.areaId,
    required this.occupancy,
    required this.capacity,
    required this.status,
    required this.statusLabel,
    required this.availableSlots,
  });

  final bool success;
  final int areaId;
  final int occupancy;
  final int capacity;
  final String status;
  final String statusLabel;
  final int availableSlots;

  factory GeofenceArrivalResult.fromApi(Map<String, dynamic> json) {
    return GeofenceArrivalResult(
      success: json['success'] == true,
      areaId: (json['area_id'] as num?)?.toInt() ?? 0,
      occupancy: (json['occupancy'] as num?)?.toInt() ?? 0,
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'grey',
      statusLabel: json['status_label']?.toString() ?? '',
      availableSlots: (json['available_slots'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReportSubmitResult {
  const ReportSubmitResult({
    required this.trackingId,
    required this.message,
    required this.duplicate,
    this.replayed = false,
  });

  final String trackingId;
  final String message;

  /// Merged into an already-active incident instead of stored as its own.
  final bool duplicate;

  /// A retry of a report the backend had already stored under the same
  /// `client_report_id`; [trackingId] is that stored report's.
  final bool replayed;
}

/// Why a report submission failed.
class ReportSubmitException implements Exception {
  const ReportSubmitException({this.statusCode, this.serverMessage});

  /// Null when the request never got a response (no connection, timeout).
  final int? statusCode;

  /// The API's own `message`, when it sent one.
  final String? serverMessage;

  @override
  String toString() => 'ReportSubmitException($statusCode, $serverMessage)';
}
