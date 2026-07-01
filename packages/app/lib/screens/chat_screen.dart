import 'dart:async';

import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../theme.dart';

/// A single conversation, Telegram-style: encrypted-status header, wallpaper,
/// message bubbles and an input bar. Bound to a [ChatController].
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.controller,
    required this.title,
  });

  final ChatController controller;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrollToBottom);
    if (widget.controller.hasTransport) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => widget.controller.poll(),
      );
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    widget.controller.removeListener(_scrollToBottom);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final String text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await widget.controller.send(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 18,
              backgroundColor: VeilColors.avatarFor(widget.title),
              child: Text(
                widget.title.isNotEmpty
                    ? widget.title.substring(0, 1).toUpperCase()
                    : '?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  widget.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.lock, size: 11, color: Color(0xFFCDE4FA)),
                    SizedBox(width: 3),
                    Text('зашифровано',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFFCDE4FA))),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.verified_user_outlined),
            tooltip: 'Сверить безопасность',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (!widget.controller.hasTransport) const _NoRelayBanner(),
          Expanded(
            child: Container(
              color: VeilColors.chatWallpaper,
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (BuildContext context, Widget? _) {
                  final List<ChatMessage> msgs = widget.controller.messages;
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: msgs.length,
                    itemBuilder: (BuildContext context, int i) =>
                        _Bubble(message: msgs[i]),
                  );
                },
              ),
            ),
          ),
          _InputBar(controller: _input, onSend: _send),
        ],
      ),
    );
  }
}

class _NoRelayBanner extends StatelessWidget {
  const _NoRelayBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF6E5),
      padding: const EdgeInsets.all(10),
      child: const Text(
        'Релей не настроен — сообщения шифруются, но не отправляются. '
        'Укажи релей в настройках.',
        style: TextStyle(fontSize: 12, color: Color(0xFF8A6D1F)),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool out = message.outgoing;
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: out ? VeilColors.bubbleOut : VeilColors.bubbleIn,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(out ? 14 : 4),
            bottomRight: Radius.circular(out ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message.text,
              style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 2),
            Text(
              _formatTime(message.time),
              style: TextStyle(
                fontSize: 11,
                color:
                    out ? const Color(0xFF5AA0D6) : VeilColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.attach_file,
                  color: VeilColors.secondaryText),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Сообщение…',
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              onPressed: () => onSend(),
              icon: const Icon(Icons.send, color: VeilColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
