import '../models/reporter_models.dart';

abstract class ReporterService {
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

  Future<EvacuationRankedResult> loadNearestEvacuationCenters({
    required double lat,
    required double lon,
    int groupSize = 1,
  });

  Future<GeofenceArrivalResult> confirmEvacuationArrival({
    required int areaId,
    int? reportId,
  });
}
