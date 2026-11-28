import 'package:bluebubbles/database/io/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final old = DateTime.utc(2024);
  final recent = DateTime.utc(2025);

  test('receipts advance but never move backward or disappear', () {
    final existing = Message();
    Message.merge(existing, Message(dateDelivered: old, dateRead: old));
    expect(existing.dateDelivered, old);
    expect(existing.dateRead, old);
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

  test('an older edit cannot overwrite a newer edit', () {
    final existing = Message(dateEdited: recent, text: 'new');
    Message.merge(existing, Message(dateEdited: old, text: 'stale'));
    expect(existing.dateEdited, recent);
    expect(existing.text, 'new');
  });

  test('a deletion survives older or missing deletion dates', () {
    final existing = Message();
    Message.merge(existing, Message(dateDeleted: recent));
    Message.merge(existing, Message(dateDeleted: old));
    Message.merge(existing, Message());
    expect(existing.dateDeleted, recent);
  });
}
