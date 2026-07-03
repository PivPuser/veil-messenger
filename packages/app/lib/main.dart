import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/chat_list_screen.dart';
import 'screens/lock_screen.dart';
import 'services/identity_service.dart';
import 'services/lock_service.dart';
import 'services/receive_service.dart';
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

class _AppGateState extends State<AppGate> with WidgetsBindingObserver {
  bool? _locked; // null = still checking

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    final bool enabled = await LockService.instance.lock.isEnabled();
    if (mounted) setState(() => _locked = enabled);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-lock: when the app leaves the foreground, re-require the passcode and
    // drop in-memory secrets, so grabbing an unlocked phone reveals nothing.
    if (state == AppLifecycleState.paused) _maybeRelock();
  }

  Future<void> _maybeRelock() async {
    if (_locked != false) return;
    if (!await LockService.instance.lock.isEnabled()) return;
    _clearMemorySecrets();
    if (mounted) setState(() => _locked = true);
  }

  void _clearMemorySecrets() {
    IdentityService.instance.reset();
    ReceiveService.instance.clear();
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
        onUnlocked: (Uint8List key) {
          // Unlock succeeded: open the encrypted identity vault with the key.
          IdentityService.instance.configure(
            store: LockService.instance.vaultStore,
            masterKey: key,
          );
          setState(() => _locked = false);
        },
        onWiped: () {
          // Everything is gone: drop in-memory secrets too.
          _clearMemorySecrets();
          setState(() => _locked = false);
        },
      );
    }
    return const ChatListScreen();
  }
}
