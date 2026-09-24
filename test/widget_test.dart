import 'package:flutter_test/flutter_test.dart';

import 'package:rapidalert/main.dart';

void main() {
  testWidgets('App loads responder shell', (WidgetTester tester) async {
    await tester.pumpWidget(const RapidAlertApp());

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
  });
}
