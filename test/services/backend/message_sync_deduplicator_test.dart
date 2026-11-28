import 'package:bluebubbles/services/backend/sync/message_sync_deduplicator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deduplicates snapshots per chat and detects changed snapshots', () {
    final cases = <(String, Map<String, dynamic>, bool)>[
      ('chat-a', {'guid': 'message', 'dateRead': null, 'text': 'hello', 'dateDeleted': null}, true),
      ('chat-a', {'guid': 'message', 'dateRead': null, 'text': 'hello', 'dateDeleted': null}, false),
      ('chat-b', {'guid': 'message', 'dateRead': null, 'text': 'hello', 'dateDeleted': null}, true),
      ('chat-a', {'guid': 'message', 'dateRead': 1, 'text': 'hello', 'dateDeleted': null}, true),
      ('chat-a', {'guid': 'message', 'dateRead': 1, 'text': 'edited', 'dateDeleted': null}, true),
      ('chat-a', {'guid': 'message', 'dateRead': 1, 'text': 'edited', 'dateDeleted': 2}, true),
      ('chat-a', {'guid': null}, true),
      ('chat-a', {'guid': null}, true),
    ];
    final deduplicator = MessageSyncDeduplicator();
    for (final (chat, snapshot, expected) in cases) {
      expect(deduplicator.shouldSync(chat, snapshot), expected, reason: '$chat $snapshot');
    }
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
