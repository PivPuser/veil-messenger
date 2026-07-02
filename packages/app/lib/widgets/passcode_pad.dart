import 'package:flutter/material.dart';

import '../theme.dart';

/// Passcode dots + numeric keypad. Stateless: the parent owns the entered
/// value and re-renders with the new [entered] count.
class PasscodePad extends StatelessWidget {
  const PasscodePad({
    super.key,
    required this.length,
    required this.entered,
    required this.onDigit,
    required this.onBackspace,
  });

  final int length;
  final int entered;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Dots(length: length, filled: entered),
        const SizedBox(height: 28),
        _Keypad(onDigit: onDigit, onBackspace: onBackspace),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.length, required this.filled});

  final int length;
  final int filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(length, (int i) {
        final bool on = i < filled;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? VeilColors.primary : Colors.transparent,
            border: on
                ? null
                : Border.all(color: const Color(0xFFC4CBD1), width: 1.5),
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
        children: <Widget>[
          for (final String d in <String>['1', '2', '3', '4', '5', '6', '7', '8', '9'])
            _Key(key: ValueKey<String>('pad_$d'), label: d, onTap: () => onDigit(d)),
          const SizedBox.shrink(),
          _Key(
              key: const ValueKey<String>('pad_0'),
              label: '0',
              onTap: () => onDigit('0')),
          _Key(
            key: const ValueKey<String>('pad_back'),
            onTap: onBackspace,
            child: const Icon(Icons.backspace_outlined,
                color: VeilColors.secondaryText),
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({super.key, required this.onTap, this.label, this.child});

  final VoidCallback onTap;
  final String? label;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: label == null ? Colors.transparent : VeilColors.field,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Center(
          child: child ??
              Text(label!, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }
}
