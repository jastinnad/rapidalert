import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rapidalert/data/backend_features.dart';
import 'package:rapidalert/data/mock_responder_service.dart';
import 'package:rapidalert/screens/coordination_screen.dart';
import 'package:rapidalert/screens/dashboard_screen.dart';

// Production has no follow-up, evacuation-record, resource, announcement or
// coordination-events endpoints yet; the responder UI must not offer them.
void main() {
  late MockResponderService service;

  setUp(() => service = MockResponderService());
  tearDown(() => service.dispose());

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('dashboard hides modules whose endpoints are not deployed', (tester) async {
    await tester.pumpWidget(host(DashboardScreen(service: service, onNavigateToTab: (_) {})));

    expect(find.text('Track Assigned Reports'), findsOneWidget);
    expect(find.text('Real-Time Coordination'), findsOneWidget);

    expect(BackendFeatures.followUps, isFalse);
    expect(find.text('Follow-Up Board'), findsNothing);
    expect(BackendFeatures.evacuationRecords, isFalse);
    expect(find.text('Evacuation Tracker'), findsNothing);
    expect(find.text('Active Centers'), findsNothing);
    expect(BackendFeatures.resources, isFalse);
    expect(find.text('Resources'), findsNothing);
    expect(BackendFeatures.responderAnnouncements, isFalse);
    expect(find.text('Announcements'), findsNothing);
  });

  testWidgets('Live tab says coordination is unavailable, not connected', (tester) async {
    await tester.pumpWidget(host(CoordinationScreen(service: service)));

    expect(BackendFeatures.coordinationFeed, isFalse);
    expect(find.text('Live coordination is not available yet'), findsOneWidget);
    expect(find.text('Connected to live coordination feed.'), findsNothing);
    expect(find.text('Waiting for coordination events...'), findsNothing);
  });

  test('push registration stays off until /api/device-token exists', () {
    expect(BackendFeatures.pushRegistration, isFalse);
  });
}
