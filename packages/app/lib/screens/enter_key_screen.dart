import 'package:crypto_core/crypto_core.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/identity_service.dart';
import '../services/relay_config.dart';
import '../theme.dart';
import 'chat_screen.dart';

/// Чел2: pastes an "amk1:" key, validates it, and opens the chat.
class EnterKeyScreen extends StatefulWidget {
  const EnterKeyScreen({super.key});

  @override
  State<EnterKeyScreen> createState() => _EnterKeyScreenState();
}

class _EnterKeyScreenState extends State<EnterKeyScreen> {
  final TextEditingController _input = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final String text = _input.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Вставь ключ, полученный от собеседника.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final InviteKey invite = await InviteKey.decode(text);
      if (!await invite.verify()) {
        throw const FormatException('bad signature');
      }
      final Identity me = await IdentityService.instance.identity();
      final ChatController controller = await ChatController.startFromInvite(
        me: me,
        invite: invite,
        transport: RelayConfig.instance.transport(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              ChatScreen(controller: controller, title: 'собеседник'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Неверный или повреждённый ключ.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ввести ключ')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text(
            'Вставь ключ вида amk1:… который тебе отдал собеседник.',
            style: TextStyle(color: VeilColors.secondaryText),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            minLines: 3,
            maxLines: 6,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'amk1:…',
              filled: true,
              fillColor: VeilColors.field,
              errorText: _error,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _connect,
            style: FilledButton.styleFrom(
              backgroundColor: VeilColors.primary,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Подключиться'),
          ),
        ],
      ),
    );
  }
}
