class Message {
  final String eventTitle;
  final String lastMessage;
  final String senderAvatarUrl;
  final String time;
  final bool isRead;

  Message({
    required this.eventTitle,
    required this.lastMessage,
    required this.senderAvatarUrl,
    required this.time,
    this.isRead = false,
  });
}
