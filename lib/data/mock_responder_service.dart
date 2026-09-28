import 'dart:async';
import 'dart:math';

import '../models/responder_models.dart';
import 'responder_service.dart';

class MockResponderService implements ResponderService {
  MockResponderService() {
    _seed();
    _startStreams();
  }

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

  late Timer _reportTimer;
  late Timer _eventTimer;
  late Timer _trackingTimer;

  GeoPoint _responderPoint = const GeoPoint(lat: 13.9412, lng: 121.1631);
  final _random = Random();

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
    final report = _reports.firstWhere(
      (r) => r.id == reportId,
      orElse: () => _reports.first,
    );
    _followUps.add(
      FollowUp(
        id: 'fu-${DateTime.now().microsecondsSinceEpoch}',
        reportId: reportId,
        trackingId: report.id,
        hazard: report.hazard,
        reason: reason,
        notes: notes,
        scheduledAt: scheduledAt,
        priority: priority,
        isCompleted: false,
      ),
    );
    _followUpsController.add(List.unmodifiable(_followUps));
  }

  @override
  Future<void> completeFollowUp(String followUpId) async {
    final index = _followUps.indexWhere((f) => f.id == followUpId);
    if (index < 0) {
      return;
    }
    final current = _followUps[index];
    _followUps[index] = FollowUp(
      id: current.id,
      reportId: current.reportId,
      trackingId: current.trackingId,
      hazard: current.hazard,
      reason: current.reason,
      notes: current.notes,
      scheduledAt: current.scheduledAt,
      priority: current.priority,
      isCompleted: true,
    );
    _followUpsController.add(List.unmodifiable(_followUps));
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
    final entry = EvacuationRecordEntry(
      trackingId: trackingId,
      hazardType: hazardType,
      barangay: barangay,
      centerName: centerName,
      status: status,
      totalEvacuees: totalEvacuees,
      maleCount: maleCount,
      femaleCount: femaleCount,
      childrenCount: childrenCount,
      seniorsCount: seniorsCount,
      pregnantCount: pregnantCount,
      pwdCount: pwdCount,
      fieldNotes: fieldNotes,
      updatedAt: DateTime.now(),
    );

    final index = _evacuationRecords.indexWhere((e) => e.trackingId == trackingId);
    if (index >= 0) {
      _evacuationRecords[index] = entry;
    } else {
      _evacuationRecords.insert(0, entry);
    }
    _evacuationController.add(List.unmodifiable(_evacuationRecords));
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
    final report = _reports.firstWhere(
      (r) => r.id == reportId,
      orElse: () => _reports.first,
    );
    _resourceRequests.insert(
      0,
      ResourceRequestEntry(
        id: 'res-${DateTime.now().microsecondsSinceEpoch}',
        reportId: reportId,
        trackingId: report.id,
        category: category,
        itemName: itemName,
        quantityRequested: quantityRequested,
        quantityFulfilled: 0,
        unit: unit,
        priority: priority,
        status: ResourceStatus.pending,
        locationHint: locationHint,
        notes: notes,
        createdAt: DateTime.now(),
      ),
    );
    _resourcesController.add(List.unmodifiable(_resourceRequests));
  }

  @override
  List<ChatMessage> messagesFor(String reportId) {
    final items = _chatMessages.where((m) => m.reportId == reportId).toList();
    items.sort((a, b) => a.time.compareTo(b.time));
    return items;
  }

  @override
  Future<void> sendResponderMessage({
    required String reportId,
    required int receiverId,
    required String text,
  }) async {
    final message = ChatMessage(
      id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
      reportId: reportId,
      sender: 'Responder',
      message: text,
      time: DateTime.now(),
      isResponder: true,
    );
    _chatMessages.add(message);
    _chatController.add(List.unmodifiable(_chatMessages));

    Future<void>.delayed(const Duration(milliseconds: 900), () {
      final autoReply = ChatMessage(
        id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
        reportId: reportId,
        sender: 'Reporter',
        message: 'Copy. We are at the barangay gym waiting for support.',
        time: DateTime.now(),
        isResponder: false,
      );
      _chatMessages.add(autoReply);
      _chatController.add(List.unmodifiable(_chatMessages));
      _events.insert(
        0,
        CoordinationEvent(
          id: 'evt-${DateTime.now().millisecondsSinceEpoch}',
          title: 'Reporter reply received',
          message: 'Report $reportId has a new reporter update.',
          priority: CoordinationPriority.important,
          time: DateTime.now(),
        ),
      );
      _eventsController.add(List.unmodifiable(_events));
    });
  }

  @override
  Future<void> updateReportStatus(String reportId, ReportStatus status) async {
    final index = _reports.indexWhere((r) => r.id == reportId);
    if (index < 0) {
      return;
    }

    final current = _reports[index];
    _reports[index] = current.copyWith(status: status, updated: DateTime.now());
    _reportsController.add(List.unmodifiable(_reports));

    _events.insert(
      0,
      CoordinationEvent(
        id: 'evt-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Status updated',
        message: 'Report $reportId changed to ${status.name}.',
        priority: CoordinationPriority.normal,
        time: DateTime.now(),
      ),
    );
    _eventsController.add(List.unmodifiable(_events));
  }

  @override
  GeoPoint get currentResponderPoint => _responderPoint;

  @override
  void dispose() {
    _reportTimer.cancel();
    _eventTimer.cancel();
    _trackingTimer.cancel();
    _reportsController.close();
    _eventsController.close();
    _trackingController.close();
    _chatController.close();
    _followUpsController.close();
    _evacuationController.close();
    _announcementsController.close();
    _resourcesController.close();
  }

  void _seed() {
    _reports.addAll([
      IncidentReport(
        id: 'RA-2026-0012',
        hazard: 'Flood',
        location: 'Barangay Banaybanay',
        reporterName: 'A. Mendoza',
        status: ReportStatus.enRoute,
        needHelp: true,
        updated: DateTime.now().subtract(const Duration(minutes: 9)),
        reporterLat: 13.9420,
        reporterLng: 121.1654,
      ),
      IncidentReport(
        id: 'RA-2026-0019',
        hazard: 'Fire',
        location: 'Barangay Marawoy',
        reporterName: 'S. Ramos',
        status: ReportStatus.assigned,
        needHelp: false,
        updated: DateTime.now().subtract(const Duration(minutes: 16)),
        reporterLat: 13.9492,
        reporterLng: 121.1492,
      ),
      IncidentReport(
        id: 'RA-2026-0024',
        hazard: 'Medical',
        location: 'Barangay Tambo',
        reporterName: 'J. Cruz',
        status: ReportStatus.assigned,
        needHelp: true,
        updated: DateTime.now().subtract(const Duration(minutes: 3)),
        reporterLat: 13.9387,
        reporterLng: 121.1701,
      ),
    ]);

    _chatMessages.addAll([
      ChatMessage(
        id: 'msg-1',
        reportId: 'RA-2026-0012',
        sender: 'Reporter',
        message: 'Water level is rising quickly near the covered court.',
        time: DateTime.now().subtract(const Duration(minutes: 11)),
        isResponder: false,
      ),
      ChatMessage(
        id: 'msg-2',
        reportId: 'RA-2026-0012',
        sender: 'Responder',
        message: 'Stay in the elevated area. Team is 5 minutes away.',
        time: DateTime.now().subtract(const Duration(minutes: 8)),
        isResponder: true,
      ),
    ]);

    _followUps.addAll([
      FollowUp(
        id: 'fu-seed-1',
        reportId: 'RA-2026-0012',
        trackingId: 'RA-2026-0012',
        hazard: 'Flood',
        reason: 'Check evacuation status of household',
        notes: 'Bring extra drinking water',
        scheduledAt: DateTime.now().add(const Duration(hours: 5)),
        priority: FollowUpPriority.high,
        isCompleted: false,
      ),
    ]);

    _evacuationRecords.addAll([
      EvacuationRecordEntry(
        trackingId: 'RA-2026-0012',
        hazardType: 'flood',
        barangay: 'Banaybanay',
        centerName: 'Lipa City Public Gym',
        status: EvacStatus.ongoing,
        totalEvacuees: 18,
        maleCount: 8,
        femaleCount: 10,
        childrenCount: 4,
        seniorsCount: 2,
        pregnantCount: 1,
        pwdCount: 1,
        fieldNotes: 'Family of the Mendoza household rescued and relocated.',
        updatedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
    ]);

    _announcements.addAll([
      Announcement(
        id: 'ann-1',
        title: 'Flood Advisory Level 2',
        message: 'Water levels in the Banaybanay area are rising. Responders in that zone should prepare evacuation routes.',
        priority: AnnouncementPriority.high,
        hazardType: 'Flood',
        publishedAt: DateTime.now().subtract(const Duration(minutes: 30)),
        publishedAgo: '30 minutes ago',
      ),
      Announcement(
        id: 'ann-2',
        title: 'Shift Briefing',
        message: 'All responders should check in with dispatch at the start of every shift for updated assignments.',
        priority: AnnouncementPriority.normal,
        hazardType: '',
        publishedAt: DateTime.now().subtract(const Duration(hours: 3)),
        publishedAgo: '3 hours ago',
      ),
    ]);

    _resourceRequests.addAll([
      ResourceRequestEntry(
        id: 'res-seed-1',
        reportId: 'RA-2026-0012',
        trackingId: 'RA-2026-0012',
        category: 'water',
        itemName: 'Bottled water',
        quantityRequested: 50,
        quantityFulfilled: 20,
        unit: 'bottles',
        priority: ResourcePriority.high,
        status: ResourceStatus.inProgress,
        locationHint: 'Banaybanay covered court',
        notes: 'For rescued families awaiting transport.',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ]);

    _events.addAll([
      CoordinationEvent(
        id: 'evt-1',
        title: 'Urgent case flag',
        message: 'Report RA-2026-0024 marked as Need Help.',
        priority: CoordinationPriority.critical,
        time: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
      CoordinationEvent(
        id: 'evt-2',
        title: 'Center update',
        message: 'Banaybanay Evacuation Center moved to Near Full.',
        priority: CoordinationPriority.urgent,
        time: DateTime.now().subtract(const Duration(minutes: 14)),
      ),
    ]);
  }

  void _startStreams() {
    _reportsController.add(List.unmodifiable(_reports));
    _eventsController.add(List.unmodifiable(_events));
    _trackingController.add(_responderPoint);
    _chatController.add(List.unmodifiable(_chatMessages));
    _followUpsController.add(List.unmodifiable(_followUps));
    _evacuationController.add(List.unmodifiable(_evacuationRecords));
    _announcementsController.add(List.unmodifiable(_announcements));
    _resourcesController.add(List.unmodifiable(_resourceRequests));

    _reportTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_reports.isEmpty) {
        return;
      }
      final i = _random.nextInt(_reports.length);
      final current = _reports[i];
      final toggledNeedHelp = _random.nextBool();
      _reports[i] = current.copyWith(
        needHelp: toggledNeedHelp,
        updated: DateTime.now(),
      );
      _reportsController.add(List.unmodifiable(_reports));
    });

    _eventTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final report = _reports[_random.nextInt(_reports.length)];
      final event = CoordinationEvent(
        id: 'evt-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Live coordination update',
        message: 'Dispatch pulse from ${report.location} for ${report.id}.',
        priority: CoordinationPriority
            .values[_random.nextInt(CoordinationPriority.values.length)],
        time: DateTime.now(),
      );
      _events.insert(0, event);
      if (_events.length > 25) {
        _events.removeLast();
      }
      _eventsController.add(List.unmodifiable(_events));
    });

    _trackingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _responderPoint = GeoPoint(
        lat: _responderPoint.lat + (_random.nextDouble() - 0.5) * 0.0007,
        lng: _responderPoint.lng + (_random.nextDouble() - 0.5) * 0.0007,
      );
      _trackingController.add(_responderPoint);
    });
  }
}
