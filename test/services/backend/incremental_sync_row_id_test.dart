import 'package:bluebubbles/services/backend/sync/incremental_sync_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = <(String, int?, List<Map<String, dynamic>>) >[
    ('no end', null, [
      {'statement': 'message.ROWID > :startRowId', 'args': {'startRowId': 10}},
    ]),
    ('end before start', 9, [
      {'statement': 'message.ROWID > :startRowId', 'args': {'startRowId': 10}},
    ]),
    ('end equal to start', 10, [
      {'statement': 'message.ROWID > :startRowId', 'args': {'startRowId': 10}},
    ]),
    ('end after start', 11, [
      {'statement': 'message.ROWID > :startRowId', 'args': {'startRowId': 10}},
      {'statement': 'message.ROWID <= :endRowId', 'args': {'endRowId': 11}},
    ]),
  ];
  for (final (name, end, expected) in cases) {
    test(name, () => expect(IncrementalSyncManager.buildRowIdWhereArgs(10, end), expected));
  }
}
