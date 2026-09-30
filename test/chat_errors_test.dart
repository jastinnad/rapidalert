import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:rapidalert/data/reporter_service.dart';
import 'package:rapidalert/models/responder_models.dart';
import 'package:rapidalert/screens/report_chat_screen.dart';

class _ChatService extends Fake implements ReporterService {
  _ChatService({required this.fail});

  bool fail;

  @override
  int? get currentUserId => 5;

  @override
  Future<List<ChatMessage>> loadReportMessages(int reportId) async {
    if (fail) throw http.ClientException('Failed host lookup');
    return const [];
  }
}

void main() {
  Future<void> pumpChat(WidgetTester tester, _ChatService service) async {
    await tester.pumpWidget(
      MaterialApp(home: ReportChatScreen(service: service, reportId: 1, receiverId: 6, receiverName: 'Rex Ander')),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a failed load is shown as an error with Retry, not as an empty chat', (tester) async {
    final service = _ChatService(fail: true);
    await pumpChat(tester, service);

    expect(find.textContaining("Couldn't load messages"), findsOneWidget);
    expect(find.textContaining('No messages yet'), findsNothing);
    expect(find.textContaining('ClientException'), findsNothing);

    service.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('No messages yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // stop the poll timer
  });

  testWidgets('the send button has an accessibility label', (tester) async {
    await pumpChat(tester, _ChatService(fail: false));

    expect(find.byTooltip('Send message'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
