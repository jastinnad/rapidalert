import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:rapidalert/data/api_reporter_service.dart';
import 'package:rapidalert/data/report_submission_ids.dart';
import 'package:rapidalert/data/reporter_service.dart';
import 'package:rapidalert/models/reporter_models.dart';
import 'package:rapidalert/models/responder_models.dart';
import 'package:rapidalert/screens/report_chat_screen.dart';
import 'package:rapidalert/screens/report_tracking_screen.dart';
import 'package:rapidalert/screens/reporter_home_shell.dart';

/// The /api/reporter/reports/track report shape (see ReporterReportController
/// transformTrackingReport).
Map<String, dynamic> _report({
  String status = 'en_route',
  String? responderName = 'Rex Ander',
  int? responderUserId = 7,
  bool withPosition = true,
}) => {
  'id': 90,
  'trackingId': 'RA-20261002-TRK001',
  'hazard': 'Flood',
  'city': 'Lipa City',
  'barangay': 'Marauoy',
  'status': status,
  'assignedResponderName': responderName,
  'assignedResponderUserId': responderUserId,
  'createdAt': 0,
  'updatedAt': 0,
  'adminComment': '',
  'responderLat': withPosition ? 13.936 : null,
  'responderLng': withPosition ? 121.151 : null,
  'responderLocationUpdatedAt': withPosition ? DateTime.now().millisecondsSinceEpoch : null,
  'etaMinutes': withPosition ? 6 : null,
  'latitude': null,
  'longitude': null,
};

class _Service extends Fake implements ReporterService {
  _Service(Map<String, dynamic> json, {this.userId = 5, this.presence, this.presenceFails = false})
    : report = TrackedReport.fromApi(json);

  final TrackedReport report;
  final int? userId;
  final ResponderPresence? presence;
  final bool presenceFails;
  int presenceCalls = 0;

  @override
  int? get currentUserId => userId;

  @override
  Future<TrackedReport?> trackReport({String? trackingId, String? clientReportId}) async => report;

  @override
  Future<ResponderPresence?> loadResponderPresence(int reportId) async {
    presenceCalls++;
    if (presenceFails) throw http.ClientException('Failed host lookup');
    return presence;
  }

  @override
  Future<List<ChatMessage>> loadReportMessages(int reportId) async => const [];
}

Future<void> _pump(WidgetTester tester, ReporterService service, {VoidCallback? onCreateAccount}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: ReportTrackingScreen(
        service: service,
        onCreateAccount: onCreateAccount,
        submissionIds: ReportSubmissionIds(storage: MemoryReportIdStorage(), deviceId: () async => 'd'),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  // Guests' blank search needs a report this phone sent; search by ID instead.
  if (find.text('No report found.').evaluate().isNotEmpty) {
    await tester.enterText(find.byType(TextField), 'RA-20261002-TRK001');
    await tester.tap(find.byTooltip('Search report'));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }
}

Future<void> _done(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Guest tracking', () {
    testWidgets('shows the Tracking ID and a clear Create account action', (tester) async {
      var opened = 0;
      await _pump(tester, _Service(_report(), userId: null), onCreateAccount: () => opened++);

      expect(find.text('RA-20261002-TRK001'), findsOneWidget);
      expect(find.byKey(const Key('tracking-create-account')), findsOneWidget);
      expect(find.textContaining("aren't added to a new account"), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      expect(opened, 1);
      await _done(tester);
    });

    testWidgets('never fabricates presence and explains that messaging needs an account', (tester) async {
      final service = _Service(_report(), userId: null, presence: const ResponderPresence(online: true));
      await _pump(tester, service);

      expect(service.presenceCalls, 0, reason: 'guests are not allowed to read presence');
      expect(find.byKey(const Key('tracking-presence')), findsNothing);
      expect(find.text('Online'), findsNothing);
      expect(find.byKey(const Key('tracking-chat-needs-account')), findsOneWidget);
      expect(find.byKey(const Key('tracking-message-responder')), findsNothing);
      await _done(tester);
    });

    testWidgets('the guest shell routes Create account to its registration callback', (tester) async {
      // AuthGate maps this callback to its existing RegisterScreen; with the
      // API off in tests AuthGate skips login, so the step is checked here.
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final offline = MockClient((_) async => throw http.ClientException('offline'));
      var opened = 0;

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(home: ReporterHomeShell(isGuest: true, onCreateAccount: () => opened++)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Track'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
        await tester.pumpAndSettle();
      }, () => offline);

      expect(opened, 1);
      await _done(tester);
    });
  });

  group('Registered tracking', () {
    testWidgets('shows the responder, their step, real presence and the chat entry', (tester) async {
      final service = _Service(_report(), presence: const ResponderPresence(online: true));
      await _pump(tester, service);

      expect(find.byKey(const Key('tracking-responder-panel')), findsOneWidget);
      expect(find.text('Rex Ander'), findsOneWidget);
      expect(find.text('On the way'), findsOneWidget);
      expect(service.presenceCalls, greaterThan(0));
      expect(find.text('Online'), findsOneWidget);
      expect(find.byKey(const Key('tracking-message-responder')), findsOneWidget);
      expect(find.byKey(const Key('tracking-create-account')), findsNothing);
      expect(find.text('View updates'), findsOneWidget, reason: 'existing registered feature kept');
      await _done(tester);
    });

    testWidgets('presence follows the backend: offline is said plainly, a failed lookup shows nothing', (tester) async {
      await _pump(tester, _Service(_report(), presence: const ResponderPresence(online: false)));
      expect(find.text('Not online right now'), findsOneWidget);
      expect(find.text('Online'), findsNothing);
      await _done(tester);

      await _pump(tester, _Service(_report(), presenceFails: true));
      expect(find.byKey(const Key('tracking-presence')), findsNothing);
      expect(find.text('Not online right now'), findsNothing);
      await _done(tester);
    });

    testWidgets('the responder position appears only with coordinates from the backend', (tester) async {
      await _pump(tester, _Service(_report()));
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.textContaining('Live — updated'), findsOneWidget);
      expect(find.byKey(const Key('tracking-location-unavailable')), findsNothing);
      await _done(tester);
    });

    testWidgets('en route without coordinates shows an honest unavailable state and no map', (tester) async {
      await _pump(tester, _Service(_report(withPosition: false)));
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.byKey(const Key('tracking-location-unavailable')), findsOneWidget);
      expect(find.textContaining('Responder location unavailable'), findsOneWidget);
      await _done(tester);
    });

    testWidgets('assigned, resolved and unassigned reports explain the location state', (tester) async {
      await _pump(tester, _Service(_report(status: 'assigned', withPosition: false)));
      expect(find.byKey(const Key('tracking-location-not-yet')), findsOneWidget);
      expect(find.text('Assigned — preparing to respond'), findsOneWidget);
      await _done(tester);

      await _pump(tester, _Service(_report(status: 'resolved', withPosition: false)));
      expect(find.byKey(const Key('tracking-location-ended')), findsOneWidget);
      await _done(tester);

      await _pump(
        tester,
        _Service(_report(status: 'reported', responderName: null, responderUserId: null, withPosition: false)),
      );
      expect(find.byKey(const Key('tracking-no-responder')), findsOneWidget);
      expect(find.byKey(const Key('tracking-message-responder')), findsNothing);
      await _done(tester);
    });

    testWidgets('the Tracking ID, not the internal report number, identifies the report and its chat', (tester) async {
      await _pump(tester, _Service(_report()));

      expect(find.text('RA-20261002-TRK001'), findsOneWidget);
      expect(find.text('90'), findsNothing);
      expect(find.textContaining('#90'), findsNothing);

      await tester.tap(find.byKey(const Key('tracking-message-responder')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportChatScreen), findsOneWidget);
      expect(find.text('Report RA-20261002-TRK001'), findsOneWidget);
      expect(find.text('90'), findsNothing);
      await _done(tester);
    });
  });

  group('Presence API', () {
    test('reads the existing responder-presence endpoint for the report', () async {
      Uri? asked;
      String? auth;
      final client = MockClient((request) async {
        asked = request.url;
        auth = request.headers['Authorization'];
        return http.Response(
          jsonEncode({
            'assignedResponder': {'userId': 7, 'name': 'Rex Ander', 'online': true, 'lastSeen': null},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final presence = await http.runWithClient(
        () => ApiReporterService(baseUrl: 'http://api.test', bearerToken: 'tok', myUserId: 5).loadResponderPresence(90),
        () => client,
      );

      expect(asked!.path, '/api/reports/responder-presence');
      expect(asked!.queryParameters, {'report_id': '90'});
      expect(auth, 'Bearer tok');
      expect(presence!.online, isTrue);
    });

    test('no assigned responder parses as no presence, not as offline', () {
      expect(ResponderPresence.fromApi({'assignedResponder': null}), isNull);
      expect(ResponderPresence.fromApi({'assignedResponder': {'online': false}})!.online, isFalse);
    });
  });
}
