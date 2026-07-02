import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';
import 'package:relay/relay.dart';

import 'chat_service.dart';

/// A persisted conversation: its stable [id], display [title], and live
/// [controller].
class StoredChat {
  StoredChat({
    required this.id,
    required this.title,
    required this.controller,
  });

  final String id;
  final String title;
  final ChatController controller;
}

/// Persists conversations encrypted at rest.
///
/// Each chat is serialized, sealed with [SecretVault] under the vault master
/// key, and written through a [LockStorage] (the same directory the panic wipe
/// clears). A small sealed index lists the chat ids.
class ChatStore {
  ChatStore(this._storage);

  final LockStorage _storage;

  static const String _indexKey = 'chats.index';

  Future<void> saveChat({
    required String id,
    required String title,
    required ChatController controller,
    required Uint8List masterKey,
  }) async {
    final String json = jsonEncode(<String, dynamic>{
      'title': title,
      'chat': await controller.toJson(),
    });
    final Uint8List sealed =
        await SecretVault.seal(masterKey: masterKey, plaintext: utf8.encode(json));
    await _storage.write(_chatKey(id), sealed);

    final List<String> ids = await _loadIndex(masterKey);
    if (!ids.contains(id)) {
      ids.add(id);
      await _saveIndex(ids, masterKey);
    }
  }

  Future<List<StoredChat>> loadChats(
    Uint8List masterKey, {
    RelayTransport? transport,
  }) async {
    final List<String> ids = await _loadIndex(masterKey);
    final List<StoredChat> out = <StoredChat>[];
    for (final String id in ids) {
      final Uint8List? blob = await _storage.read(_chatKey(id));
      if (blob == null) continue;
      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(await SecretVault.open(masterKey: masterKey, blob: blob)),
      ) as Map<String, dynamic>;
      out.add(StoredChat(
        id: id,
        title: json['title'] as String,
        controller: await ChatController.fromJson(
          json['chat'] as Map<String, dynamic>,
          transport: transport,
        ),
      ));
    }
    return out;
  }

  static String _chatKey(String id) => 'chat.$id';

  Future<List<String>> _loadIndex(Uint8List masterKey) async {
    final Uint8List? blob = await _storage.read(_indexKey);
    if (blob == null) return <String>[];
    final List<dynamic> list = jsonDecode(
      utf8.decode(await SecretVault.open(masterKey: masterKey, blob: blob)),
    ) as List<dynamic>;
    return list.cast<String>();
  }

  Future<void> _saveIndex(List<String> ids, Uint8List masterKey) async {
    final Uint8List sealed = await SecretVault.seal(
      masterKey: masterKey,
      plaintext: utf8.encode(jsonEncode(ids)),
    );
    await _storage.write(_indexKey, sealed);
  }
}
