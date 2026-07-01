import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil/screens/enter_key_screen.dart';

void main() {
  testWidgets('shows an error for an invalid key', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: EnterKeyScreen()));

    await tester.enterText(find.byType(TextField), 'не-ключ');
    await tester.tap(find.text('Подключиться'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Неверный или повреждённый'), findsOneWidget);
  });
}
