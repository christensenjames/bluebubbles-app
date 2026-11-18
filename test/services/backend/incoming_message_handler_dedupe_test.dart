import 'dart:async';

import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/incoming_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

IncomingPayload payload(String guid, {MessageSource source = MessageSource.socket}) => IncomingPayload(
      type: MessageEventType.newMessage,
      source: source,
      chat: Chat(guid: 'chat'),
      message: Message(guid: guid, isFromMe: true),
    );

void main() {
  setUpAll(openTestDatabase);
  setUp(() {
    Database.reset();
    isIsolateOverride = true;
  });
  tearDown(() => isIsolateOverride = false);

  test('same GUID deliveries serialize and deduplicate while another GUID can proceed', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final otherStarted = Completer<void>();
    final saves = <String>[];
    final handler = IncomingMessageHandler.forTest(
      hydrateChat: (chat, message) async => chat,
      saveMessage: (chat, message, attachments) async {
        saves.add(message.guid!);
        if (message.guid == 'same') {
          firstStarted.complete();
          await releaseFirst.future;
        } else {
          otherStarted.complete();
        }
        return message;
      },
    );
    addTearDown(handler.dispose);

    final first = handler.handle(payload('same'));
    await firstStarted.future;
    final duplicate = handler.handle(payload('same', source: MessageSource.methodChannel));
    final other = handler.handle(payload('other'));
    await otherStarted.future;
    expect(saves, ['same', 'other']);
    releaseFirst.complete();
    await Future.wait([first, duplicate, other]);
    expect(saves, ['same', 'other']);
    await handler.handle(payload('same', source: MessageSource.apiResponse));
    expect(saves, ['same', 'other']);
  });

  test('an existing GUID follows the update path instead of saving a new message', () async {
    Database.messages.put(Message(guid: 'existing', isFromMe: true));
    var hydrations = 0;
    var saves = 0;
    final handler = IncomingMessageHandler.forTest(
      hydrateChat: (chat, message) async {
        hydrations++;
        return chat;
      },
      saveMessage: (chat, message, attachments) async {
        saves++;
        return message;
      },
    );
    addTearDown(handler.dispose);

    await handler.handle(payload('existing'));
    expect(hydrations, 1);
    expect(saves, 0);
    expect(Database.messages.count(), 1);
  });

  test('a processed GUID still accepts an update', () async {
    var hydrations = 0;
    var saves = 0;
    final handler = IncomingMessageHandler.forTest(
      hydrateChat: (chat, message) async {
        hydrations++;
        return chat;
      },
      saveMessage: (chat, message, attachments) async {
        saves++;
        Database.messages.put(message);
        return message;
      },
    );
    addTearDown(handler.dispose);

    final incoming = payload('updated');
    await handler.handle(incoming);
    await handler.handle(incoming.copyWith(type: MessageEventType.updatedMessage));
    expect(saves, 1);
    expect(hydrations, 2);
    expect(Database.messages.count(), 1);
  });

  test('dedupe remembers the latest 100 GUIDs and evicts the oldest', () async {
    final saves = <String>[];
    final handler = IncomingMessageHandler.forTest(
      hydrateChat: (chat, message) async => chat,
      saveMessage: (chat, message, attachments) async {
        saves.add(message.guid!);
        return message;
      },
    );
    addTearDown(handler.dispose);

    for (var i = 0; i < 101; i++) {
      await handler.handle(payload('message-$i'));
    }
    await handler.handle(payload('message-1'));
    expect(saves.length, 101);
    await handler.handle(payload('message-0'));
    expect(saves.length, 102);
    expect(saves.last, 'message-0');
  });
}
