import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/backend/actions/chat_actions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/test_database.dart';

void main() {
  setUpAll(openTestDatabase);
  setUp(Database.reset);

  Chat saveChat(Chat chat) {
    Database.chats.put(chat);
    return chat;
  }

  Message saveMessage(Chat chat, String guid, DateTime date) {
    final message = Message(guid: guid, text: guid, dateCreated: date)..chat.target = chat;
    Database.messages.put(message);
    return message;
  }

  void setPreview(Chat chat, Message message) {
    chat.dbLatestMessage.target = message;
    chat.dbOnlyLatestMessageDate = message.dateCreated;
    Database.chats.put(chat);
  }

  test('moves messages and copies settings and newer preview', () async {
    final legacy = saveChat(Chat(
      guid: 'iMessage;-;+15550001', isPinned: true, pinnedIndex: 3, muteType: 'mute', muteArgs: 'forever',
      textFieldText: 'legacy draft', hasUnreadMessage: true, lastReadMessageGuid: 'read-legacy',
    ));
    final target = saveChat(Chat(guid: 'any;-;+15550001', textFieldText: ''));
    final oldMessage = saveMessage(target, 'old', DateTime.utc(2024));
    final newMessage = saveMessage(legacy, 'new', DateTime.utc(2025));
    setPreview(target, oldMessage);
    setPreview(legacy, newMessage);

    final result = await ChatActions.mergeLegacyChats({});

    expect(result, {'iMessage;-;+15550001': 'any;-;+15550001'});
    expect(Database.chats.get(legacy.id!), isNull);
    expect(Database.messages.get(newMessage.id!)!.chat.target!.guid, 'any;-;+15550001');
    final merged = Database.chats.get(target.id!)!;
    expect(merged.isPinned, true);
    expect(merged.pinIndex, 3);
    expect(merged.muteType, 'mute');
    expect(merged.muteArgs, 'forever');
    expect(merged.textFieldText, 'legacy draft');
    expect(merged.dbLatestMessage.target!.guid, 'new');
    expect(merged.dbOnlyLatestMessageDate!.millisecondsSinceEpoch, DateTime.utc(2025).millisecondsSinceEpoch);
    expect(merged.hasUnreadMessage, true);
    expect(merged.lastReadMessageGuid, 'read-legacy');
  });

  test('preserves existing settings and newer target preview', () async {
    final legacy = saveChat(Chat(
      guid: 'iMessage;-;+15550002', isPinned: true, pinnedIndex: 7, muteType: 'mute', muteArgs: 'legacy',
      textFieldText: 'legacy draft', hasUnreadMessage: true,
    ));
    final target = saveChat(Chat(
      guid: 'any;-;+15550002', isPinned: true, pinnedIndex: 2, muteType: 'other', muteArgs: 'target',
      textFieldText: 'target draft', hasUnreadMessage: false,
    ));
    final oldMessage = saveMessage(legacy, 'old', DateTime.utc(2024));
    final newMessage = saveMessage(target, 'new', DateTime.utc(2025));
    setPreview(legacy, oldMessage);
    setPreview(target, newMessage);

    expect(await ChatActions.mergeLegacyChats({}), {'iMessage;-;+15550002': 'any;-;+15550002'});
    final merged = Database.chats.get(target.id!)!;
    expect(merged.isPinned, true);
    expect(merged.pinIndex, 2);
    expect(merged.muteType, 'other');
    expect(merged.muteArgs, 'target');
    expect(merged.textFieldText, 'target draft');
    expect(merged.dbLatestMessage.target!.guid, 'new');
    expect(merged.dbOnlyLatestMessageDate!.millisecondsSinceEpoch, DateTime.utc(2025).millisecondsSinceEpoch);
    expect(merged.hasUnreadMessage, false);
    expect(Database.messages.get(oldMessage.id!)!.chat.target!.guid, 'any;-;+15550002');
  });

  test('deleted legacy moves messages without copying settings or preview', () async {
    final legacy = saveChat(Chat(
      guid: 'iMessage;-;+15550003', dateDeleted: DateTime.utc(2025), isPinned: true, pinnedIndex: 4,
      muteType: 'mute', textFieldText: 'deleted draft', hasUnreadMessage: true,
    ));
    final target = saveChat(Chat(guid: 'any;-;+15550003'));
    final message = saveMessage(legacy, 'deleted-chat-message', DateTime.utc(2025));
    setPreview(legacy, message);

    expect(await ChatActions.mergeLegacyChats({}), {'iMessage;-;+15550003': 'any;-;+15550003'});
    expect(Database.chats.get(legacy.id!), isNull);
    expect(Database.messages.get(message.id!)!.chat.target!.guid, 'any;-;+15550003');
    final merged = Database.chats.get(target.id!)!;
    expect(merged.isPinned, false);
    expect(merged.pinIndex, isNull);
    expect(merged.muteType, isNull);
    expect(merged.textFieldText, isNull);
    expect(merged.dbLatestMessage.target, isNull);
    expect(merged.dbOnlyLatestMessageDate, isNull);
    expect(merged.hasUnreadMessage, false);
  });

  test('moves group membership without duplicating an existing target', () async {
    final legacy = saveChat(Chat(guid: 'iMessage;-;+15550004'));
    final target = saveChat(Chat(guid: 'any;-;+15550004'));
    final both = CustomGroup(name: 'both')..chats.addAll([legacy, target]);
    final legacyOnly = CustomGroup(name: 'legacy')..chats.add(legacy);
    Database.customGroups.putMany([both, legacyOnly]);

    expect(await ChatActions.mergeLegacyChats({}), {'iMessage;-;+15550004': 'any;-;+15550004'});
    expect(Database.chats.get(legacy.id!), isNull);
    expect(Database.customGroups.get(both.id!)!.chats.map((c) => c.guid).toList(), ['any;-;+15550004']);
    expect(Database.customGroups.get(legacyOnly.id!)!.chats.map((c) => c.guid).toList(), ['any;-;+15550004']);
  });

  test('skips open legacy chat and chats without a counterpart', () async {
    final skipped = saveChat(Chat(guid: 'iMessage;-;+15550005', textFieldText: 'open draft'));
    final target = saveChat(Chat(guid: 'any;-;+15550005'));
    final unmatched = saveChat(Chat(guid: 'SMS;-;+15550006', textFieldText: 'unmatched draft'));
    final skippedMessage = saveMessage(skipped, 'skipped', DateTime.utc(2025));
    final unmatchedMessage = saveMessage(unmatched, 'unmatched', DateTime.utc(2025));

    expect(await ChatActions.mergeLegacyChats({'skipGuid': 'iMessage;-;+15550005'}), isEmpty);
    expect(Database.chats.get(skipped.id!)!.textFieldText, 'open draft');
    expect(Database.chats.get(target.id!)!.textFieldText, isNull);
    expect(Database.chats.get(unmatched.id!)!.textFieldText, 'unmatched draft');
    expect(Database.messages.get(skippedMessage.id!)!.chat.target!.guid, 'iMessage;-;+15550005');
    expect(Database.messages.get(unmatchedMessage.id!)!.chat.target!.guid, 'SMS;-;+15550006');
  });

  test('merges SMS and RCS prefixes', () async {
    final sms = saveChat(Chat(guid: 'SMS;-;+15550007'));
    final rcs = saveChat(Chat(guid: 'RCS;-;+15550008'));
    saveChat(Chat(guid: 'any;-;+15550007'));
    saveChat(Chat(guid: 'any;-;+15550008'));
    final smsMessage = saveMessage(sms, 'sms', DateTime.utc(2025));
    final rcsMessage = saveMessage(rcs, 'rcs', DateTime.utc(2025));

    expect(await ChatActions.mergeLegacyChats({}), {
      'SMS;-;+15550007': 'any;-;+15550007',
      'RCS;-;+15550008': 'any;-;+15550008',
    });
    expect(Database.chats.get(sms.id!), isNull);
    expect(Database.chats.get(rcs.id!), isNull);
    expect(Database.messages.get(smsMessage.id!)!.chat.target!.guid, 'any;-;+15550007');
    expect(Database.messages.get(rcsMessage.id!)!.chat.target!.guid, 'any;-;+15550008');
  });
}
