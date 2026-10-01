import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/reporter_models.dart';
import '../models/responder_models.dart' show ChatMessage;
import 'backend_features.dart';
import 'offline_cache.dart';
import 'reporter_service.dart';

class ApiReporterService implements ReporterService {
  ApiReporterService({required String baseUrl, required String bearerToken, int? myUserId, OfflineCache? cache})
    : _baseUrl = baseUrl,
      _bearerToken = bearerToken,
      _myUserId = myUserId,
      _cache = cache ?? OfflineCache();

  final String _baseUrl;
  final String _bearerToken;
  final int? _myUserId;
  final OfflineCache _cache;

  /// Generous enough for a photo upload on a weak mobile connection.
  static const _submitTimeout = Duration(seconds: 90);

  /// For reads, so a dead connection turns into "offline" instead of an
  /// endless spinner.
  static const _readTimeout = Duration(seconds: 20);

  /// Cache entries are per account, so one account never sees another's.
  String get _cacheOwner => _myUserId?.toString() ?? 'guest';

  @override
  int? get currentUserId => _myUserId;

  /// Guests (no account) construct this service with an empty token — the
  /// backend's reporting routes accept requests with or without one.
  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (_bearerToken.isNotEmpty) 'Authorization': 'Bearer $_bearerToken',
  };

  Map<String, String> get _jsonHeaders => {
    ..._headers,
    'Content-Type': 'application/json',
  };

  @override
  Future<ReportFormOptions> loadHazardOptions() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/reporter/hazard-options'),
      headers: _headers,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load hazard options: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final options = (json['options'] as List<dynamic>? ?? const []);
    return ReportFormOptions(
      hazardOptions: options.map((item) => HazardOption.fromApi(item as Map<String, dynamic>)).toList(),
      situationConfig: CurrentSituationConfig.fromApi(json['current_situation'] as Map<String, dynamic>?),
      rapidAssessment: RapidAssessmentPrefill.fromApi(json['active_rapid_assessment'] as Map<String, dynamic>?),
    );
  }

  @override
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
    String? phone,
  }) async {
    final endpoint = Uri.parse('$_baseUrl/api/reporter/reports');
    final request = http.MultipartRequest('POST', endpoint)
      ..headers.addAll(_headers)
      ..fields['hazard_type'] = hazardType
      ..fields['particular'] = particular
      ..fields['particular_color'] = particularColor
      ..fields['particular_detail'] = particularDetail
      ..fields['region'] = region
      ..fields['province'] = province
      ..fields['city'] = city
      ..fields['barangay'] = barangay
      ..fields['purok'] = purok
      ..fields['house_no'] = houseNo
      ..fields['pregnant_count'] = pregnantCount.toString()
      ..fields['elderly_count'] = elderlyCount.toString()
      ..fields['child_count'] = childCount.toString()
      ..fields['pwd_count'] = pwdCount.toString();

    if (needHelp) {
      // Laravel's `boolean` validation rule accepts 1/0/"1"/"0"/true/false,
      // but NOT the literal strings "true"/"false" that .toString() would
      // produce here — send "1" (and omit the field when false, since it's
      // nullable).
      request.fields['need_help'] = '1';
    }

    if (landmark != null && landmark.isNotEmpty) {
      request.fields['landmark'] = landmark;
    }
    if (latitude != null && longitude != null) {
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
    }
    if (imagePath != null) {
      request.files.add(await http.MultipartFile.fromPath('emergency_image', imagePath));
    }
    if (clientReportId != null && clientReportId.isNotEmpty) {
      request.fields['client_report_id'] = clientReportId;
    }
    if (phone != null && phone.isNotEmpty) {
      request.fields['phone'] = phone;
    }

    // `MultipartRequest.fields` is a Map, so it can't hold repeated
    // "needs[]" keys the way a browser form submit would. Laravel parses
    // indexed keys ("needs[0]", "needs[1]", ...) into the same array shape,
    // so we send those instead.
    for (var i = 0; i < needs.length; i++) {
      request.fields['needs[$i]'] = needs[i];
    }
    for (var i = 0; i < currentSituation.length; i++) {
      request.fields['current_situation[$i]'] = currentSituation[i];
    }

    // No response (offline, dropped, timed out) says nothing about whether
    // the backend stored the report; the caller retries with the same
    // client_report_id, which the backend treats as the same report.
    final http.Response response;
    try {
      response = await request.send().then(http.Response.fromStream).timeout(_submitTimeout);
    } on http.ClientException {
      throw const ReportSubmitException();
    } on IOException {
      throw const ReportSubmitException();
    } on TimeoutException {
      throw const ReportSubmitException();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? serverMessage;
      try {
        serverMessage = (jsonDecode(response.body) as Map<String, dynamic>)['message']?.toString();
      } catch (_) {
        // Not JSON (e.g. a proxy error page); the status code is enough.
      }
      throw ReportSubmitException(statusCode: response.statusCode, serverMessage: serverMessage);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ReportSubmitResult(
      trackingId: json['tracking_id']?.toString() ?? '',
      message: json['message']?.toString() ?? 'Report submitted.',
      duplicate: json['duplicate'] == true,
      replayed: json['replayed'] == true,
    );
  }

  @override
  Future<TrackedReport?> trackReport({String? trackingId, String? clientReportId}) async {
    final queryParameters = <String, String>{
      if (trackingId != null && trackingId.isNotEmpty) 'tracking_id': trackingId,
      if (clientReportId != null && clientReportId.isNotEmpty) 'client_report_id': clientReportId,
    };
    final uri = Uri.parse(
      '$_baseUrl/api/reporter/reports/track',
    ).replace(queryParameters: queryParameters.isEmpty ? null : queryParameters);
    final response = await http.get(uri, headers: _headers).timeout(_readTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to track report: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['found'] != true || json['report'] == null) {
      return null;
    }

    final report = json['report'] as Map<String, dynamic>;
    await _cache.save('tracked_report.$_cacheOwner', report);
    return TrackedReport.fromApi(report);
  }

  @override
  Future<CachedCopy<TrackedReport>?> cachedTrackedReport({String? trackingId}) async {
    final copy = await _cache.load('tracked_report.$_cacheOwner');
    if (copy == null) return null;
    final report = TrackedReport.fromApi(copy.value);
    if (trackingId != null && trackingId.toUpperCase() != report.trackingId.toUpperCase()) return null;
    return CachedCopy(report, copy.savedAt);
  }

  @override
  Future<StatusHistory?> loadStatusHistory({required String trackingId, String? clientReportId}) async {
    if (!BackendFeatures.reporterTrackingDetails) return null;
    final uri = Uri.parse('$_baseUrl/api/reporter/reports/history').replace(
      queryParameters: {
        'tracking_id': trackingId,
        if (clientReportId != null && clientReportId.isNotEmpty) 'client_report_id': clientReportId,
      },
    );
    final response = await http.get(uri, headers: _headers).timeout(_readTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load status history: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['found'] == true ? StatusHistory.fromApi(json) : null;
  }

  @override
  Future<List<ReportNotification>> loadReportNotifications(int reportId) async {
    final uri = Uri.parse(
      '$_baseUrl/api/reports/notifications',
    ).replace(queryParameters: {'report_id': reportId.toString()});
    final response = await http.get(uri, headers: _headers).timeout(_readTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load notifications: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['notifications'] as List<dynamic>? ?? const [])
        .map((item) => ReportNotification.fromApi(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<bool> submittedReportExists(String clientReportId) async {
    // Read-only; answers only {"exists": true|false}. A signed-in reporter
    // matches only their own reports; a guest matches any guest report with
    // the ID (guest reports have no server-side ownership binding).
    final uri = Uri.parse('$_baseUrl/api/reporter/report-submission-status/${Uri.encodeComponent(clientReportId)}');
    final http.Response response;
    try {
      response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
    } on http.ClientException {
      throw const ReportSubmitException();
    } on IOException {
      throw const ReportSubmitException();
    } on TimeoutException {
      throw const ReportSubmitException();
    }

    Object? exists;
    try {
      exists = (jsonDecode(response.body) as Map<String, dynamic>)['exists'];
    } catch (_) {
      exists = null;
    }
    if (response.statusCode == 200 && exists is bool) return exists;
    throw ReportSubmitException(statusCode: response.statusCode);
  }

  @override
  Future<ReporterProfile> loadProfile() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/reporter/profile'), headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load profile: ${response.body}');
    }

    return ReporterProfile.fromApi(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
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
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/reporter/profile'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'phone': phone,
        'gender': ?gender,
        'house_no': houseNo,
        'purok': purok,
        'barangay': barangay,
        if (landmark != null && landmark.isNotEmpty) 'landmark': landmark,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to update profile: ${response.body}');
    }
  }

  @override
  Future<CheckInStatus> setCheckInStatus(CheckInStatus status) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/reporter/user-status'),
      headers: _jsonHeaders,
      body: jsonEncode({'current_status': status.apiValue}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to update status: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CheckInStatusApi.fromApi(json['status']?.toString() ?? status.apiValue);
  }

  @override
  Future<CheckInStatus> loadCheckInStatus() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/reporter/user-status'),
      headers: _headers,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load status: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CheckInStatusApi.fromApi(json['status']?.toString() ?? 'im_safe');
  }

  @override
  Future<EvacuationRankedResult> loadNearestEvacuationCenters({
    required double lat,
    required double lon,
    int groupSize = 1,
    bool fromUserLocation = true,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/evacuation/ranked').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'group_size': groupSize.toString(),
      },
    );
    final response = await http.get(uri, headers: _headers).timeout(_readTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load evacuation centers: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    await _cache.save('evacuation_centers.$_cacheOwner', fromUserLocation ? json : _withoutDistances(json));
    return EvacuationRankedResult.fromApi(json);
  }

  /// The ranked list minus each center's distance and ETA, which were
  /// measured from a fallback point, not from the user.
  static Map<String, dynamic> _withoutDistances(Map<String, dynamic> json) => {
    ...json,
    'centres': [
      for (final centre in (json['centres'] as List<dynamic>? ?? const []))
        {...(centre as Map<String, dynamic>)}
          ..remove('distance_km')
          ..remove('eta_minutes'),
    ],
  };

  @override
  Future<CachedCopy<EvacuationRankedResult>?> cachedEvacuationCenters() async {
    final copy = await _cache.load('evacuation_centers.$_cacheOwner');
    return copy == null ? null : CachedCopy(EvacuationRankedResult.fromApi(copy.value), copy.savedAt);
  }

  @override
  Future<GeofenceArrivalResult> confirmEvacuationArrival({
    required int areaId,
    int? reportId,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/evacuation/geofence-arrive'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'area_id': areaId,
        'report_id': ?reportId,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to confirm arrival: ${response.body}');
    }

    return GeofenceArrivalResult.fromApi(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<List<ChatMessage>> loadReportMessages(int reportId) async {
    final uri = Uri.parse(
      '$_baseUrl/api/reports/messages',
    ).replace(queryParameters: {'report_id': reportId.toString()});
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load messages: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (json['messages'] as List<dynamic>? ?? const []);
    return items.map((item) => _chatMessageFromApi(item as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> sendReportMessage({
    required int reportId,
    required int receiverId,
    required String text,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/reports/messages'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'report_id': reportId,
        'receiver_id': receiverId,
        'message': text,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to send message: ${response.body}');
    }
  }

  ChatMessage _chatMessageFromApi(Map<String, dynamic> json) {
    final senderId = (json['senderId'] as num?)?.toInt();
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      reportId: json['reportId']?.toString() ?? '',
      sender: json['senderName']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      time: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      // Only two parties can ever exist in one of these threads (enforced
      // server-side) — anything not sent by me was sent by the responder.
      isResponder: senderId != _myUserId,
    );
  }
}
