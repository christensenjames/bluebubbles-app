import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/outgoing_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  setUpAll(() async {
    await openTestDatabase();
    isIsolateOverride = true;
  });
  setUp(Database.reset);

  test('missing temp message saves the replacement with its chat', () async {
    final chat = Chat(guid: 'chat-guid');
    Database.chats.put(chat);
    final replacement = Message.fromMap({'guid': 'real-guid'});

    await OutgoingMessageHandler.swapOutgoingMessage(chat, 'temp-guid', replacement);

    expect(Message.findOne(guid: 'real-guid')!.chat.target!.guid, 'chat-guid');
    expect(Message.findOne(guid: 'temp-guid'), isNull);
  });

  test('existing temp message is renamed and keeps its chat', () async {
    final chat = Chat(guid: 'chat-guid');
    Database.chats.put(chat);
    Message.fromMap({'guid': 'temp-guid'}).save(chat: chat);
    final replacement = Message.fromMap({'guid': 'real-guid'});

    await OutgoingMessageHandler.swapOutgoingMessage(chat, 'temp-guid', replacement);

    expect(Message.findOne(guid: 'real-guid')!.chat.target!.guid, 'chat-guid');
    expect(Message.findOne(guid: 'temp-guid'), isNull);
  });
}
