import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:rapidalert/data/api_responder_service.dart';
import 'package:rapidalert/data/responder_service.dart';
import 'package:rapidalert/models/responder_models.dart';
import 'package:rapidalert/screens/assigned_reports_screen.dart';
import 'package:rapidalert/screens/chat_screen.dart';
import 'package:rapidalert/screens/home_shell.dart';
import 'package:rapidalert/screens/map_tracking_screen.dart';

/// /api/responder/reports, as SharedReportController::myReports sends it.
Map<String, dynamic> _apiReport({
  int id = 95,
  int? reporterUserId = 5,
  Object? online = true,
  double? lat = 13.9412,
}) => {
  'reportId': id,
  'trackingId': 'RA-20260930-NKMOIA',
  'hazardType': 'Flood',
  'barangay': 'Bulacnin',
  'city': 'Lipa City',
  'reporterName': 'Vera Fyre',
  'status': 'en_route',
  'needHelp': false,
  'updatedAt': DateTime(2026, 9, 30, 9, 5).millisecondsSinceEpoch,
  'latitude': lat,
  'longitude': lat == null ? null : 121.1631,
  'reporterUserId': reporterUserId,
  'particular': 'Flood depth',
  'particularColor': 'orange',
  'particularDetail': 'Knee-to-waist deep, rising',
  'currentSituation': ['Floodwater is rising around my home'],
  'needs': ['rescue', 'medical'],
  'pregnantCount': 0,
  'elderlyCount': 2,
  'childCount': 0,
  'pwdCount': 1,
  'purok': 'Purok 1',
  'houseNo': '12',
  'landmark': 'Near the chapel',
  'phone': '09171234567',
  'alternateContact': '',
  'imageUrl': '',
  'createdAt': DateTime(2026, 9, 30, 9).millisecondsSinceEpoch,
  'reporterIsGuest': reporterUserId == null,
  'reporterOnline': ?online,
};

IncidentReport _report({
  String id = '95',
  String trackingId = 'RA-20260930-NKMOIA',
  ReportStatus status = ReportStatus.assigned,
  int? reporterUserId = 5,
  bool? online = true,
  double? lat = 13.9412,
  String reporterName = 'Vera Fyre',
}) => IncidentReport(
  id: id,
  trackingId: trackingId,
  hazard: 'Flood',
  location: 'Bulacnin',
  city: 'Lipa City',
  reporterName: reporterName,
  status: status,
  needHelp: false,
  updated: DateTime(2026, 9, 30, 9, 5),
  reportedAt: DateTime(2026, 9, 30, 9),
  reporterLat: lat,
  reporterLng: lat == null ? null : 121.1631,
  reporterUserId: reporterUserId,
  reporterOnline: reporterUserId == null ? null : online,
  particular: 'Flood depth',
  particularDetail: 'Knee-to-waist deep, rising',
  currentSituation: const ['Floodwater is rising around my home'],
  needs: const ['rescue', 'medical'],
  elderlyCount: 2,
  pwdCount: 1,
  purok: 'Purok 1',
  houseNo: '12',
  landmark: 'Near the chapel',
  phone: '09171234567',
);

/// A responder's app with [reports] assigned and an optional GPS fix.
class _Svc extends Fake implements ResponderService {
  _Svc(this._reports, {this.point, this.sharing = false});

  List<IncidentReport> _reports;
  final GeoPoint? point;
  final bool sharing;
  final _reportsCtrl = StreamController<List<IncidentReport>>.broadcast();
  final _chatCtrl = StreamController<List<ChatMessage>>.broadcast();

  /// Messages the backend holds, per report id.
  final threads = <String, List<ChatMessage>>{};
  final loads = <String>[];
  bool failLoads = false;
  final sent = <(String, int, String)>[];
  final statusCalls = <(String, ReportStatus)>[];
  bool failStatus = false;

  void setReports(List<IncidentReport> reports) {
    _reports = reports;
    _reportsCtrl.add(reports);
  }

  @override
  List<IncidentReport> get reports => _reports;
  @override
  Stream<List<IncidentReport>> get reportsStream => _reportsCtrl.stream;
  @override
  Stream<ReportListStatus> get reportListStatusStream => const Stream.empty();
  @override
  ReportListStatus get reportListStatus => ReportListStatus(lastLoadedAt: DateTime(2026, 9, 30));
  @override
  Future<void> refreshReports() async {}
  @override
  Stream<GeoPoint> get responderTrackingStream => const Stream.empty();
  @override
  GeoPoint? get currentResponderPoint => point;
  @override
  bool get isSharingLocation => sharing;

  @override
  Stream<List<ChatMessage>> get chatStream => _chatCtrl.stream;
  @override
  List<ChatMessage> messagesFor(String reportId) => List.of(threads[reportId] ?? const []);
  @override
  Future<void> loadMessages(String reportId) async {
    loads.add(reportId);
    if (failLoads) throw http.ClientException('Failed host lookup');
    _chatCtrl.add(const []);
  }

  @override
  Future<void> sendResponderMessage({required String reportId, required int receiverId, required String text}) async {
    sent.add((reportId, receiverId, text));
  }

  @override
  Future<void> updateReportStatus(String reportId, ReportStatus status) async {
    statusCalls.add((reportId, status));
    if (failStatus) throw Exception('Failed to update report status');
    setReports([for (final r in _reports) r.id == reportId ? r.copyWith(status: status) : r]);
  }
}

ChatMessage _msg(String id, String reportId, String text, {bool responder = false, DateTime? at}) => ChatMessage(
  id: id,
  reportId: reportId,
  sender: responder ? 'Rex Ander' : 'Vera Fyre',
  message: text,
  time: at ?? DateTime.now(),
  isResponder: responder,
);

Future<void> _phone(WidgetTester tester, {Size size = const Size(412, 915)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<LatLng> _markerPoints(WidgetTester tester) => [
  for (final m in tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers) m.point,
];

void main() {
  group('Responder report list from the API', () {
    test('keeps the Tracking ID, the report details and the real presence flag', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/responder/reports') {
          return http.Response(
            jsonEncode({
              'reports': [
                _apiReport(),
                _apiReport(id: 96, reporterUserId: null, online: null),
                _apiReport(id: 97, online: null), // older backend: no flag sent
                _apiReport(id: 98, online: false),
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'assignments': [], 'notifications': []}), 200);
      });
      late ApiResponderService service;
      await http.runWithClient(() async {
        service = ApiResponderService(baseUrl: 'http://api.test', bearerToken: 't', responderUserId: 6);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }, () => client);
      addTearDown(service.dispose);

      final report = service.reports.firstWhere((r) => r.id == '95');
      expect(report.trackingId, 'RA-20260930-NKMOIA');
      expect(report.displayId, 'RA-20260930-NKMOIA');
      expect(report.particularDetail, 'Knee-to-waist deep, rising');
      expect(report.needs, ['rescue', 'medical']);
      expect(report.currentSituation, ['Floodwater is rising around my home']);
      expect(report.landmark, 'Near the chapel');
      expect(report.phone, '09171234567');
      expect(report.elderlyCount, 2);
      expect(report.reportedAt, DateTime(2026, 9, 30, 9));
      expect(report.reporterOnline, isTrue);

      final guest = service.reports.firstWhere((r) => r.id == '96');
      expect(guest.isGuestReport, isTrue);
      expect(guest.reporterOnline, isNull);
      expect(service.reports.firstWhere((r) => r.id == '97').reporterOnline, isNull, reason: 'unknown, not offline');
      expect(service.reports.firstWhere((r) => r.id == '98').reporterOnline, isFalse);
    });

    test('chat goes to the report-bound endpoint and keeps the backend time and sender', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/reports/messages' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'id': 1,
                  'reportId': 95,
                  'senderId': 5,
                  'senderName': 'Vera Fyre',
                  'receiverId': 6,
                  'message': 'Water is at the door',
                  'createdAt': '2026-09-30T09:10:00+08:00',
                },
                {
                  'id': 2,
                  'reportId': 95,
                  'senderId': 6,
                  'senderName': 'Rex Ander',
                  'receiverId': 5,
                  'message': 'On the way',
                  'createdAt': '2026-09-30T09:11:00+08:00',
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/reports/messages') return http.Response(jsonEncode({'data': {}}), 200);
        return http.Response(jsonEncode({'reports': [], 'assignments': []}), 200);
      });
      late ApiResponderService service;
      await http.runWithClient(() async {
        service = ApiResponderService(baseUrl: 'http://api.test', bearerToken: 't', responderUserId: 6);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await service.loadMessages('95');
        await service.sendResponderMessage(reportId: '95', receiverId: 5, text: 'Stay upstairs');
      }, () => client);
      addTearDown(service.dispose);

      final thread = service.messagesFor('95');
      expect(thread.map((m) => m.message), ['Water is at the door', 'On the way']);
      expect(thread.map((m) => m.isResponder), [false, true]);
      expect(thread.first.time, DateTime.parse('2026-09-30T09:10:00+08:00'));
      expect(service.messagesFor('96'), isEmpty, reason: 'one report, one conversation');

      final get = requests.firstWhere((r) => r.url.path == '/api/reports/messages' && r.method == 'GET');
      expect(get.url.queryParameters, {'report_id': '95'});
      final post = requests.firstWhere((r) => r.url.path == '/api/reports/messages' && r.method == 'POST');
      expect(jsonDecode(post.body), {'report_id': 95, 'receiver_id': 5, 'message': 'Stay upstairs'});
    });
  });

  group('Responder map', () {
    testWidgets('a larger map plus the report details, Tracking ID and status', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTrackingScreen(service: _Svc([_report()])))));
      await tester.pump();

      expect(tester.getSize(find.byKey(const Key('responder-map'))).height, greaterThan(260));
      final details = find.byKey(const Key('responder-report-details'));
      expect(details, findsOneWidget);
      for (final text in [
        'RA-20260930-NKMOIA',
        'Flood — Flood depth',
        'Knee-to-waist deep, rising',
        '12, Purok 1, Bulacnin, Lipa City',
        'Near the chapel',
        'Vera Fyre · Online',
        '09171234567',
        'Floodwater is rising around my home',
        'rescue, medical',
        'Elderly 2 · PWD 1',
      ]) {
        expect(find.descendant(of: details, matching: find.text(text)), findsOneWidget, reason: text);
      }
      expect(find.descendant(of: details, matching: find.text('Assigned')), findsOneWidget);
      expect(find.text('RA-20260930-NKMOIA - Bulacnin'), findsOneWidget, reason: 'the picker uses the Tracking ID');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('on a small phone the map keeps a usable size', (tester) async {
      await _phone(tester, size: const Size(360, 640));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTrackingScreen(service: _Svc([_report()])))));
      await tester.pump();

      expect(tester.getSize(find.byKey(const Key('responder-map'))).height, greaterThanOrEqualTo(240));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the legend tells the report location from your own position', (tester) async {
      await _phone(tester);
      final svc = _Svc([_report(status: ReportStatus.enRoute)],
          point: GeoPoint(lat: 13.95, lng: 121.16, recordedAt: DateTime.now()), sharing: true);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTrackingScreen(service: svc))));
      await tester.pump();
      await tester.pump();

      final legend = find.byKey(const Key('responder-map-legend'));
      expect(find.descendant(of: legend, matching: find.text('Report location')), findsOneWidget);
      expect(find.descendant(of: legend, matching: find.text('You (live GPS)')), findsOneWidget);
      expect(_markerPoints(tester), containsAll([const LatLng(13.9412, 121.1631), const LatLng(13.95, 121.16)]));
      expect(find.textContaining('Live — sharing your location'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no GPS anywhere: nothing is drawn, not even at Lipa City', (tester) async {
      await _phone(tester);
      final svc = _Svc([_report(lat: null, status: ReportStatus.enRoute)], sharing: true);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTrackingScreen(service: svc))));
      await tester.pump();

      expect(_markerPoints(tester), isEmpty);
      expect(find.textContaining('Reporter location unavailable'), findsOneWidget);
      expect(find.textContaining('Waiting for your GPS position'), findsOneWidget);
      final legend = find.byKey(const Key('responder-map-legend'));
      expect(find.descendant(of: legend, matching: find.text('Report location — not sent')), findsOneWidget);
      expect(find.descendant(of: legend, matching: find.text('You — no GPS position yet')), findsOneWidget);
      expect(find.text('Open in Google Maps'), findsNothing);
      expect(find.textContaining('km'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('assigned, not yet started: your position is not "waited for"', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTrackingScreen(service: _Svc([_report()])))));
      await tester.pump();

      expect(find.textContaining('shown here once you tap Start — En Route'), findsOneWidget);
      expect(find.textContaining('Waiting for your GPS'), findsNothing);
      expect(_markerPoints(tester), [const LatLng(13.9412, 121.1631)], reason: 'only the report pin');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the next status step is offered on the map and goes to the backend', (tester) async {
      await _phone(tester);
      final svc = _Svc([_report(status: ReportStatus.enRoute)]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTrackingScreen(service: svc))));
      await tester.pump();

      final button = find.byKey(const Key('map-next-step'));
      expect(find.descendant(of: button, matching: find.text('Arrived — On Scene')), findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump();
      expect(svc.statusCalls, [('95', ReportStatus.onScene)]);
      expect(find.descendant(of: button, matching: find.text('Mark Resolved')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('resolved reports offer no further step', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MapTrackingScreen(service: _Svc([_report(status: ReportStatus.resolved)])))),
      );
      await tester.pump();
      expect(find.byKey(const Key('map-next-step')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Message reporter opens that report\'s chat; not for a guest report', (tester) async {
      await _phone(tester);
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MapTrackingScreen(service: _Svc([_report()]), onOpenChat: (id) => opened = id)),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('map-message-reporter')));
      await tester.tap(find.byKey(const Key('map-message-reporter')));
      expect(opened, '95');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapTrackingScreen(service: _Svc([_report(reporterUserId: null)]), onOpenChat: (_) {}),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('map-message-reporter')), findsNothing);
      expect(find.textContaining('Guest report (no account)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Start — En Route', () {
    testWidgets('opens the map on that report once the backend accepts it', (tester) async {
      await _phone(tester);
      final svc = _Svc([_report(), _report(id: '91', trackingId: 'RA-OTHER')]);
      String? opened;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignedReportsScreen(service: svc, onOpenMap: (id) => opened = id))),
      );
      await tester.pump();

      expect(find.text('RA-20260930-NKMOIA'), findsOneWidget, reason: 'cards are titled by Tracking ID');
      await tester.tap(find.byKey(const Key('report-next-step-95')));
      await tester.pump();
      await tester.pump();
      expect(svc.statusCalls, [('95', ReportStatus.enRoute)]);
      expect(opened, '95');
    });

    testWidgets('a failed Start stays on the list with an error', (tester) async {
      await _phone(tester);
      final svc = _Svc([_report()])..failStatus = true;
      String? opened;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignedReportsScreen(service: svc, onOpenMap: (id) => opened = id))),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('report-next-step-95')));
      await tester.pump();
      await tester.pump();
      expect(opened, isNull);
      expect(find.text('Failed to update status. Please try again.'), findsOneWidget);
    });

    testWidgets('in the app: Start switches to the Map tab with that report\'s details', (tester) async {
      await _phone(tester);
      // No session: the sample-data service (debug builds only).
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pump();
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));

      // RA-2026-0019 is an assigned sample report.
      await tester.ensureVisible(find.byKey(const Key('report-next-step-RA-2026-0019')));
      await tester.tap(find.byKey(const Key('report-next-step-RA-2026-0019')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MapTrackingScreen), findsOneWidget);
      final id = find.byKey(const Key('responder-tracking-id'));
      expect(tester.widget<SelectableText>(id).data, 'RA-2026-0019');
      expect(find.descendant(of: find.byKey(const Key('responder-report-details')), matching: find.text('En Route')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Responder chat', () {
    testWidgets('shows the Tracking ID, reporter and presence for the open conversation', (tester) async {
      await _phone(tester);
      final svc = _Svc([_report(), _report(id: '91', trackingId: 'RA-OTHER', reporterName: 'Ana Cruz', online: false)]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatScreen(service: svc))));
      await tester.pump();

      expect(find.text('Report RA-20260930-NKMOIA'), findsOneWidget);
      expect(find.text('Vera Fyre · Online'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatScreen(service: svc, initialReportId: '91'))));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatScreen(service: svc, initialReportId: '91'))));
      await tester.pump();
      expect(find.text('Report RA-OTHER'), findsOneWidget);
      expect(find.text('Ana Cruz · Not online right now'), findsOneWidget);
      expect(svc.loads.last, '91');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('unknown presence is not shown as offline', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatScreen(service: _Svc([_report(online: null)])))));
      await tester.pump();
      expect(find.textContaining('Not online'), findsNothing);
      expect(find.textContaining('Online'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('only the open report\'s messages are shown, with their times', (tester) async {
      await _phone(tester);
      final svc = _Svc([_report(), _report(id: '91', trackingId: 'RA-OTHER')]);
      final today = DateTime.now();
      svc.threads['95'] = [
        _msg('1', '95', 'Water is at the door', at: DateTime(today.year, today.month, today.day, 9, 10)),
        _msg('2', '95', 'On the way', responder: true, at: DateTime(today.year, today.month, today.day, 9, 11)),
      ];
      svc.threads['91'] = [_msg('3', '91', 'A different report')];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatScreen(service: svc))));
      await tester.pump();

      expect(find.text('Water is at the door'), findsOneWidget);
      expect(find.text('On the way'), findsOneWidget);
      expect(find.text('9:10 AM'), findsOneWidget);
      expect(find.text('9:11 AM'), findsOneWidget);
      expect(find.text('A different report'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sends to the report owner on the open report', (tester) async {
      await _phone(tester);
      final svc = _Svc([_report()]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatScreen(service: svc))));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Stay upstairs');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(svc.sent, [('95', 5, 'Stay upstairs')]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('refreshes the open conversation while shown, and says when that fails', (tester) async {
      await _phone(tester);
      final svc = _Svc([_report()]);
      svc.threads['95'] = [_msg('1', '95', 'Water is at the door')];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatScreen(service: svc))));
      await tester.pump();
      expect(svc.loads, ['95']);

      // A reply arrives on the backend: the next refresh shows it.
      svc.threads['95']!.add(_msg('2', '95', 'Second floor now'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(svc.loads, ['95', '95']);
      expect(find.text('Second floor now'), findsOneWidget);

      svc.failLoads = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text("Couldn't refresh messages; showing the last ones loaded."), findsOneWidget);
      expect(find.text('Water is at the door'), findsOneWidget, reason: 'the last messages stay');

      svc.failLoads = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text("Couldn't refresh messages; showing the last ones loaded."), findsNothing);

      await tester.pumpWidget(const SizedBox());
      final before = svc.loads.length;
      await tester.pump(const Duration(seconds: 10));
      expect(svc.loads.length, before, reason: 'no refreshing once the chat is closed');
    });

    testWidgets('a list that loads after the chat opens selects a report', (tester) async {
      await _phone(tester);
      final svc = _Svc(const []);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatScreen(service: svc))));
      await tester.pump();
      expect(find.text('No assigned reports to chat about.'), findsOneWidget);

      svc.setReports([_report()]);
      await tester.pump(); // delivers the list
      await tester.pump(); // selects the first report and loads it
      await tester.pump(); // shows it
      expect(find.text('Report RA-20260930-NKMOIA'), findsOneWidget);
      expect(svc.loads, ['95']);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
