import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/migrations/message_handle_id_migration.dart';
import 'package:bluebubbles/database/migrations/chat_latest_message_migration.dart';
import 'package:bluebubbles/database/migrations/message_handle_relationship_migration.dart';
import 'package:bluebubbles/database/migrations/preview_icon_migration.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  setUpAll(openTestDatabase);
  setUp(Database.reset);

  test('version 2 remaps incoming and null sender flags while preserving outgoing and unknown handles', () {
    final handle = Handle(address: 'alice', originalROWID: 123);
    Database.handles.put(handle);
    final incoming = Message(guid: 'incoming', handleId: handle.id, isFromMe: false);
    final unknownSender = Message(guid: 'null', handleId: handle.id, isFromMe: null);
    final outgoing = Message(guid: 'outgoing', handleId: handle.id, isFromMe: true);
    final unknownHandle = Message(guid: 'unknown', handleId: 999, isFromMe: false);
    Database.messages.putMany([incoming, unknownSender, outgoing, unknownHandle]);

    MessageHandleIdMigration.migrate();

    expect(Database.messages.get(incoming.id!)!.handleId, 123);
    expect(Database.messages.get(unknownSender.id!)!.handleId, 123);
    expect(Database.messages.get(outgoing.id!)!.handleId, handle.id);
    expect(Database.messages.get(unknownHandle.id!)!.handleId, 999);
  });

  test('version 6 links incoming handles by server row ID', () async {
    final handle = Handle(address: 'alice', originalROWID: 123);
    Database.handles.put(handle);
    final incoming = Message(guid: 'incoming', handleId: 123, isFromMe: false);
    final outgoing = Message(guid: 'outgoing', handleId: 123, isFromMe: true);
    final missing = Message(guid: 'missing', handleId: 456, isFromMe: false);
    Database.messages.putMany([incoming, outgoing, missing]);

    await MessageHandleRelationshipMigration.migrate();

    expect(Database.messages.get(incoming.id!)!.handleRelation.targetId, handle.id);
    expect(Database.messages.get(outgoing.id!)!.handleRelation.targetId, 0);
    expect(Database.messages.get(missing.id!)!.handleRelation.targetId, 0);
  });

  test('version 8 backfills newest non-deleted message and leaves empty chats untouched', () async {
    final chat = Chat(guid: 'chat');
    final empty = Chat(guid: 'empty');
    Database.chats.putMany([chat, empty]);
    final older = Message(guid: 'older', dateCreated: DateTime.utc(2020, 1, 1))..chat.target = chat;
    final latest = Message(guid: 'latest', dateCreated: DateTime.utc(2020, 1, 2))..chat.target = chat;
    final deleted = Message(guid: 'deleted', dateCreated: DateTime.utc(2020, 1, 3), dateDeleted: DateTime.utc(2020))
      ..chat.target = chat;
    Database.messages.putMany([older, latest, deleted]);

    await ChatLatestMessageMigration.migrate();

    final saved = Database.chats.get(chat.id!)!;
    expect(saved.dbLatestMessage.target!.guid, 'latest');
    expect(saved.dbOnlyLatestMessageDate!.toUtc(), DateTime.utc(2020, 1, 2));
    final savedEmpty = Database.chats.get(empty.id!)!;
    expect(savedEmpty.dbLatestMessage.target, isNull);
    expect(savedEmpty.dbOnlyLatestMessageDate, isNull);
  });

  test('version 10 collects valid hashes and skips corrupt metadata', () {
    Database.messages.putMany([
      Message(guid: 'one', metadata: {'previewIconMd5': 'abc'}),
      Message(guid: 'two', metadata: {'previewIconMd5': 'abc'}),
      Message(guid: 'three', metadata: {'previewIconMd5': 'def'}),
      Message(guid: 'other', metadata: {'other': 'ignored'}),
    ]);
    expect(PreviewIconMigration.hashes(), {'abc', 'def'});
    expect(PreviewIconMigration.hashesFromMetadata([
      '{"previewIconMd5":"abc"}',
      'broken previewIconMd5',
      '["previewIconMd5"]',
      '{"previewIconMd5":42}',
      '{"previewIconMd5":"def"}',
    ]), {'abc', 'def'});
  });
}
