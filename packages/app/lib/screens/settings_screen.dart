import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/identity_service.dart';
import '../services/lock_service.dart';
import '../services/relay_config.dart';
import '../theme.dart';
import 'set_passcode_screen.dart';

/// App settings: the passcode/panic-wipe toggle and the relay address.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _passcodeOn = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bool on = await LockService.instance.lock.isEnabled();
    if (!mounted) return;
    setState(() {
      _passcodeOn = on;
      _loading = false;
    });
  }

  Future<void> _togglePasscode(bool value) async {
    if (value) {
      final Uint8List? masterKey = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute<Uint8List>(
          builder: (_) =>
              SetPasscodeScreen(appLock: LockService.instance.lock),
        ),
      );
      if (masterKey == null) return;
      // Seal the current identity under the new passcode key so it survives
      // restarts and is protected at rest.
      final identity = await IdentityService.instance.identity();
      await LockService.instance.vaultStore.saveIdentity(identity, masterKey);
      IdentityService.instance.configure(
        store: LockService.instance.vaultStore,
        masterKey: masterKey,
      );
      if (mounted) setState(() => _passcodeOn = true);
    } else {
      final bool ok = await _confirmDisable();
      if (!ok) return;
      await LockService.instance.lock.disable();
      if (mounted) setState(() => _passcodeOn = false);
    }
  }

  Future<bool> _confirmDisable() async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Отключить код-пароль?'),
            content: const Text(
                'Приложение перестанет запрашивать код и удалять данные при '
                'неверном вводе.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Отключить'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _editRelay() async {
    final TextEditingController input = TextEditingController(
      text: RelayConfig.instance.baseUrl?.toString() ?? '',
    );
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Адрес релея'),
        content: TextField(
          controller: input,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'http://…  или  …onion'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, input.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (value == null) return;
    setState(() {
      RelayConfig.instance.baseUrl =
          value.isEmpty ? null : Uri.tryParse(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: <Widget>[
                const _SectionLabel('Защита'),
                SwitchListTile(
                  title: const Text('Код-пароль'),
                  subtitle: const Text(
                      'Запрос кода при входе; 2 неверных ввода стирают все данные'),
                  value: _passcodeOn,
                  onChanged: _togglePasscode,
                ),
                const Divider(height: 0),
                const _SectionLabel('Сеть'),
                ListTile(
                  title: const Text('Релей'),
                  subtitle: Text(
                    RelayConfig.instance.baseUrl?.toString() ?? 'не задан',
                    style: const TextStyle(color: VeilColors.secondaryText),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _editRelay,
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
            color: VeilColors.secondaryText, fontSize: 12),
      ),
    );
  }
}
