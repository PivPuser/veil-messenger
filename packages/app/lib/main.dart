import 'package:flutter/material.dart';

import 'screens/chat_list_screen.dart';
import 'theme.dart';

void main() => runApp(const VeilApp());

class VeilApp extends StatelessWidget {
  const VeilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'veil',
      debugShowCheckedModeBanner: false,
      theme: buildVeilTheme(),
      home: const ChatListScreen(),
    );
  }
}
