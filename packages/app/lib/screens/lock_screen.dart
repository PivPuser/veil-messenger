import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/passcode_pad.dart';

/// The unlock gate shown on launch when a passcode is set.
///
/// Wrong passcodes count down to a wipe (the policy lives in [AppLock]); the
/// "delete data" button wipes immediately (with a confirmation to avoid an
/// accidental tap). On success [onUnlocked] receives the vault master key; a
/// wipe (button or too many wrong attempts) calls [onWiped].
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.appLock,
    required this.onUnlocked,
    required this.onWiped,
  });

  final AppLock appLock;
  final ValueChanged<Uint8List> onUnlocked;
  final VoidCallback onWiped;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  int _length = 4;
  String _entry = '';
  String? _warning;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.appLock.passwordLength().then((int? len) {
      if (mounted && len != null) setState(() => _length = len);
    });
  }

  Future<void> _onDigit(String d) async {
    if (_busy || _entry.length >= _length) return;
    setState(() => _entry += d);
    if (_entry.length == _length) await _submit();
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final Uint8List key = await widget.appLock.unlock(_entry);
      if (mounted) setState(() => _busy = false);
      widget.onUnlocked(key);
    } on WrongPasswordException catch (e) {
      if (!mounted) return;
      setState(() {
        _entry = '';
        _busy = false;
        _warning = e.remainingAttempts == 1
            ? 'Осталась 1 попытка'
            : 'Осталось попыток: ${e.remainingAttempts}';
      });
    } on DataWipedException {
      widget.onWiped();
    }
  }

  Future<void> _confirmWipe() async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Удалить все данные?'),
            content: const Text(
                'Все чаты и ключи будут стёрты без возможности восстановления.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: VeilColors.danger),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await widget.appLock.wipe();
    widget.onWiped();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const SizedBox(height: 32),
            const CircleAvatar(
              radius: 26,
              backgroundColor: Color(0xFFE9F2FD),
              child: Icon(Icons.lock, color: VeilColors.primary),
            ),
            const SizedBox(height: 10),
            const Text('veil',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Введи код-пароль',
                style: TextStyle(color: VeilColors.secondaryText)),
            const SizedBox(height: 20),
            SizedBox(
              height: 18,
              child: Text(
                _warning ?? '',
                style: const TextStyle(color: VeilColors.danger, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            PasscodePad(
              length: _length,
              entered: _entry.length,
              onDigit: _onDigit,
              onBackspace: _onBackspace,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _confirmWipe,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Удалить данные'),
              style: TextButton.styleFrom(foregroundColor: VeilColors.danger),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
