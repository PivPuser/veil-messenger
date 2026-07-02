import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil/screens/set_passcode_screen.dart';

import 'support/memory_lock_storage.dart';

Future<void> _enter(WidgetTester tester, String pin) async {
  for (final String c in pin.split('')) {
    await tester.tap(find.byKey(ValueKey<String>('pad_$c')));
    await tester.pump();
  }
}

void main() {
  testWidgets('sets a 4-digit passcode (enter + confirm) and enables the lock',
      (WidgetTester tester) async {
    // Fast KDF + in-memory storage keeps the widget test snappy and settle-able.
    final AppLock lock = AppLock(MemoryLockStorage(), kdfIterations: 1);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push<Uint8List>(
                MaterialPageRoute<Uint8List>(
                  builder: (_) => SetPasscodeScreen(appLock: lock),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '4'));
    await tester.pumpAndSettle();

    await _enter(tester, '1234'); // choose
    await tester.pumpAndSettle();
    await _enter(tester, '1234'); // confirm
    await tester.pumpAndSettle();

    expect(await lock.isEnabled(), isTrue);
    expect(await lock.passwordLength(), 4);
  });

  testWidgets('mismatched confirmation shows an error and does not enable',
      (WidgetTester tester) async {
    final AppLock lock = AppLock(MemoryLockStorage(), kdfIterations: 1);

    await tester.pumpWidget(MaterialApp(home: SetPasscodeScreen(appLock: lock)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '4'));
    await tester.pumpAndSettle();

    await _enter(tester, '1234');
    await tester.pumpAndSettle();
    await _enter(tester, '9999');
    await tester.pumpAndSettle();

    expect(find.textContaining('не совпадают'), findsOneWidget);
    expect(await lock.isEnabled(), isFalse);
  });
}
