import 'package:crypto_core/crypto_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/passcode_pad.dart';

/// Lets the user pick a passcode length (4 / 6 / 12) and set it (enter + confirm).
/// On success it enables [appLock] and pops `true`.
class SetPasscodeScreen extends StatefulWidget {
  const SetPasscodeScreen({super.key, required this.appLock});

  final AppLock appLock;

  @override
  State<SetPasscodeScreen> createState() => _SetPasscodeScreenState();
}

class _SetPasscodeScreenState extends State<SetPasscodeScreen> {
  int _length = 6;
  String _entry = '';
  String? _first; // first entry, awaiting confirmation
  String? _error;

  bool get _confirming => _first != null;

  Future<void> _onDigit(String d) async {
    if (_entry.length >= _length) return;
    setState(() {
      _entry += d;
      _error = null;
    });
    if (_entry.length == _length) {
      await _onComplete();
    }
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _onComplete() async {
    if (!_confirming) {
      setState(() {
        _first = _entry;
        _entry = '';
      });
      return;
    }
    if (_entry == _first) {
      await widget.appLock.enable(password: _entry, passwordLength: _length);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = 'Коды не совпадают. Попробуй снова.';
        _first = null;
        _entry = '';
      });
    }
  }

  void _selectLength(int value) {
    setState(() {
      _length = value;
      _entry = '';
      _first = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Код-пароль')),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: <Widget>[
            Text(
              _confirming ? 'Повтори код-пароль' : 'Придумай код-пароль',
              style: const TextStyle(color: VeilColors.secondaryText),
            ),
            const SizedBox(height: 16),
            if (!_confirming)
              _LengthPicker(selected: _length, onSelect: _selectLength),
            SizedBox(height: _error == null ? 20 : 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: const TextStyle(color: VeilColors.danger)),
              ),
            const Spacer(),
            PasscodePad(
              length: _length,
              entered: _entry.length,
              onDigit: _onDigit,
              onBackspace: _onBackspace,
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _LengthPicker extends StatelessWidget {
  const _LengthPicker({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (final int len in AppLock.allowedLengths)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text('$len'),
              selected: selected == len,
              onSelected: (_) => onSelect(len),
              selectedColor: VeilColors.primary,
              labelStyle: TextStyle(
                color: selected == len ? Colors.white : VeilColors.secondaryText,
              ),
            ),
          ),
      ],
    );
  }
}
