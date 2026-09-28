import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rapidalert/data/report_submission_ids.dart';
import 'package:rapidalert/data/reporter_service.dart';
import 'package:rapidalert/models/reporter_models.dart';
import 'package:rapidalert/screens/report_tracking_screen.dart';

/// Records what the tracking screen asks the API for.
class _RecordingReporterService extends Fake implements ReporterService {
  _RecordingReporterService({this.currentUserId});

  @override
  final int? currentUserId;

  final lookups = <({String? trackingId, String? clientReportId})>[];

  @override
  Future<TrackedReport?> trackReport({String? trackingId, String? clientReportId}) async {
    lookups.add((trackingId: trackingId, clientReportId: clientReportId));
    return null;
  }
}

void main() {
  const deviceId = '11111111-1111-4111-8111-111111111111';

  late ReportSubmissionIds ids;
  late String firstReportId;
  late String secondReportId;

  setUp(() async {
    ids = ReportSubmissionIds(storage: MemoryReportIdStorage(), deviceId: () async => deviceId);
    Future<bool> none(String _) async => false;
    firstReportId =
        (await ids.submit({'r': 1}, (id) async => 'RA-FIRST1', isStored: none, trackingId: (t) => t)).clientReportId;
    secondReportId =
        (await ids.submit({'r': 2}, (id) async => 'RA-SECOND', isStored: none, trackingId: (t) => t)).clientReportId;
  });

  Future<_RecordingReporterService> pumpTracking(WidgetTester tester, {int? userId}) async {
    final service = _RecordingReporterService(currentUserId: userId);
    await tester.pumpWidget(MaterialApp(home: ReportTrackingScreen(service: service, submissionIds: ids)));
    await tester.pumpAndSettle();
    return service;
  }

  Future<void> search(WidgetTester tester, String trackingId) async {
    await tester.enterText(find.byType(TextField), trackingId);
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets("a guest's blank search asks for the latest report by its own client_report_id", (tester) async {
    final service = await pumpTracking(tester);

    expect(service.lookups.single, (trackingId: null, clientReportId: secondReportId));
  });

  testWidgets("a guest searching one of their own tracking IDs sends that report's client_report_id", (tester) async {
    final service = await pumpTracking(tester);
    await search(tester, 'RA-FIRST1');

    expect(service.lookups.last, (trackingId: 'RA-FIRST1', clientReportId: firstReportId));
    expect(firstReportId, isNot(secondReportId));
  });

  testWidgets("a guest searching someone else's tracking ID sends only the tracking ID", (tester) async {
    final service = await pumpTracking(tester);
    await search(tester, 'RA-OTHER1');

    expect(service.lookups.last, (trackingId: 'RA-OTHER1', clientReportId: null));
  });

  testWidgets('the device ID is never used for a lookup once the install has its own reports', (tester) async {
    final service = await pumpTracking(tester);
    await search(tester, 'RA-FIRST1');

    expect(service.lookups.map((l) => l.clientReportId), isNot(contains(deviceId)));
  });

  testWidgets('a signed-in reporter is looked up by account, with no client_report_id', (tester) async {
    final service = await pumpTracking(tester, userId: 4);
    await search(tester, 'RA-FIRST1');

    expect(service.lookups, [
      (trackingId: null, clientReportId: null),
      (trackingId: 'RA-FIRST1', clientReportId: null),
    ]);
  });
}
