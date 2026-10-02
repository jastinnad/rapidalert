import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:rapidalert/data/api_reporter_service.dart';
import 'package:rapidalert/data/offline_cache.dart';
import 'package:rapidalert/data/report_submission_ids.dart';
import 'package:rapidalert/data/reporter_service.dart';
import 'package:rapidalert/models/reporter_models.dart';
import 'package:rapidalert/screens/report_tracking_screen.dart';

Map<String, dynamic> _reportJson({String trackingId = 'RA-ONE', String status = 'en_route'}) => {
  'id': 7,
  'trackingId': trackingId,
  'hazard': 'Flood',
  'city': 'Lipa City',
  'barangay': 'Sabang',
  'status': status,
  'assignedResponderName': 'Rex Ander',
  'createdAt': DateTime(2026, 9, 28, 9).millisecondsSinceEpoch,
  'updatedAt': DateTime(2026, 9, 28, 9, 5).millisecondsSinceEpoch,
  'adminComment': '',
  'responderLat': 13.94,
  'responderLng': 121.16,
  'responderLocationUpdatedAt': DateTime.now().millisecondsSinceEpoch,
  'etaMinutes': 6,
};

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('ApiReporterService offline cache', () {
    ApiReporterService service({int? userId}) =>
        ApiReporterService(baseUrl: 'http://api.test', bearerToken: userId == null ? '' : 't', myUserId: userId);

    test('a found report is saved and returned only for a matching tracking ID', () async {
      final client = MockClient((_) async => http.Response(jsonEncode({'found': true, 'report': _reportJson()}), 200));
      final api = service(userId: 5);
      await http.runWithClient(() => api.trackReport(), () => client);

      expect((await api.cachedTrackedReport())?.value.trackingId, 'RA-ONE');
      expect((await api.cachedTrackedReport(trackingId: 'ra-one'))?.value.trackingId, 'RA-ONE');
      expect(await api.cachedTrackedReport(trackingId: 'RA-OTHER'), isNull);
    });

    test("one account's saved report is not shown to another account or a guest", () async {
      final client = MockClient((_) async => http.Response(jsonEncode({'found': true, 'report': _reportJson()}), 200));
      await http.runWithClient(() => service(userId: 5).trackReport(), () => client);

      expect(await service(userId: 6).cachedTrackedReport(), isNull);
      expect(await service().cachedTrackedReport(), isNull);
    });

    test('clearAll (sign-out) removes saved copies', () async {
      final client = MockClient((_) async => http.Response(jsonEncode({'found': true, 'report': _reportJson()}), 200));
      final api = service(userId: 5);
      await http.runWithClient(() => api.trackReport(), () => client);
      await OfflineCache().clearAll();

      expect(await api.cachedTrackedReport(), isNull);
    });

    test('an evacuation list ranked from a fallback point is saved without distances or ETAs', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'centres': [
              {
                'area_id': 1,
                'name': 'Tibig Covered Court',
                // The ranked API always sends the center's position.
                'lat': 13.95,
                'lon': 121.15,
                'capacity': 300,
                'available_slots': 300,
                'distance_km': 1.4,
                'eta_minutes': 3,
              },
            ],
          }),
          200,
        ),
      );
      final api = service(userId: 5);

      await http.runWithClient(
        () => api.loadNearestEvacuationCenters(lat: 13.9411, lon: 121.1634, fromUserLocation: false),
        () => client,
      );
      final fallbackCopy = (await api.cachedEvacuationCenters())!.value.centres.single;
      expect(fallbackCopy.distanceKm, isNull);
      expect(fallbackCopy.etaMinutes, isNull);
      expect(fallbackCopy.name, 'Tibig Covered Court', reason: 'the center itself is kept');
      expect(fallbackCopy.availableSlots, 300);

      await http.runWithClient(() => api.loadNearestEvacuationCenters(lat: 13.935, lon: 121.15), () => client);
      final realCopy = (await api.cachedEvacuationCenters())!.value.centres.single;
      expect(realCopy.distanceKm, 1.4, reason: 'a list ranked from a real fix keeps its distances');
      expect(realCopy.etaMinutes, 3);
    });

    test('loadReportNotifications parses the backend list for one report', () async {
      late Uri asked;
      final client = MockClient((request) async {
        asked = request.url;
        return http.Response(
          jsonEncode({
            'notifications': [
              {
                'id': 3,
                'reportId': 7,
                'message': 'Report RA-ONE is now resolved.',
                'status': 'resolved',
                'timestamp': '1 minute ago',
                'createdAt': '2026-09-28T09:10:00+08:00',
              },
            ],
          }),
          200,
        );
      });
      final items = await http.runWithClient(() => service(userId: 5).loadReportNotifications(7), () => client);

      expect(asked.path, '/api/reports/notifications');
      expect(asked.queryParameters, {'report_id': '7'});
      expect(items.single.message, 'Report RA-ONE is now resolved.');
      expect(items.single.status, 'resolved');
      expect(items.single.createdAt, isNotNull);
    });

    test('a dropped connection is reported as a network error', () async {
      final client = MockClient((_) async => throw http.ClientException('Connection refused'));
      final error = await http.runWithClient(
        () => service(userId: 5).trackReport().then<Object?>((_) => null, onError: (Object e) => e),
        () => client,
      );
      expect(isNetworkError(error!), isTrue);
    });
  });

  group('tracking screen offline', () {
    testWidgets('shows the saved copy with an OFFLINE badge and never "Live"', (tester) async {
      final service = _OfflineReporterService(
        CachedCopy(TrackedReport.fromApi(_reportJson()), DateTime.now().subtract(const Duration(minutes: 3))),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReportTrackingScreen(
            service: service,
            submissionIds: ReportSubmissionIds(storage: MemoryReportIdStorage(), deviceId: () async => 'd'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('RA-ONE'), findsOneWidget);
      expect(find.textContaining('Live'), findsNothing);
      expect(find.textContaining('Last known position'), findsOneWidget);
      expect(find.textContaining('ETA ~'), findsNothing);
      expect(find.textContaining('ETA unavailable'), findsOneWidget);
    });

    testWidgets('without a saved copy shows a plain message and Retry', (tester) async {
      final service = _OfflineReporterService(null);
      await tester.pumpWidget(
        MaterialApp(
          home: ReportTrackingScreen(
            service: service,
            submissionIds: ReportSubmissionIds(storage: MemoryReportIdStorage(), deviceId: () async => 'd'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });
  });
}

/// A signed-in reporter whose phone has no connection.
class _OfflineReporterService extends Fake implements ReporterService {
  _OfflineReporterService(this.saved);

  final CachedCopy<TrackedReport>? saved;

  @override
  int? get currentUserId => 5;

  @override
  Future<TrackedReport?> trackReport({String? trackingId, String? clientReportId}) async =>
      throw http.ClientException('Failed host lookup');

  @override
  Future<CachedCopy<TrackedReport>?> cachedTrackedReport({String? trackingId}) async => saved;
}
