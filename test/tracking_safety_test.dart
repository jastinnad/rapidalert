import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rapidalert/data/report_submission_ids.dart';
import 'package:rapidalert/data/reporter_service.dart';
import 'package:rapidalert/data/responder_service.dart';
import 'package:rapidalert/models/reporter_models.dart';
import 'package:rapidalert/models/responder_models.dart';
import 'package:rapidalert/screens/map_tracking_screen.dart';
import 'package:rapidalert/screens/report_tracking_screen.dart';

Map<String, dynamic> _report(String status) => {
  'id': 85,
  'trackingId': 'RA-SAFE',
  'hazard': 'Flood',
  'city': 'Lipa City',
  'barangay': 'Bulacnin',
  'status': status,
  'assignedResponderName': 'Rex Ander',
  'createdAt': 0,
  'updatedAt': 0,
  'adminComment': '',
  // The backend sends a position only while en_route/on_scene.
  if (status == 'en_route') ...{
    'responderLat': 13.95,
    'responderLng': 121.16,
    'responderLocationUpdatedAt': DateTime.now().millisecondsSinceEpoch,
    'etaMinutes': 6,
  },
};

/// Answers each tracking request with the next status in [statuses].
class _SequenceReporterService extends Fake implements ReporterService {
  _SequenceReporterService(this.statuses);

  final List<String> statuses;
  int calls = 0;

  @override
  int? get currentUserId => 5;

  @override
  Future<TrackedReport?> trackReport({String? trackingId, String? clientReportId}) async {
    final status = statuses[calls < statuses.length ? calls : statuses.length - 1];
    calls++;
    return TrackedReport.fromApi(_report(status));
  }
}

/// Online, en route, but the responder's last ping was 2 minutes ago; the
/// backend still sends its ETA from that old position.
class _StaleReporterService extends Fake implements ReporterService {
  @override
  int? get currentUserId => 5;

  @override
  Future<TrackedReport?> trackReport({String? trackingId, String? clientReportId}) async =>
      TrackedReport.fromApi({
        ..._report('en_route'),
        'responderLocationUpdatedAt': DateTime.now().subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
      });
}

/// A responder phone that has no GPS fix yet.
class _NoFixResponderService extends Fake implements ResponderService {
  final _tracking = StreamController<GeoPoint>.broadcast();

  static final _assigned = IncidentReport(
    id: '85',
    hazard: 'Flood',
    location: 'Bulacnin',
    reporterName: 'Vera Fyre',
    status: ReportStatus.assigned,
    needHelp: false,
    updated: DateTime(2026, 9, 28),
    reporterLat: 13.935,
    reporterLng: 121.15,
  );

  @override
  List<IncidentReport> get reports => [_assigned];

  @override
  Stream<List<IncidentReport>> get reportsStream => Stream.value([_assigned]);

  @override
  Stream<GeoPoint> get responderTrackingStream => _tracking.stream;

  @override
  GeoPoint? get currentResponderPoint => null;

  @override
  bool get isSharingLocation => false;
}

void main() {
  testWidgets('reporter stops polling and shows no live position once the report is resolved', (tester) async {
    final service = _SequenceReporterService(['en_route', 'resolved']);
    await tester.pumpWidget(
      MaterialApp(
        home: ReportTrackingScreen(
          service: service,
          submissionIds: ReportSubmissionIds(storage: MemoryReportIdStorage(), deviceId: () async => 'd'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Live'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7)); // one live poll → resolved
    await tester.pump();
    expect(find.text('RESOLVED'), findsOneWidget);
    expect(find.textContaining('Live'), findsNothing);
    expect(find.textContaining('Last known position'), findsNothing);
    expect(find.textContaining('ETA'), findsNothing);

    final callsAtResolve = service.calls;
    await tester.pump(const Duration(seconds: 30));
    expect(service.calls, callsAtResolve, reason: 'no polling after resolved');
  });

  testWidgets('a new report turns assigned, en route and live without a manual refresh', (tester) async {
    final service = _SequenceReporterService(['reported', 'assigned', 'en_route', 'resolved']);
    await tester.pumpWidget(
      MaterialApp(
        home: ReportTrackingScreen(
          service: service,
          submissionIds: ReportSubmissionIds(storage: MemoryReportIdStorage(), deviceId: () async => 'd'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('REPORTED'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pump();
    expect(find.text('ASSIGNED'), findsOneWidget);
    expect(find.textContaining('Live'), findsNothing, reason: 'no position while only assigned');

    await tester.pump(const Duration(seconds: 7));
    await tester.pump();
    expect(find.text('EN ROUTE'), findsOneWidget);
    expect(find.textContaining('Live'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pump();
    expect(find.text('RESOLVED'), findsOneWidget);
    final callsAtResolve = service.calls;
    await tester.pump(const Duration(seconds: 30));
    expect(service.calls, callsAtResolve);
  });

  testWidgets('a stale position shows "Last known position" and no current ETA', (tester) async {
    final service = _StaleReporterService();
    await tester.pumpWidget(
      MaterialApp(
        home: ReportTrackingScreen(
          service: service,
          submissionIds: ReportSubmissionIds(storage: MemoryReportIdStorage(), deviceId: () async => 'd'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Last known position — 2m ago'), findsOneWidget);
    expect(find.textContaining('Live'), findsNothing);
    expect(find.textContaining('ETA ~6'), findsNothing, reason: 'an ETA from an old position is not current');
    expect(find.text("ETA unavailable until the responder's position updates."), findsOneWidget);
    expect(find.text('OFFLINE'), findsNothing, reason: 'the reporter is online; only the position is old');

    await tester.pumpWidget(const SizedBox()); // stop the live poll
  });

  testWidgets('responder map draws no responder position before a real GPS fix', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTrackingScreen(service: _NoFixResponderService()))));
    await tester.pump();

    // Assigned, not yet en route: GPS isn't in use yet, so nothing is "waited for".
    expect(find.textContaining('shown here once you tap Start — En Route'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_rounded), findsNothing);
    expect(find.textContaining('km'), findsNothing);
  });
}
