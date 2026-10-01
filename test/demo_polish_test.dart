import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:rapidalert/data/auth_service.dart';
import 'package:rapidalert/data/responder_service.dart';
import 'package:rapidalert/models/responder_models.dart';
import 'package:rapidalert/screens/chat_screen.dart';
import 'package:rapidalert/screens/dashboard_screen.dart';
import 'package:rapidalert/screens/map_tracking_screen.dart';

IncidentReport _incident(
  String id, {
  int? reporterUserId,
  ReportStatus status = ReportStatus.assigned,
  double? lat = 13.935,
}) => IncidentReport(
  id: id,
  hazard: 'Flood',
  location: 'Bulacnin',
  reporterName: 'Vera Fyre',
  status: status,
  needHelp: false,
  updated: DateTime(2026, 9, 30),
  reporterLat: lat,
  reporterLng: lat == null ? null : 121.15,
  reporterUserId: reporterUserId,
);

class _Responder extends Fake implements ResponderService {
  _Responder(this.reports, {this.loadFails = false, this.status = const ReportListStatus()});

  @override
  final List<IncidentReport> reports;
  final bool loadFails;
  final ReportListStatus status;
  int loads = 0;

  @override
  Stream<List<ChatMessage>> get chatStream => const Stream.empty();
  @override
  List<ChatMessage> messagesFor(String reportId) => const [];
  @override
  Future<void> loadMessages(String reportId) async {
    loads++;
    if (loadFails) throw http.ClientException('Failed host lookup');
  }

  @override
  Stream<List<IncidentReport>> get reportsStream => const Stream.empty();
  @override
  Stream<ReportListStatus> get reportListStatusStream => const Stream.empty();
  @override
  ReportListStatus get reportListStatus => status;
  @override
  Future<void> refreshReports() async {}
  @override
  Stream<List<EvacuationRecordEntry>> get evacuationRecordsStream => const Stream.empty();
  @override
  List<EvacuationRecordEntry> get evacuationRecords => const [];
  @override
  Stream<GeoPoint> get responderTrackingStream => const Stream.empty();
  @override
  GeoPoint? get currentResponderPoint => null;
  @override
  bool get isSharingLocation => false;
}

void main() {
  group('B-a responder chat', () {
    testWidgets('a failed load shows an error with Retry, not "No chat messages yet"', (tester) async {
      final service = _Responder([_incident('90', reporterUserId: 5)], loadFails: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatScreen(service: service)),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(find.text('No chat messages yet.'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(service.loads, 2);
      expect(find.byTooltip('Send message'), findsOneWidget);
    });

    testWidgets("a guest's report explains why chat isn't available and disables Send", (tester) async {
      final service = _Responder([_incident('91')]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatScreen(service: service)),
        ),
      );
      await tester.pump();

      expect(find.textContaining("Chat isn't available for this report"), findsOneWidget);
      final send = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send_rounded));
      expect(send.onPressed, isNull);
    });
  });

  group('B-d responder Open in Maps', () {
    testWidgets('shown for a report with real coordinates only', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MapTrackingScreen(service: _Responder([_incident('90')]))),
        ),
      );
      await tester.pump();
      expect(find.text('Open in Google Maps'), findsOneWidget);

      // Unmount first, so the second case gets a fresh screen, not the first one's state.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MapTrackingScreen(service: _Responder([_incident('91', lat: null)]))),
        ),
      );
      await tester.pump();
      expect(find.text('Open in Google Maps'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('B-e sign-in errors', () {
    test('a 5xx never shows the server text; 4xx and 429 are plain', () {
      const leak = 'SQLSTATE[08006] connection to server at "127.0.0.1", port 5433 failed';
      final message = AuthService.failureMessage(500, leak, 'Sign in');
      expect(message, isNot(contains('SQLSTATE')));
      expect(message, 'Rapid Alert is having trouble right now. Please try again in a moment.');
      expect(AuthService.failureMessage(429, 'Too Many Attempts.', 'Sign in'), startsWith('Too many attempts'));
      expect(
        AuthService.failureMessage(401, 'These credentials do not match our records.', 'Sign in'),
        'These credentials do not match our records.',
      );
      expect(
        AuthService.failureMessage(422, null, 'Sign in'),
        'Sign in failed. Please check your details and try again.',
      );
    });

    test('login turns a 500 into the plain message', () async {
      final client = MockClient((_) async => http.Response(jsonEncode({'message': 'SQLSTATE[08006] ...'}), 500));
      final error = await http.runWithClient(
        () => AuthService.login('a@b.c', 'x').then<Object?>((_) => null, onError: (Object e) => e),
        () => client,
      );
      expect(error, isA<AuthException>());
      expect((error! as AuthException).message, isNot(contains('SQLSTATE')));
    });
  });

  group('B-f responder dashboard counts', () {
    testWidgets('not loaded yet: dashes, not zeros', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(service: _Responder(const []), onNavigateToTab: (_) {}),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('0'), findsNothing);
    });

    testWidgets('resolved reports are not open cases', (tester) async {
      final service = _Responder([
        _incident('90'),
        _incident('85', status: ReportStatus.resolved),
      ], status: ReportListStatus(lastLoadedAt: DateTime(2026, 9, 30)));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(service: service, onNavigateToTab: (_) {}),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('2'), findsOneWidget, reason: 'assigned reports');
      expect(find.text('1'), findsOneWidget, reason: 'open cases');
    });
  });
}
