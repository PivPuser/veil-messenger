import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/chat_list_screen.dart';
import 'screens/lock_screen.dart';
import 'services/lock_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Directory support = await getApplicationSupportDirectory();
  final Directory dataDir =
      Directory('${support.path}${Platform.pathSeparator}vault');
  LockService.instance.initWith(dataDir);
  runApp(const VeilApp());
}

class VeilApp extends StatelessWidget {
  const VeilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'veil',
      debugShowCheckedModeBanner: false,
      theme: buildVeilTheme(),
      home: const AppGate(),
    );
  }
}

/// Decides the first screen: the passcode lock (if set) or the chat list.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool? _locked; // null = still checking

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final bool enabled = await LockService.instance.lock.isEnabled();
    if (mounted) setState(() => _locked = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final bool? locked = _locked;
    if (locked == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (locked) {
      return LockScreen(
        appLock: LockService.instance.lock,
        onUnlocked: (_) => setState(() => _locked = false),
        onWiped: () => setState(() => _locked = false),
      );
    }
    return const ChatListScreen();
  }
}
