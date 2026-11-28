import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  setUpAll(openTestDatabase);
  setUp(Database.reset);

  final old = DateTime.utc(2024);
  final recent = DateTime.utc(2025);

  test('receipts advance but never move backward or disappear', () {
    final existing = Message(dateDelivered: old, dateRead: old);
    Message.merge(existing, Message(dateDelivered: recent, dateRead: recent));
    expect(existing.dateDelivered, recent);
    expect(existing.dateRead, recent);
    Message.merge(existing, Message(dateDelivered: old, dateRead: old));
    Message.merge(existing, Message());
    expect(existing.dateDelivered, recent);
    expect(existing.dateRead, recent);
  });

  test('an edit with the same timestamp is applied again', () {
    final existing = Message(dateEdited: old, text: 'old');
    Message.merge(existing, Message(dateEdited: old, text: 'updated'));
    expect(existing.dateEdited, old);
    expect(existing.text, 'updated');
  });

  test('a deletion survives older or missing deletion dates', () {
    final existing = Message();
    Message.merge(existing, Message(dateDeleted: recent));
    Message.merge(existing, Message(dateDeleted: old));
    Message.merge(existing, Message());
    expect(existing.dateDeleted, recent);
  });
}
