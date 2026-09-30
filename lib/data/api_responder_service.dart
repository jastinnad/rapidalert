import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/responder_models.dart';
import 'backend_features.dart';
import 'offline_cache.dart' show isNetworkError;
import 'responder_service.dart';

class ApiResponderService implements ResponderService {
  ApiResponderService({
    required String baseUrl,
    required String bearerToken,
    required int responderUserId,
  }) : _baseUrl = baseUrl,
       _bearerToken = bearerToken,
       _responderUserId = responderUserId {
    _bootstrap();
  }

  final String _baseUrl;
  final String _bearerToken;
  final int _responderUserId;

  final _reportsController = StreamController<List<IncidentReport>>.broadcast();
  final _eventsController =
      StreamController<List<CoordinationEvent>>.broadcast();
  final _trackingController = StreamController<GeoPoint>.broadcast();
  final _chatController = StreamController<List<ChatMessage>>.broadcast();
  final _followUpsController = StreamController<List<FollowUp>>.broadcast();
  final _evacuationController = StreamController<List<EvacuationRecordEntry>>.broadcast();
  final _announcementsController = StreamController<List<Announcement>>.broadcast();
  final _resourcesController = StreamController<List<ResourceRequestEntry>>.broadcast();
  final _reportListStatusController = StreamController<ReportListStatus>.broadcast();
  final _assignmentAlertsController = StreamController<AssignmentAlert>.broadcast();

  ReportListStatus _reportListStatus = const ReportListStatus();

  /// Report IDs in the last successfully loaded list; null before the first
  /// load, which is the baseline (only assignments made after it are new).
  Set<String>? _knownReportIds;
  final _announcedNotificationIds = <int>{};

  final List<IncidentReport> _reports = [];
  final List<CoordinationEvent> _events = [];
  final List<ChatMessage> _chatMessages = [];
  final List<FollowUp> _followUps = [];
  final List<EvacuationRecordEntry> _evacuationRecords = [];
  final List<Announcement> _announcements = [];
  final List<ResourceRequestEntry> _resourceRequests = [];

  Timer? _reportsPollTimer;
  Timer? _eventsPollTimer;
  Timer? _activeTrackingPollTimer;
  Timer? _followUpsPollTimer;
  Timer? _evacuationPollTimer;
  Timer? _announcementsPollTimer;
  Timer? _resourcesPollTimer;
  StreamSubscription<Position>? _gpsSub;
  Timer? _gpsHeartbeat;
  DateTime? _lastGpsPingAt;

  /// Null until the first real GPS fix; never a made-up position.
  GeoPoint? _responderPoint;
  String? _activeReportId;
  List<ActiveTrackingAssignment> _activeTrackingAssignments = const [];

  @override
  Stream<List<IncidentReport>> get reportsStream => _reportsController.stream;

  @override
  Stream<List<CoordinationEvent>> get eventsStream => _eventsController.stream;

  @override
  Stream<GeoPoint> get responderTrackingStream => _trackingController.stream;

  @override
  Stream<List<ChatMessage>> get chatStream => _chatController.stream;

  @override
  List<IncidentReport> get reports => List.unmodifiable(_reports);

  @override
  Stream<ReportListStatus> get reportListStatusStream => _reportListStatusController.stream;

  @override
  ReportListStatus get reportListStatus => _reportListStatus;

  @override
  Future<void> refreshReports() => _refreshReports();

  @override
  Stream<AssignmentAlert> get assignmentAlerts => _assignmentAlertsController.stream;

  @override
  GeoPoint? get currentResponderPoint => _responderPoint;

  @override
  bool get isSharingLocation => _gpsSub != null;

  @override
  List<ChatMessage> messagesFor(String reportId) {
    _activeReportId = reportId;
    return _chatMessages.where((m) => m.reportId == reportId).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  @override
  Future<void> updateReportStatus(String reportId, ReportStatus status) async {
    final endpoint = Uri.parse(
      '$_baseUrl/api/responder/reports/$reportId/status',
    );

    final response = await http.post(
      endpoint,
      headers: _headers,
      body: jsonEncode({'status': _apiStatus(status)}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to update report status: ${response.body}');
    }

    await _refreshReports();
    await _refreshEvents();
    await _refreshActiveTracking();
  }

  @override
  Future<void> sendResponderMessage({
    required String reportId,
    required int receiverId,
    required String text,
  }) async {
    final endpoint = Uri.parse('$_baseUrl/api/reports/messages');

    final response = await http.post(
      endpoint,
      headers: _headers,
      body: jsonEncode({
        'report_id': int.tryParse(reportId) ?? reportId,
        'receiver_id': receiverId,
        'message': text,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to send message: ${response.body}');
    }

    await _refreshMessages(reportId);
    await _refreshEvents();
  }

  @override
  Stream<List<FollowUp>> get followUpsStream => _followUpsController.stream;

  @override
  List<FollowUp> get followUps => List.unmodifiable(_followUps);

  @override
  Future<void> createFollowUp({
    required String reportId,
    required String reason,
    String? notes,
    required DateTime scheduledAt,
    required FollowUpPriority priority,
  }) async {
    final endpoint = Uri.parse('$_baseUrl/api/responder/follow-ups');
    final response = await http.post(
      endpoint,
      headers: _headers,
      body: jsonEncode({
        'incident_report_id': int.tryParse(reportId) ?? reportId,
        'assigned_to_responder_user_id': _responderUserId,
        'reason': reason,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'scheduled_at': _formatDateTime(scheduledAt),
        'priority': _apiPriority(priority),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to create follow-up: ${response.body}');
    }

    await _refreshFollowUps();
  }

  @override
  Future<void> completeFollowUp(String followUpId) async {
    final endpoint = Uri.parse(
      '$_baseUrl/api/responder/follow-ups/$followUpId/complete',
    );
    final response = await http.patch(endpoint, headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to complete follow-up: ${response.body}');
    }

    await _refreshFollowUps();
  }

  @override
  Stream<List<EvacuationRecordEntry>> get evacuationRecordsStream => _evacuationController.stream;

  @override
  List<EvacuationRecordEntry> get evacuationRecords => List.unmodifiable(_evacuationRecords);

  @override
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
  }) async {
    final endpoint = Uri.parse('$_baseUrl/api/responder/evacuation-records');
    final response = await http.post(
      endpoint,
      headers: _headers,
      body: jsonEncode({
        'tracking_id': trackingId,
        'hazard_type': hazardType,
        'barangay': barangay,
        'center_name': centerName,
        'evac_status': _apiEvacStatus(status),
        'total_evacuees': totalEvacuees,
        'male_count': maleCount,
        'female_count': femaleCount,
        'children_count': childrenCount,
        'seniors_count': seniorsCount,
        'pregnant_count': pregnantCount,
        'pwd_count': pwdCount,
        if (fieldNotes != null && fieldNotes.isNotEmpty) 'field_notes': fieldNotes,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to save evacuation record: ${response.body}');
    }

    await _refreshEvacuationRecords();
  }

  @override
  Stream<List<Announcement>> get announcementsStream => _announcementsController.stream;

  @override
  List<Announcement> get announcements => List.unmodifiable(_announcements);

  @override
  Stream<List<ResourceRequestEntry>> get resourceRequestsStream => _resourcesController.stream;

  @override
  List<ResourceRequestEntry> get resourceRequests => List.unmodifiable(_resourceRequests);

  @override
  Future<void> createResourceRequest({
    required String reportId,
    required String category,
    required String itemName,
    required int quantityRequested,
    String? unit,
    required ResourcePriority priority,
    String? locationHint,
    String? notes,
  }) async {
    final endpoint = Uri.parse('$_baseUrl/api/responder/resources');
    final response = await http.post(
      endpoint,
      headers: _headers,
      body: jsonEncode({
        'incident_report_id': int.tryParse(reportId) ?? reportId,
        'category': category,
        'item_name': itemName,
        'quantity_requested': quantityRequested,
        if (unit != null && unit.isNotEmpty) 'unit': unit,
        'priority': _apiResourcePriority(priority),
        if (locationHint != null && locationHint.isNotEmpty) 'location_hint': locationHint,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to submit resource request: ${response.body}');
    }

    await _refreshResourceRequests();
  }

  @override
  void dispose() {
    _reportsPollTimer?.cancel();
    _eventsPollTimer?.cancel();
    _activeTrackingPollTimer?.cancel();
    _gpsHeartbeat?.cancel();
    _gpsSub?.cancel();
    _followUpsPollTimer?.cancel();
    _evacuationPollTimer?.cancel();
    _announcementsPollTimer?.cancel();
    _resourcesPollTimer?.cancel();
    _reportsController.close();
    _eventsController.close();
    _trackingController.close();
    _chatController.close();
    _followUpsController.close();
    _evacuationController.close();
    _announcementsController.close();
    _resourcesController.close();
    _reportListStatusController.close();
    _assignmentAlertsController.close();
  }

  Future<void> _bootstrap() async {
    _reportsController.add(const <IncidentReport>[]);
    _eventsController.add(const <CoordinationEvent>[]);
    _chatController.add(const <ChatMessage>[]);
    _followUpsController.add(const <FollowUp>[]);
    _evacuationController.add(const <EvacuationRecordEntry>[]);
    _announcementsController.add(const <Announcement>[]);
    _resourcesController.add(const <ResourceRequestEntry>[]);

    // Each _refresh* below for an endpoint that production doesn't have yet
    // returns without a request (see BackendFeatures), and its poll timer is
    // only started once the endpoint exists.
    await _refreshReports();
    await _refreshEvents();
    await _refreshFollowUps();
    await _refreshEvacuationRecords();
    await _refreshAnnouncements();
    await _refreshResourceRequests();

    _reportsPollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _refreshReports();
    });

    _eventsPollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _refreshEvents();
      if (_activeReportId != null) {
        _refreshMessages(_activeReportId!);
      }
    });

    await _refreshActiveTracking();
    _activeTrackingPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshActiveTracking();
    });

    if (BackendFeatures.followUps) {
      _followUpsPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _refreshFollowUps();
      });
    }

    if (BackendFeatures.evacuationRecords) {
      _evacuationPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _refreshEvacuationRecords();
      });
    }

    if (BackendFeatures.responderAnnouncements) {
      _announcementsPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        _refreshAnnouncements();
      });
    }

    if (BackendFeatures.resources) {
      _resourcesPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _refreshResourceRequests();
      });
    }
  }

  /// Never throws: a failed load is reported through [reportListStatus] and
  /// the last good list is kept (it used to throw inside [_bootstrap] when
  /// the app started offline, so polling never began).
  Future<void> _refreshReports() async {
    final endpoint = Uri.parse('$_baseUrl/api/responder/reports');
    final http.Response response;
    try {
      response = await http.get(endpoint, headers: _headers).timeout(const Duration(seconds: 20));
    } catch (e) {
      _setReportListError(
        isNetworkError(e)
            ? "You're offline. Assigned reports can't be refreshed until you reconnect."
            : "Couldn't load your assigned reports.",
      );
      return;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _setReportListError("Couldn't load your assigned reports.");
      return;
    }

    final List<IncidentReport> loaded;
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final payload = (json['reports'] as List<dynamic>? ?? const []);
      loaded = payload.map((item) => item as Map<String, dynamic>).map(_reportFromApi).toList();
    } catch (_) {
      _setReportListError("Couldn't load your assigned reports.");
      return;
    }

    _reports
      ..clear()
      ..addAll(loaded);

    _reportsController.add(List.unmodifiable(_reports));
    _setReportListStatus(ReportListStatus(lastLoadedAt: DateTime.now()));
    _announceNewAssignments();

    if (_activeReportId != null) {
      await _refreshMessages(_activeReportId!);
    }
  }

  void _setReportListStatus(ReportListStatus status) {
    _reportListStatus = status;
    if (!_reportListStatusController.isClosed) _reportListStatusController.add(status);
  }

  void _setReportListError(String message) =>
      _setReportListStatus(ReportListStatus(lastLoadedAt: _reportListStatus.lastLoadedAt, errorMessage: message));

  void _announceNewAssignments() {
    final ids = _reports.map((r) => r.id).toSet();
    final known = _knownReportIds;
    _knownReportIds = ids;
    if (known == null) return;
    for (final id in ids.difference(known)) {
      unawaited(_announceAssignment(id));
    }
  }

  /// Shows the backend's own notification for a newly assigned report:
  /// "New assignment: …" (one-click assign) or "Responder has been assigned
  /// to report …" (the assignment queue). With neither, nothing is shown —
  /// the report is in the list anyway. Best-effort; not retried.
  Future<void> _announceAssignment(String reportId) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/api/reports/notifications',
      ).replace(queryParameters: {'report_id': reportId});
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final items = (jsonDecode(response.body) as Map<String, dynamic>)['notifications'] as List<dynamic>? ?? const [];
      Map<String, dynamic>? match;
      for (final item in items.cast<Map<String, dynamic>>()) {
        // The backend lists newest first.
        final message = item['message']?.toString() ?? '';
        if (message.startsWith('New assignment') || message.contains('has been assigned')) {
          match = item;
          break;
        }
      }
      final notificationId = (match?['id'] as num?)?.toInt();
      if (match == null || notificationId == null || !_announcedNotificationIds.add(notificationId)) return;

      if (!_assignmentAlertsController.isClosed) {
        _assignmentAlertsController.add(
          AssignmentAlert(notificationId: notificationId, reportId: reportId, message: match['message'].toString()),
        );
      }
    } catch (_) {
      // Best-effort: the report already shows in the assigned list.
    }
  }

  Future<void> _refreshEvents() async {
    if (!BackendFeatures.coordinationFeed) return;
    final endpoint = Uri.parse('$_baseUrl/api/responder/coordination/events');
    final response = await http.get(endpoint, headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final payload = (json['events'] as List<dynamic>? ?? const []);

    _events
      ..clear()
      ..addAll(
        payload.map((item) => item as Map<String, dynamic>).map(_eventFromApi),
      );

    _eventsController.add(List.unmodifiable(_events));
  }

  Future<void> _refreshMessages(String reportId) async {
    final endpoint = Uri.parse(
      '$_baseUrl/api/reports/messages',
    ).replace(queryParameters: {'report_id': reportId});
    final response = await http.get(endpoint, headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final payload = (json['messages'] as List<dynamic>? ?? const []);

    _chatMessages
      ..removeWhere((m) => m.reportId == reportId)
      ..addAll(
        payload
            .map((item) => item as Map<String, dynamic>)
            .map((item) => _chatMessageFromApi(item, reportId)),
      );

    _chatController.add(List.unmodifiable(_chatMessages));
  }

  Future<void> _refreshFollowUps() async {
    if (!BackendFeatures.followUps) return;
    final endpoint = Uri.parse('$_baseUrl/api/responder/follow-ups/upcoming');
    final response = await http.get(endpoint, headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final payload = (json['follow_ups'] as List<dynamic>? ?? const []);

    _followUps
      ..clear()
      ..addAll(
        payload.map((item) => item as Map<String, dynamic>).map(_followUpFromApi),
      );

    _followUpsController.add(List.unmodifiable(_followUps));
  }

  Future<void> _refreshEvacuationRecords() async {
    if (!BackendFeatures.evacuationRecords) return;
    final endpoint = Uri.parse('$_baseUrl/api/responder/evacuation-records');
    final response = await http.get(endpoint, headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final payload = (json['records'] as List<dynamic>? ?? const []);

    _evacuationRecords
      ..clear()
      ..addAll(
        payload.map((item) => item as Map<String, dynamic>).map(_evacuationRecordFromApi),
      );

    _evacuationController.add(List.unmodifiable(_evacuationRecords));
  }

  Future<void> _refreshAnnouncements() async {
    if (!BackendFeatures.responderAnnouncements) return;
    final endpoint = Uri.parse('$_baseUrl/api/responder/announcements');
    final response = await http.get(endpoint, headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final payload = (json['announcements'] as List<dynamic>? ?? const []);

    _announcements
      ..clear()
      ..addAll(
        payload.map((item) => item as Map<String, dynamic>).map(_announcementFromApi),
      );

    _announcementsController.add(List.unmodifiable(_announcements));
  }

  Future<void> _refreshResourceRequests() async {
    if (!BackendFeatures.resources) return;
    final endpoint = Uri.parse('$_baseUrl/api/responder/resources');
    final response = await http.get(endpoint, headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final payload = (json['resources'] as List<dynamic>? ?? const []);

    _resourceRequests
      ..clear()
      ..addAll(
        payload.map((item) => item as Map<String, dynamic>).map(_resourceRequestFromApi),
      );

    _resourcesController.add(List.unmodifiable(_resourceRequests));
  }

  /// Polls which reports (if any) the responder is currently `en_route`/
  /// `on_scene` for, and starts/stops the real GPS stream accordingly — GPS
  /// never runs while there's no active assignment to push it to.
  /// Never throws on a network failure: it runs inside [_bootstrap], where
  /// an offline start used to abort before this poll was created, so GPS
  /// sharing never resumed for an en-route report. Keeps the last state.
  Future<void> _refreshActiveTracking() async {
    final endpoint = Uri.parse('$_baseUrl/api/responder/active-tracking');
    final http.Response response;
    try {
      response = await http.get(endpoint, headers: _headers).timeout(const Duration(seconds: 20));
    } catch (_) {
      return;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final payload = (json['assignments'] as List<dynamic>? ?? const []);
    final wasEmpty = _activeTrackingAssignments.isEmpty;
    _activeTrackingAssignments = payload
        .map((item) => ActiveTrackingAssignment.fromApi(item as Map<String, dynamic>))
        .toList();
    final isEmpty = _activeTrackingAssignments.isEmpty;

    if (wasEmpty && !isEmpty) {
      await _startGpsStream();
    } else if (!wasEmpty && isEmpty) {
      await _stopGpsTracking();
    }
  }

  Future<void> _stopGpsTracking() async {
    _gpsHeartbeat?.cancel();
    _gpsHeartbeat = null;
    await _gpsSub?.cancel();
    _gpsSub = null;
  }

  Future<void> _startGpsStream() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      return;
    }

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen(_onPosition);

    // The stream only fires after 15m of movement, so a responder standing
    // still at the scene sends nothing and the reporter's card flips to
    // "Last known position" after 60s. Re-check in with a fresh fix while
    // stationary. If no fix can be had (GPS lost), nothing is sent and the
    // card honestly goes stale.
    _gpsHeartbeat?.cancel();
    _gpsHeartbeat = Timer.periodic(_gpsHeartbeatInterval, (_) => _gpsCheckIn());
  }

  // Check every 20s and skip only if a ping went out in the last 15s. Skipping
  // on the full interval would skip every other tick (each ping lands just
  // after a tick), leaving ~50s gaps against the reporter's 60s stale mark.
  static const _gpsHeartbeatInterval = Duration(seconds: 20);
  static const _gpsRecentPing = Duration(seconds: 15);

  Future<void> _gpsCheckIn() async {
    final last = _lastGpsPingAt;
    if (last != null && DateTime.now().difference(last) < _gpsRecentPing) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (_gpsSub == null) return; // tracking stopped while waiting for the fix
      _onPosition(position);
    } catch (_) {
      // No fix available — leave it to show as stale.
    }
  }

  void _onPosition(Position position) {
    _lastGpsPingAt = DateTime.now();
    final point = GeoPoint(lat: position.latitude, lng: position.longitude, recordedAt: position.timestamp);
    _responderPoint = point;
    _trackingController.add(point);

    for (final assignment in _activeTrackingAssignments) {
      _postTrackingToApi(assignment.reportId.toString());
    }
  }

  Future<void> _postTrackingToApi(String reportId) async {
    final endpoint = Uri.parse(
      '$_baseUrl/api/responder/reports/$reportId/tracking',
    );
    final point = _responderPoint;
    if (point == null) return;
    await http.post(
      endpoint,
      headers: _headers,
      body: jsonEncode({
        'latitude': point.lat,
        'longitude': point.lng,
      }),
    );
  }

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (_bearerToken.isNotEmpty) 'Authorization': 'Bearer $_bearerToken',
  };

  IncidentReport _reportFromApi(Map<String, dynamic> item) {
    final reportId = item['reportId'];
    final trackingId = item['trackingId']?.toString() ?? '';
    final id = reportId == null ? trackingId : reportId.toString();

    return IncidentReport(
      id: id,
      hazard: item['hazardType']?.toString() ?? 'Unknown',
      location: item['barangay']?.toString().trim().isNotEmpty == true
          ? item['barangay'].toString()
          : item['city']?.toString() ?? 'Unknown location',
      reporterName: item['reporterName']?.toString().trim().isNotEmpty == true
          ? item['reporterName'].toString()
          : 'Reporter',
      status: _statusFromApi(item['status']?.toString() ?? ''),
      needHelp: item['needHelp'] == true,
      updated: DateTime.fromMillisecondsSinceEpoch(
        (item['updatedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      // No default: a report without GPS must not appear at a made-up spot.
      reporterLat: _toDouble(item['latitude']),
      reporterLng: _toDouble(item['longitude']),
      reporterUserId: (item['reporterUserId'] as num?)?.toInt(),
    );
  }

  CoordinationEvent _eventFromApi(Map<String, dynamic> item) {
    return CoordinationEvent(
      id:
          item['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: item['title']?.toString() ?? 'Coordination update',
      message: item['message']?.toString() ?? '',
      priority: _priorityFromApi(item['priority']?.toString() ?? 'normal'),
      time:
          DateTime.tryParse(item['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  ChatMessage _chatMessageFromApi(Map<String, dynamic> item, String reportId) {
    final senderUserId = (item['senderId'] as num?)?.toInt() ?? 0;

    return ChatMessage(
      id:
          item['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      reportId: reportId,
      sender: item['senderName']?.toString() ?? 'Unknown',
      message: item['message']?.toString() ?? '',
      time:
          DateTime.tryParse(item['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      isResponder: senderUserId == _responderUserId,
    );
  }

  ReportStatus _statusFromApi(String value) {
    return switch (value.toLowerCase().trim()) {
      'en_route' => ReportStatus.enRoute,
      'on_scene' => ReportStatus.onScene,
      'resolved' => ReportStatus.resolved,
      'completed' => ReportStatus.completed,
      _ => ReportStatus.assigned,
    };
  }

  String _apiStatus(ReportStatus status) {
    return switch (status) {
      ReportStatus.assigned => 'assigned',
      ReportStatus.enRoute => 'en_route',
      ReportStatus.onScene => 'on_scene',
      ReportStatus.resolved => 'resolved',
      ReportStatus.completed => 'completed',
    };
  }

  FollowUp _followUpFromApi(Map<String, dynamic> item) {
    final incident = item['incident'] as Map<String, dynamic>?;

    return FollowUp(
      id: item['follow_up_id']?.toString() ?? '',
      reportId: item['incident_report_id']?.toString() ?? '',
      trackingId: incident?['tracking_id']?.toString() ?? '',
      hazard: incident?['hazard_type']?.toString() ?? 'Unknown',
      reason: item['reason']?.toString() ?? '',
      notes: item['notes']?.toString(),
      scheduledAt:
          DateTime.tryParse(item['scheduled_at']?.toString() ?? '') ??
          DateTime.now(),
      priority: _followUpPriorityFromApi((item['priority'] as num?)?.toInt() ?? 2),
      isCompleted: item['status']?.toString() == 'completed',
    );
  }

  FollowUpPriority _followUpPriorityFromApi(int value) {
    return switch (value) {
      1 => FollowUpPriority.high,
      3 => FollowUpPriority.low,
      _ => FollowUpPriority.medium,
    };
  }

  int _apiPriority(FollowUpPriority priority) {
    return switch (priority) {
      FollowUpPriority.high => 1,
      FollowUpPriority.medium => 2,
      FollowUpPriority.low => 3,
    };
  }

  EvacuationRecordEntry _evacuationRecordFromApi(Map<String, dynamic> item) {
    return EvacuationRecordEntry(
      trackingId: item['tracking_id']?.toString() ?? '',
      hazardType: item['hazard_type']?.toString() ?? 'flood',
      barangay: item['barangay']?.toString() ?? '',
      centerName: item['center_name']?.toString() ?? '',
      status: _evacStatusFromApi(item['evac_status']?.toString() ?? ''),
      totalEvacuees: (item['total_evacuees'] as num?)?.toInt() ?? 0,
      maleCount: (item['male_count'] as num?)?.toInt() ?? 0,
      femaleCount: (item['female_count'] as num?)?.toInt() ?? 0,
      childrenCount: (item['children_count'] as num?)?.toInt() ?? 0,
      seniorsCount: (item['seniors_count'] as num?)?.toInt() ?? 0,
      pregnantCount: (item['pregnant_count'] as num?)?.toInt() ?? 0,
      pwdCount: (item['pwd_count'] as num?)?.toInt() ?? 0,
      fieldNotes: item['field_notes']?.toString(),
      updatedAt:
          DateTime.tryParse(item['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  EvacStatus _evacStatusFromApi(String value) {
    return switch (value.toLowerCase().trim()) {
      'preparing' => EvacStatus.preparing,
      'completed' => EvacStatus.completed,
      'needs-support' => EvacStatus.needsSupport,
      _ => EvacStatus.ongoing,
    };
  }

  String _apiEvacStatus(EvacStatus status) {
    return switch (status) {
      EvacStatus.preparing => 'preparing',
      EvacStatus.ongoing => 'ongoing',
      EvacStatus.completed => 'completed',
      EvacStatus.needsSupport => 'needs-support',
    };
  }

  Announcement _announcementFromApi(Map<String, dynamic> item) {
    return Announcement(
      id: item['id']?.toString() ?? '',
      title: item['title']?.toString() ?? '',
      message: item['message']?.toString() ?? '',
      priority: _announcementPriorityFromApi(item['priority']?.toString() ?? 'normal'),
      hazardType: item['hazardType']?.toString() ?? '',
      publishedAt:
          DateTime.tryParse(item['publishedAtIso']?.toString() ?? '') ?? DateTime.now(),
      publishedAgo: item['publishedAgo']?.toString() ?? '',
    );
  }

  AnnouncementPriority _announcementPriorityFromApi(String value) {
    return switch (value.toLowerCase().trim()) {
      'high' => AnnouncementPriority.high,
      'low' => AnnouncementPriority.low,
      _ => AnnouncementPriority.normal,
    };
  }

  ResourceRequestEntry _resourceRequestFromApi(Map<String, dynamic> item) {
    final trackingId = item['trackingId']?.toString() ?? '';
    final reportId = item['incidentReportId'];

    return ResourceRequestEntry(
      id: item['id']?.toString() ?? '',
      reportId: reportId?.toString() ?? '',
      trackingId: trackingId.isNotEmpty ? trackingId : (reportId?.toString() ?? ''),
      category: item['category']?.toString() ?? 'other',
      itemName: item['itemName']?.toString() ?? '',
      quantityRequested: (item['quantityRequested'] as num?)?.toInt() ?? 0,
      quantityFulfilled: (item['quantityFulfilled'] as num?)?.toInt() ?? 0,
      unit: (item['unit']?.toString().isNotEmpty ?? false) ? item['unit'].toString() : null,
      priority: _resourcePriorityFromApi(item['priority']?.toString() ?? 'normal'),
      status: _resourceStatusFromApi(item['status']?.toString() ?? 'pending'),
      locationHint:
          (item['locationHint']?.toString().isNotEmpty ?? false) ? item['locationHint'].toString() : null,
      notes: (item['notes']?.toString().isNotEmpty ?? false) ? item['notes'].toString() : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (item['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  ResourcePriority _resourcePriorityFromApi(String value) {
    return switch (value.toLowerCase().trim()) {
      'low' => ResourcePriority.low,
      'high' => ResourcePriority.high,
      'critical' => ResourcePriority.critical,
      _ => ResourcePriority.normal,
    };
  }

  ResourceStatus _resourceStatusFromApi(String value) {
    return switch (value.toLowerCase().trim()) {
      'approved' => ResourceStatus.approved,
      'in_progress' => ResourceStatus.inProgress,
      'fulfilled' => ResourceStatus.fulfilled,
      'cancelled' => ResourceStatus.cancelled,
      _ => ResourceStatus.pending,
    };
  }

  String _apiResourcePriority(ResourcePriority priority) {
    return switch (priority) {
      ResourcePriority.low => 'low',
      ResourcePriority.normal => 'normal',
      ResourcePriority.high => 'high',
      ResourcePriority.critical => 'critical',
    };
  }

  /// The backend validates scheduled_at against the server's clock in
  /// Asia/Manila (see config/app.php), which rarely matches the device's own
  /// timezone. Convert to the true UTC instant, then to Manila's fixed
  /// UTC+8 (no DST), so the naive datetime string means what the server
  /// thinks it means regardless of what timezone the device is set to.
  String _formatDateTime(DateTime dt) {
    final manila = dt.toUtc().add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${manila.year}-${two(manila.month)}-${two(manila.day)} ${two(manila.hour)}:${two(manila.minute)}:${two(manila.second)}';
  }

  CoordinationPriority _priorityFromApi(String value) {
    return switch (value.toLowerCase().trim()) {
      'normal' => CoordinationPriority.normal,
      'important' => CoordinationPriority.important,
      'urgent' => CoordinationPriority.urgent,
      'critical' => CoordinationPriority.critical,
      _ => CoordinationPriority.normal,
    };
  }

  double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
