import 'package:flutter_test/flutter_test.dart';

import 'package:veil/main.dart';

void main() {
  testWidgets('shows the chat list on launch', (WidgetTester tester) async {
    await tester.pumpWidget(const VeilApp());
    await tester.pumpAndSettle();

    // App bar title and a demo chat should be visible.
    expect(find.text('veil'), findsOneWidget);
    expect(find.text('собеседник'), findsOneWidget);
  });
}
