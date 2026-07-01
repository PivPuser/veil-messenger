import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veil/screens/create_key_screen.dart';

void main() {
  testWidgets('generates and shows a real amk1 key', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreateKeyScreen()));

    // Key generation is async; let the FutureBuilder resolve.
    await tester.pumpAndSettle();

    expect(find.textContaining('amk1:'), findsOneWidget);
    expect(find.text('Копировать ключ'), findsOneWidget);
  });
}
