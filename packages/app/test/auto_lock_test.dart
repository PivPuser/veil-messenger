import 'package:crypto_core/crypto_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil/main.dart';
import 'package:veil/services/lock_service.dart';

import 'support/memory_lock_storage.dart';

Future<void> _enter(WidgetTester tester, String pin) async {
  for (final String c in pin.split('')) {
    await tester.tap(find.byKey(ValueKey<String>('pad_$c')));
    await tester.pump();
  }
}

Future<void> _lifecycle(WidgetTester tester, String state) async {
  final ByteData? msg = const StringCodec().encodeMessage(state);
  await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage('flutter/lifecycle', msg, (_) {});
}

/// Pumps (advancing time so async crypto can finish) until [finder] matches.
Future<void> _pumpUntil(WidgetTester tester, Finder finder,
    {int maxFrames = 60}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('locks at startup, unlocks, then re-locks on background',
      (WidgetTester tester) async {
    final MemoryLockStorage storage = MemoryLockStorage();
    await tester.runAsync(() async {
      await AppLock(storage, kdfMemory: 256, kdfIterations: 1)
          .enable(password: '1234', passwordLength: 4);
    });
    LockService.instance.initWithStorage(storage);

    await tester.pumpWidget(const VeilApp());
    await _pumpUntil(tester, find.text('Введи код-пароль'));
    expect(find.text('Введи код-пароль'), findsOneWidget);
    expect(find.text('собеседник'), findsNothing);

    // Unlock -> chat list.
    await _enter(tester, '1234');
    await _pumpUntil(tester, find.text('собеседник'));
    expect(find.text('собеседник'), findsOneWidget);

    // Background -> auto re-lock.
    await _lifecycle(tester, 'AppLifecycleState.paused');
    await _pumpUntil(tester, find.text('Введи код-пароль'));
    expect(find.text('Введи код-пароль'), findsOneWidget);
    expect(find.text('собеседник'), findsNothing);
  });
}
