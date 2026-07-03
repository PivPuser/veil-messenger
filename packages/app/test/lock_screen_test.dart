import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil/screens/lock_screen.dart';

import 'support/memory_lock_storage.dart';

Future<void> _enter(WidgetTester tester, String pin) async {
  for (final String c in pin.split('')) {
    await tester.tap(find.byKey(ValueKey<String>('pad_$c')));
    await tester.pump();
  }
}

Future<AppLock> _enabledLock() async {
  final AppLock lock = AppLock(MemoryLockStorage(), kdfMemory: 256, kdfIterations: 1);
  await lock.enable(password: '1234', passwordLength: 4);
  return lock;
}

void main() {
  testWidgets('correct passcode unlocks', (WidgetTester tester) async {
    final AppLock lock = await _enabledLock();
    Uint8List? unlockedKey;
    bool wiped = false;

    await tester.pumpWidget(MaterialApp(
      home: LockScreen(
        appLock: lock,
        onUnlocked: (Uint8List k) => unlockedKey = k,
        onWiped: () => wiped = true,
      ),
    ));
    await tester.pumpAndSettle();

    await _enter(tester, '1234');
    await tester.pumpAndSettle();

    expect(unlockedKey, isNotNull);
    expect(unlockedKey!.length, 32);
    expect(wiped, isFalse);
  });

  testWidgets('two wrong passcodes wipe the data', (WidgetTester tester) async {
    final AppLock lock = await _enabledLock();
    bool wiped = false;

    await tester.pumpWidget(MaterialApp(
      home: LockScreen(
        appLock: lock,
        onUnlocked: (_) {},
        onWiped: () => wiped = true,
      ),
    ));
    await tester.pumpAndSettle();

    await _enter(tester, '0000');
    await tester.pumpAndSettle();
    expect(find.text('Осталась 1 попытка'), findsOneWidget);
    expect(wiped, isFalse);

    await _enter(tester, '9999');
    await tester.pumpAndSettle();
    expect(wiped, isTrue);
  });
}
