import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/responder_models.dart';
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

  final List<IncidentReport> _reports = [];
  final List<CoordinationEvent> _events = [];
  final List<ChatMessage> _chatMessages = [];
  final List<FollowUp> _followUps = [];
  final List<EvacuationRecordEntry> _evacuationRecords = [];
  final List<Announcement> _announcements = [];
  final List<ResourceRequestEntry> _resourceRequests = [];

  Timer? _reportsPollTimer;
  Timer? _eventsPollTimer;
  Timer? _trackingTimer;
  Timer? _followUpsPollTimer;
  Timer? _evacuationPollTimer;
  Timer? _announcementsPollTimer;
  Timer? _resourcesPollTimer;

  GeoPoint _responderPoint = const GeoPoint(lat: 13.9412, lng: 121.1631);
  String? _activeReportId;

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
  GeoPoint get currentResponderPoint => _responderPoint;

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

    final response = await http.put(
      endpoint,
      headers: _headers,
      body: jsonEncode({'status': _apiStatus(status)}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to update report status: ${response.body}');
    }

    await _refreshReports();
    await _refreshEvents();
  }

  @override
  Future<void> sendResponderMessage({
    required String reportId,
    required String text,
  }) async {
    final endpoint = Uri.parse(
      '$_baseUrl/api/responder/reports/$reportId/messages',
    );

    final response = await http.post(
      endpoint,
      headers: _headers,
      body: jsonEncode({'message': text}),
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
    _trackingTimer?.cancel();
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
  }

  Future<void> _bootstrap() async {
    _reportsController.add(const <IncidentReport>[]);
    _eventsController.add(const <CoordinationEvent>[]);
    _trackingController.add(_responderPoint);
    _chatController.add(const <ChatMessage>[]);
    _followUpsController.add(const <FollowUp>[]);
    _evacuationController.add(const <EvacuationRecordEntry>[]);
    _announcementsController.add(const <Announcement>[]);
    _resourcesController.add(const <ResourceRequestEntry>[]);

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

    _trackingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _simulateLocalTracking();
      _postTrackingToApi();
    });

    _followUpsPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshFollowUps();
    });

    _evacuationPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshEvacuationRecords();
    });

    _announcementsPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshAnnouncements();
    });

    _resourcesPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshResourceRequests();
    });
  }

  Future<void> _refreshReports() async {
    final endpoint = Uri.parse('$_baseUrl/api/responder/reports');
    final response = await http.get(endpoint, headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final payload = (json['reports'] as List<dynamic>? ?? const []);

    _reports
      ..clear()
      ..addAll(
        payload.map((item) => item as Map<String, dynamic>).map(_reportFromApi),
      );

    _reportsController.add(List.unmodifiable(_reports));

    if (_activeReportId != null) {
      await _refreshMessages(_activeReportId!);
    }
  }

  Future<void> _refreshEvents() async {
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
      '$_baseUrl/api/responder/reports/$reportId/messages',
    );
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

  void _simulateLocalTracking() {
    final random = Random();
    _responderPoint = GeoPoint(
      lat: _responderPoint.lat + (random.nextDouble() - 0.5) * 0.00035,
      lng: _responderPoint.lng + (random.nextDouble() - 0.5) * 0.00035,
    );
    _trackingController.add(_responderPoint);
  }

  Future<void> _postTrackingToApi() async {
    final reportId = _activeReportId;
    if (reportId == null) {
      return;
    }

    final endpoint = Uri.parse(
      '$_baseUrl/api/responder/reports/$reportId/tracking',
    );
    await http.post(
      endpoint,
      headers: _headers,
      body: jsonEncode({
        'latitude': _responderPoint.lat,
        'longitude': _responderPoint.lng,
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
      reporterLat: _toDouble(item['latitude']) ?? 13.9412,
      reporterLng: _toDouble(item['longitude']) ?? 121.1631,
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
    final normalized = value.toLowerCase().trim();
    return switch (normalized) {
      'assigned' || 'pending' => ReportStatus.assigned,
      'in-progress' || 'in_progress' || 'ongoing' => ReportStatus.inProgress,
      'need-help' || 'need_help' || 'critical' => ReportStatus.needHelp,
      'follow-up' || 'follow_up' => ReportStatus.followUp,
      'completed' || 'resolved' || 'cancelled' => ReportStatus.completed,
      _ => ReportStatus.assigned,
    };
  }

  String _apiStatus(ReportStatus status) {
    return switch (status) {
      ReportStatus.assigned => 'pending',
      ReportStatus.inProgress => 'in_progress',
      ReportStatus.needHelp => 'critical',
      ReportStatus.followUp => 'ongoing',
      ReportStatus.completed => 'resolved',
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
