import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:rapidalert/data/api_reporter_service.dart';
import 'package:rapidalert/data/backend_features.dart';
import 'package:rapidalert/data/report_submission_ids.dart';
import 'package:rapidalert/data/reporter_service.dart';
import 'package:rapidalert/models/reporter_models.dart';
import 'package:rapidalert/screens/report_history_screen.dart';
import 'package:rapidalert/screens/report_tracking_screen.dart';

/// C-b (incident location and road route) and C-c (status history) run only
/// while BackendFeatures.reporterTrackingDetails is on. Run this file both
/// ways: `flutter test` (production default, off) and
/// `flutter test --dart-define=RAPID_ALERT_REPORTER_TRACKING_DETAILS=true`.
const _on = BackendFeatures.reporterTrackingDetails;

Map<String, dynamic> _liveReport() => {
  'id': 90,
  'trackingId': 'RA-LIVE',
  'hazard': 'Flood',
  'city': 'Lipa City',
  'barangay': 'Bulacnin',
  'status': 'en_route',
  'createdAt': 0,
  'updatedAt': 0,
  'adminComment': '',
  'responderLat': 13.936,
  'responderLng': 121.151,
  'responderLocationUpdatedAt': DateTime.now().millisecondsSinceEpoch,
  'etaMinutes': 6,
  'latitude': 13.935,
  'longitude': 121.15,
};

Future<void> _pumpTracking(WidgetTester tester, ReporterService service) async {
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
  await tester.pump();
}

void main() {
  group('C-b reporter map', () {
    testWidgets(
      _on ? 'live: the incident pin, ETA and Status history are shown' : 'flag off: no incident pin or history',
      (tester) async {
        await _pumpTracking(tester, _Tracking(TrackedReport.fromApi(_liveReport())));

        expect(find.bySemanticsLabel(RegExp('your reported location')), _on ? findsOneWidget : findsNothing);
        expect(find.text('Status history'), _on ? findsOneWidget : findsNothing);
        // Unchanged either way: the live responder position and its ETA.
        expect(find.textContaining('Live — updated'), findsOneWidget);
        expect(find.textContaining('ETA'), findsOneWidget);
        expect(find.text('View updates'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a guest sees Status history only with the flag on', (tester) async {
      await _pumpTracking(tester, _Tracking(TrackedReport.fromApi(_liveReport()), userId: null));

      expect(find.text('Status history'), _on ? findsOneWidget : findsNothing);
      expect(find.text('View updates'), findsNothing);
      expect(find.textContaining('Sign in to see the list of updates'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('C-c status history API', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test(
      _on ? 'calls the history endpoint and parses it' : 'flag off: no request is made',
      () async {
        final requests = <Uri>[];
        final client = MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'found': true,
              'trackingId': 'RA-HIST',
              'submittedAt': 0,
              'transitions': [
                {'fromStatus': 'reported', 'toStatus': 'assigned', 'at': 1, 'actorRole': 'dispatcher', 'actorName': null},
              ],
            }),
            200,
          );
        });
        final api = ApiReporterService(baseUrl: 'http://api.test', bearerToken: '');

        final history = await http.runWithClient(
          () => api.loadStatusHistory(trackingId: 'RA-HIST', clientReportId: 'abc'),
          () => client,
        );

        if (_on) {
          expect(requests.single.path, '/api/reporter/reports/history');
          expect(requests.single.queryParameters, {'tracking_id': 'RA-HIST', 'client_report_id': 'abc'});
          expect(history?.transitions.single.toStatus, 'assigned');
        } else {
          expect(requests, isEmpty);
          expect(history, isNull);
        }
      },
    );
  });

  group('C-c status history screen', () {
    testWidgets('lists only the recorded steps, with actor and time', (tester) async {
      final service = _History(
        StatusHistory.fromApi({
          'trackingId': 'RA-HIST',
          'submittedAt': DateTime(2026, 9, 30, 10).millisecondsSinceEpoch,
          'transitions': [
            {
              'fromStatus': 'reported',
              'toStatus': 'assigned',
              'at': DateTime(2026, 9, 30, 10, 5).millisecondsSinceEpoch,
              'actorRole': 'dispatcher',
              'actorName': null,
            },
            {
              'fromStatus': 'assigned',
              'toStatus': 'en_route',
              'at': DateTime(2026, 9, 30, 10, 7).millisecondsSinceEpoch,
              'actorRole': 'responder',
              'actorName': 'Rex Ander',
            },
          ],
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReportHistoryScreen(service: service, trackingId: 'RA-HIST'),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.bySemanticsLabel(RegExp('^Report submitted')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Responder assigned, by a CDRRMO dispatcher')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Responder on the way, by Rex Ander \(responder\)')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Responder arrived')), findsNothing, reason: 'nothing is inferred');
    });

    testWidgets('not found for this caller: an explanation, no made-up steps', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReportHistoryScreen(service: _History(null), trackingId: 'RA-X'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining("Status history isn't available"), findsOneWidget);
    });

    testWidgets('a failed load shows Retry', (tester) async {
      final service = _History(null, fail: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ReportHistoryScreen(service: service, trackingId: 'RA-X'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

class _Tracking extends Fake implements ReporterService {
  _Tracking(this.report, {this.userId = 5});
  final TrackedReport report;
  final int? userId;

  @override
  int? get currentUserId => userId;
  @override
  Future<TrackedReport?> trackReport({String? trackingId, String? clientReportId}) async => report;
}

class _History extends Fake implements ReporterService {
  _History(this.history, {this.fail = false});
  final StatusHistory? history;
  final bool fail;

  @override
  Future<StatusHistory?> loadStatusHistory({required String trackingId, String? clientReportId}) async {
    if (fail) throw http.ClientException('Failed host lookup');
    return history;
  }
}
