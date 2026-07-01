import 'package:flutter/material.dart';

/// Чел1: generates and shows the shareable "amk1:" key. Implemented in the next
/// step; this placeholder keeps navigation working and `flutter analyze` green.
class CreateKeyScreen extends StatelessWidget {
  const CreateKeyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый ключ')),
      body: const Center(child: Text('Скоро')),
    );
  }
}
