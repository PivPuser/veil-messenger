/// A conversation shown in the chat list.
///
/// For now this is a lightweight view model with demo data; later it will be
/// backed by persisted [Session] state from crypto_core.
class Chat {
  const Chat({
    required this.id,
    required this.title,
    required this.lastMessage,
    required this.time,
    this.unread = 0,
  });

  final String id;
  final String title;
  final String lastMessage;
  final String time;
  final int unread;

  String get initials =>
      title.isEmpty ? '?' : title.substring(0, 1).toUpperCase();
}
