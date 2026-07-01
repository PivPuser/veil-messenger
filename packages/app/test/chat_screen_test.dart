import 'package:crypto_core/crypto_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil/screens/chat_screen.dart';
import 'package:veil/services/chat_service.dart';

Future<ChatController> _offlineController() async {
  final Identity bob = await Identity.generate();
  final PreKeys bobPreKeys = await PreKeys.generate(bob);
  final InviteKey invite = await InviteKey.create(bob, bobPreKeys);
  final Identity alice = await Identity.generate();
  // No transport -> offline: encrypt + show, but don't deliver.
  final ChatController controller =
      await ChatController.startFromInvite(me: alice, invite: invite);
  controller.messages.addAll(<ChatMessage>[
    ChatMessage(text: 'привет', outgoing: false, time: DateTime.now()),
    ChatMessage(text: 'здарова', outgoing: true, time: DateTime.now()),
  ]);
  return controller;
}

void main() {
  testWidgets('renders bubbles and appends a sent message',
      (WidgetTester tester) async {
    final ChatController controller = await _offlineController();

    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(controller: controller, title: 'собеседник'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('привет'), findsOneWidget);
    expect(find.text('здарова'), findsOneWidget);
    // Offline banner shows because there is no transport.
    expect(find.textContaining('Релей не настроен'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'новое сообщение');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('новое сообщение'), findsOneWidget);
  });
}
