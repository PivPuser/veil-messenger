import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../theme.dart';
import 'create_key_screen.dart';
import 'enter_key_screen.dart';
import 'settings_screen.dart';

/// Home screen: the list of conversations, Telegram-style, with a compose FAB
/// that offers "create key" / "enter key".
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  // Placeholder data until sessions are wired to persistence.
  static const List<Chat> _demoChats = <Chat>[
    Chat(
      id: '1',
      title: 'собеседник',
      lastMessage: 'И сервер не знает, что мы общаемся',
      time: '14:22',
      unread: 2,
    ),
    Chat(
      id: '2',
      title: 'команда',
      lastMessage: 'Ключ сработал 👌',
      time: 'пн',
    ),
    Chat(
      id: '3',
      title: 'мимо',
      lastMessage: 'Вы: увидимся',
      time: 'вс',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const _AppDrawer(),
      appBar: AppBar(
        title: const Text('veil'),
        actions: <Widget>[
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search),
            tooltip: 'Поиск',
          ),
        ],
      ),
      body: _demoChats.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              itemCount: _demoChats.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 76,
                color: VeilColors.divider,
              ),
              itemBuilder: (BuildContext context, int index) =>
                  _ChatTile(chat: _demoChats[index]),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatSheet(context),
        backgroundColor: VeilColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Новый чат',
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }

  void _showNewChatSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined,
                    color: VeilColors.primary),
                title: const Text('Создать ключ'),
                subtitle: const Text('Пригласить собеседника'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CreateKeyScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.login, color: VeilColors.primary),
                title: const Text('Ввести ключ'),
                subtitle: const Text('Подключиться по ключу'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EnterKeyScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: VeilColors.avatarFor(chat.id),
        child: Text(
          chat.initials,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      title: Text(
        chat.title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        chat.lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: VeilColors.secondaryText),
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            chat.time,
            style: const TextStyle(
                color: VeilColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 4),
          if (chat.unread > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: const BoxDecoration(
                color: VeilColors.primary,
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: Text(
                '${chat.unread}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            )
          else
            const SizedBox(height: 18),
        ],
      ),
      onTap: () {},
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          const DrawerHeader(
            decoration: BoxDecoration(color: VeilColors.primary),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'veil',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Настройки'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.lock_outline, size: 48, color: VeilColors.secondaryText),
            SizedBox(height: 12),
            Text(
              'Пока нет чатов.\nСоздай ключ или введи чужой, чтобы начать.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VeilColors.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}
