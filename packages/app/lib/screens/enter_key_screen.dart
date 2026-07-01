import 'package:flutter/material.dart';

/// Чел2: pastes an "amk1:" key to connect. Implemented in the next step; this
/// placeholder keeps navigation working and `flutter analyze` green.
class EnterKeyScreen extends StatelessWidget {
  const EnterKeyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ввести ключ')),
      body: const Center(child: Text('Скоро')),
    );
  }
}
