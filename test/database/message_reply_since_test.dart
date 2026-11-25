import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  setUpAll(openTestDatabase);
  setUp(Database.reset);

  final since = DateTime.utc(2020, 1, 2);

  void saveReply({required DateTime created, bool fromMe = true, DateTime? deleted}) {
    final chat = Chat(guid: 'chat');
    Database.chats.put(chat);
    final reply = Message(
      guid: 'reply',
      threadOriginatorGuid: 'thread',
      dateCreated: created,
      isFromMe: fromMe,
      dateDeleted: deleted,
    )..chat.target = chat;
    Database.messages.put(reply);
  }

  test('my reply after the pick time makes the saved reply stale', () {
    saveReply(created: since.add(const Duration(seconds: 1)));
    expect(Message.hasReplyFromMeSince('thread', since), isTrue);
  });

  test('my reply before the pick time keeps a later reply', () {
    saveReply(created: since.subtract(const Duration(seconds: 1)));
    expect(Message.hasReplyFromMeSince('thread', since), isFalse);
  });

  test('legacy saved reply is stale when I replied at any time', () {
    saveReply(created: since.subtract(const Duration(seconds: 1)));
    expect(Message.hasReplyFromMeSince('thread', null), isTrue);
  });

  test('another person replying after the pick time does not make it stale', () {
    saveReply(created: since.add(const Duration(seconds: 1)), fromMe: false);
    expect(Message.hasReplyFromMeSince('thread', since), isFalse);
  });

  test('my deleted reply after the pick time does not make it stale', () {
    saveReply(created: since.add(const Duration(seconds: 1)), deleted: since.add(const Duration(seconds: 2)));
    expect(Message.hasReplyFromMeSince('thread', since), isFalse);
  });
}
