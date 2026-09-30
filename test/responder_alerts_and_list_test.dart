import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:rapidalert/data/api_responder_service.dart';
import 'package:rapidalert/data/responder_service.dart';
import 'package:rapidalert/models/responder_models.dart';
import 'package:rapidalert/screens/assigned_reports_screen.dart';
import 'package:rapidalert/screens/map_tracking_screen.dart';

Map<String, dynamic> _apiReport(int id) => {
  'reportId': id,
  'trackingId': 'RA-$id',
  'hazardType': 'Flood',
  'barangay': 'Bulacnin',
  'status': 'assigned',
  'reporterName': 'Vera Fyre',
  'latitude': 13.935,
  'longitude': 121.15,
};

/// A local backend stand-in: [reportIds] is what /api/responder/reports
/// returns; [listFailure] makes that call fail instead.
class _Backend {
  List<int> reportIds = [];
  Object? listFailure;
  int listStatus = 200;
  bool offline = false;
  int activeTrackingCalls = 0;

  /// Report IDs returned with latitude/longitude null (sent without GPS).
  final withoutCoordinates = <int>{};
  final notificationRequests = <String>[];

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/responder/active-tracking') activeTrackingCalls++;
    if (offline) throw http.ClientException('Failed host lookup');
    if (path == '/api/responder/reports') {
      if (listFailure != null) throw listFailure!;
      final reports = [
        for (final id in reportIds)
          {
            ..._apiReport(id),
            if (withoutCoordinates.contains(id)) ...{'latitude': null, 'longitude': null},
          },
      ];
      return http.Response(jsonEncode({'reports': reports}), listStatus);
    }
    if (path == '/api/reports/notifications') {
      final id = request.url.queryParameters['report_id']!;
      notificationRequests.add(id);
      // Newest first, like the backend; the "New assignment" row is the real one.
      return http.Response(
        jsonEncode({
          'notifications': [
            {'id': 56, 'reportId': int.parse(id), 'message': 'New assignment: Report #RA-$id (Flood in Bulacnin)'},
            {'id': 55, 'reportId': int.parse(id), 'message': 'Report RA-$id status updated to in progress.'},
          ],
        }),
        200,
      );
    }
    if (path == '/api/responder/active-tracking') {
      return http.Response(jsonEncode({'assignments': []}), 200);
    }
    return http.Response('{}', 404);
  });
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  group('ApiResponderService', () {
    late _Backend backend;
    late ApiResponderService service;
    late List<AssignmentAlert> alerts;
    late StreamSubscription<AssignmentAlert> sub;

    Future<void> start() => http.runWithClient(() async {
      service = ApiResponderService(baseUrl: 'http://api.test', bearerToken: 't', responderUserId: 6);
      alerts = [];
      sub = service.assignmentAlerts.listen(alerts.add);
      await _settle();
    }, () => backend.client);

    Future<void> refresh() => http.runWithClient(() async {
      await service.refreshReports();
      await _settle();
    }, () => backend.client);

    setUp(() => backend = _Backend());
    tearDown(() async {
      await sub.cancel();
      service.dispose();
    });

    test('announces a newly assigned report once, with the backend notification', () async {
      backend.reportIds = [85];
      await start();
      expect(alerts, isEmpty, reason: 'reports already assigned at start are the baseline');

      backend.reportIds = [86, 85];
      await refresh();
      expect(alerts, hasLength(1));
      expect(alerts.single.notificationId, 56);
      expect(alerts.single.reportId, '86');
      expect(alerts.single.message, 'New assignment: Report #RA-86 (Flood in Bulacnin)');

      await refresh();
      backend.reportIds = [85];
      await refresh();
      backend.reportIds = [86, 85];
      await refresh();
      expect(alerts, hasLength(1), reason: 'the same notification is never shown twice');
    });

    test('a report without GPS keeps no position (no made-up default)', () async {
      backend.reportIds = [85, 91];
      backend.withoutCoordinates.add(91);
      await start();

      final report = service.reports.firstWhere((r) => r.id == '91');
      expect(report.reporterLat, isNull);
      expect(report.reporterLng, isNull);
      expect(service.reports.firstWhere((r) => r.id == '85').reporterLat, 13.935);
    });

    test('a failed list load is reported, never shown as an empty list, and clears on success', () async {
      backend.listFailure = http.ClientException('Failed host lookup');
      await start();
      expect(service.reportListStatus.loaded, isFalse);
      expect(service.reportListStatus.errorMessage, startsWith("You're offline"));

      backend.listFailure = null;
      backend.reportIds = [85];
      await refresh();
      expect(service.reportListStatus.loaded, isTrue);
      expect(service.reportListStatus.errorMessage, isNull);

      backend.listStatus = 500;
      await refresh();
      expect(service.reportListStatus.errorMessage, "Couldn't load your assigned reports.");
      expect(service.reports.map((r) => r.id), ['85'], reason: 'the last good list is kept');
    });
  });

  testWidgets('started offline, the service resumes its list and GPS-tracking polls once back online', (
    tester,
  ) async {
    final backend = _Backend()
      ..offline = true
      ..reportIds = [88];
    late ApiResponderService service;
    await http.runWithClient(() async {
      service = ApiResponderService(baseUrl: 'http://api.test', bearerToken: 't', responderUserId: 6);
      await tester.pump();
    }, () => backend.client);
    expect(service.reportListStatus.loaded, isFalse);
    expect(backend.activeTrackingCalls, 1, reason: 'startup tried once, offline');

    backend.offline = false;
    await tester.pump(const Duration(seconds: 21));
    expect(service.reportListStatus.loaded, isTrue, reason: 'the 8 s list poll kept running');
    expect(backend.activeTrackingCalls, greaterThan(1), reason: 'the 20 s active-tracking poll exists');

    service.dispose();
  });

  group('MapTrackingScreen', () {
    testWidgets('a report without GPS gets no reporter pin, route, distance or ETA', (tester) async {
      final noGps = IncidentReport(
        id: '91',
        hazard: 'Flood',
        location: 'Bulacnin',
        reporterName: 'Vera Fyre',
        status: ReportStatus.assigned,
        needHelp: false,
        updated: DateTime(2026, 9, 29),
        reporterLat: null,
        reporterLng: null,
      );
      // The responder does have a real fix, so only the reporter side is missing.
      final service = _MapService([noGps], point: GeoPoint(lat: 13.956, lng: 121.164, recordedAt: DateTime.now()));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTrackingScreen(service: service))));
      await tester.pump();

      expect(find.textContaining('Reporter location unavailable'), findsOneWidget);
      expect(find.bySemanticsLabel('Reporter location'), findsNothing);
      expect(find.byIcon(Icons.location_on_rounded), findsNothing);
      expect(find.bySemanticsLabel('Your position'), findsOneWidget);
      expect(find.textContaining('km'), findsNothing);
      expect(find.textContaining('ETA'), findsNothing);
      await tester.pumpWidget(const SizedBox()); // stop the age timer
    });

    testWidgets('a last known responder position is never shown as live; a fresh shared fix restores Live', (
      tester,
    ) async {
      final tracking = StreamController<GeoPoint>.broadcast();
      final service = _MapService(
        [_report('90')],
        // Tracking stopped; only the last real fix from 5 minutes ago remains.
        // Near the reporter so the marker is inside the unfitted map view.
        point: GeoPoint(lat: 13.936, lng: 121.151, recordedAt: DateTime.now().subtract(const Duration(minutes: 5))),
        sharing: false,
        tracking: tracking.stream,
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTrackingScreen(service: service))));
      // flutter_map learns its size after the first frame; until then it only
      // builds markers exactly at the camera centre.
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Last known position — 5m ago'), findsOneWidget);
      // Two markers share one merged semantics node, so match within it.
      expect(find.bySemanticsLabel(RegExp('Your last known position')), findsOneWidget);
      expect(find.textContaining('Live —'), findsNothing);
      // No ETA or distance value (the message itself says they aren't shown).
      expect(find.textContaining(RegExp(r'ETA about|road ETA unavailable')), findsNothing);
      expect(find.textContaining("distance and ETA aren't shown"), findsOneWidget);
      expect(find.textContaining('km'), findsNothing);

      // Tracking resumes: sharing is on again and a fresh fix arrives.
      service.sharing = true;
      tracking.add(GeoPoint(lat: 13.936, lng: 121.151, recordedAt: DateTime.now()));
      await tester.pump(); // delivers the event
      await tester.pump(); // rebuilds with it
      expect(find.textContaining('Live — sharing your location'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Your position')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Your last known position')), findsNothing);
      expect(find.textContaining('Last known position'), findsNothing);
      expect(find.textContaining('km'), findsOneWidget);

      // Sharing stops (e.g. the report is resolved): stale without any new fix.
      service.sharing = false;
      await tester.pump(const Duration(seconds: 11));
      expect(find.textContaining('Last known position'), findsOneWidget);
      expect(find.textContaining('Live —'), findsNothing);
      expect(find.textContaining('km'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tracking.close();
    });

    testWidgets('opens on the requested report, also when already showing another', (tester) async {
      final service = _MapService([_report('90'), _report('85')]);
      Widget map(String? id) => MaterialApp(
        home: Scaffold(body: MapTrackingScreen(service: service, initialReportId: id)),
      );

      await tester.pumpWidget(map('85'));
      await tester.pump();
      expect(find.text('85 - Bulacnin'), findsOneWidget, reason: 'not the first report, the requested one');

      await tester.pumpWidget(map('90'));
      await tester.pump();
      expect(find.text('90 - Bulacnin'), findsOneWidget);

      await tester.pumpWidget(map('77')); // no longer assigned
      await tester.pump();
      expect(find.text('90 - Bulacnin'), findsOneWidget, reason: 'falls back without a dropdown assertion');
    });
  });

  group('AssignedReportsScreen', () {
    Future<_ListService> pumpScreen(WidgetTester tester, ReportListStatus status, List<IncidentReport> reports) async {
      final service = _ListService(status, reports);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AssignedReportsScreen(service: service))));
      await tester.pump();
      return service;
    }

    testWidgets('never loaded + failed: an error with Retry, not "no reports"', (tester) async {
      final service = await pumpScreen(
        tester,
        const ReportListStatus(errorMessage: "You're offline. Assigned reports can't be refreshed until you reconnect."),
        const [],
      );

      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(find.textContaining('No reports matched'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(service.refreshCalls, 1);
    });

    testWidgets('loaded before, now failing: the old list is marked with its time and Retry', (tester) async {
      await pumpScreen(
        tester,
        ReportListStatus(lastLoadedAt: DateTime(2026, 9, 29, 15, 24), errorMessage: "Couldn't load your assigned reports."),
        [_report('85')],
      );

      expect(find.text("Couldn't load your assigned reports. Showing the list from 3:24 PM."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
    });
  });
}

IncidentReport _report(String id) => IncidentReport(
  id: id,
  hazard: 'Flood',
  location: 'Bulacnin',
  reporterName: 'Vera Fyre',
  status: ReportStatus.assigned,
  needHelp: false,
  updated: DateTime(2026, 9, 29),
  reporterLat: 13.935,
  reporterLng: 121.15,
);

class _MapService extends Fake implements ResponderService {
  _MapService(this.reports, {this.point, this.sharing = true, Stream<GeoPoint>? tracking})
    : _tracking = tracking ?? const Stream.empty();

  @override
  final List<IncidentReport> reports;

  final GeoPoint? point;
  bool sharing;
  final Stream<GeoPoint> _tracking;

  @override
  Stream<List<IncidentReport>> get reportsStream => const Stream.empty();

  @override
  Stream<GeoPoint> get responderTrackingStream => _tracking;

  @override
  GeoPoint? get currentResponderPoint => point;

  @override
  bool get isSharingLocation => sharing;
}

class _ListService extends Fake implements ResponderService {
  _ListService(this.reportListStatus, this.reports);

  @override
  final ReportListStatus reportListStatus;

  @override
  final List<IncidentReport> reports;

  int refreshCalls = 0;

  @override
  Stream<ReportListStatus> get reportListStatusStream => const Stream.empty();

  @override
  Stream<List<IncidentReport>> get reportsStream => const Stream.empty();

  @override
  Future<void> refreshReports() async => refreshCalls++;
}
