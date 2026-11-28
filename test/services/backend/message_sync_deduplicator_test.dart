import 'package:bluebubbles/services/backend/sync/message_sync_deduplicator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an identical snapshot in the same chat is skipped', () {
    final deduplicator = MessageSyncDeduplicator();
    final snapshot = {'guid': 'message', 'text': 'hello'};
    expect(deduplicator.shouldSync('chat-a', snapshot), isTrue);
    expect(deduplicator.shouldSync('chat-a', snapshot), isFalse);
  });

  test('the same snapshot in another chat is synced', () {
    final deduplicator = MessageSyncDeduplicator();
    final snapshot = {'guid': 'message', 'text': 'hello'};
    expect(deduplicator.shouldSync('chat-a', snapshot), isTrue);
    expect(deduplicator.shouldSync('chat-b', snapshot), isTrue);
  });

  for (final (field, value) in <(String, dynamic)>[
    ('dateRead', 1),
    ('text', 'edited'),
    ('dateDeleted', 2),
  ]) {
    test('a changed $field is synced', () {
      final deduplicator = MessageSyncDeduplicator();
      final snapshot = <String, dynamic>{
        'guid': 'message', 'dateRead': null, 'text': 'hello', 'dateDeleted': null,
      };
      expect(deduplicator.shouldSync('chat-a', snapshot), isTrue);
      expect(deduplicator.shouldSync('chat-a', {...snapshot, field: value}), isTrue);
    });
  }

  test('a null GUID is always synced', () {
    final deduplicator = MessageSyncDeduplicator();
    final snapshot = <String, dynamic>{'guid': null};
    expect(deduplicator.shouldSync('chat-a', snapshot), isTrue);
    expect(deduplicator.shouldSync('chat-a', snapshot), isTrue);
  });

  test('keeps a copy of nested input when the caller mutates it', () {
    final deduplicator = MessageSyncDeduplicator();
    final snapshot = <String, dynamic>{'guid': 'message', 'parts': [{'text': 'original'}]};
    expect(deduplicator.shouldSync('chat', snapshot), isTrue);
    (snapshot['parts'] as List)[0]['text'] = 'changed';
    expect(deduplicator.shouldSync('chat', {
      'guid': 'message',
      'parts': [{'text': 'original'}],
    }), isFalse);
    expect(deduplicator.shouldSync('chat', snapshot), isTrue);
  });
}
