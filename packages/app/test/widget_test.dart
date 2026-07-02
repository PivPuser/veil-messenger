import 'package:flutter_test/flutter_test.dart';

import 'package:veil/main.dart';
import 'package:veil/services/lock_service.dart';

import 'support/memory_lock_storage.dart';

void main() {
  testWidgets('shows the chat list on launch (no passcode set)',
      (WidgetTester tester) async {
    LockService.instance.initWithStorage(MemoryLockStorage());

    await tester.pumpWidget(const VeilApp());
    await tester.pumpAndSettle();

    expect(find.text('veil'), findsOneWidget);
    expect(find.text('собеседник'), findsOneWidget);
  });
}
