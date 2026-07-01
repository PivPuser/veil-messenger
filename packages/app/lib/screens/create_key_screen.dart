import 'package:crypto_core/crypto_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/identity_service.dart';
import '../theme.dart';

/// Чел1: generates a fresh signed pre-key bundle and shows the shareable
/// "amk1:" key (as text and QR) to hand to Чел2.
class CreateKeyScreen extends StatefulWidget {
  const CreateKeyScreen({super.key});

  @override
  State<CreateKeyScreen> createState() => _CreateKeyScreenState();
}

class _CreateKeyScreenState extends State<CreateKeyScreen> {
  late final Future<String> _keyFuture = _generateKey();

  Future<String> _generateKey() async {
    final Identity identity = await IdentityService.instance.identity();
    final PreKeys preKeys = await PreKeys.generate(identity);
    final InviteKey invite = await InviteKey.create(identity, preKeys);
    return invite.encode();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый ключ')),
      body: FutureBuilder<String>(
        future: _keyFuture,
        builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Не удалось создать ключ'));
          }
          return _KeyView(keyString: snapshot.data!);
        },
      ),
    );
  }
}

class _KeyView extends StatelessWidget {
  const _KeyView({required this.keyString});

  final String keyString;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: VeilColors.divider),
            ),
            child: QrImageView(
              data: keyString,
              version: QrVersions.auto,
              size: 200,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: VeilColors.field,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            keyString,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _copy(context),
          icon: const Icon(Icons.copy),
          label: const Text('Копировать ключ'),
          style: FilledButton.styleFrom(
            backgroundColor: VeilColors.primary,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Отдай ключ собеседнику любым способом. Он введёт его — и защищённый '
          'канал поднимется. Никто, кроме вас двоих, не прочитает переписку.',
          style: TextStyle(color: VeilColors.secondaryText, fontSize: 13),
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: keyString));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ключ скопирован')),
    );
  }
}
