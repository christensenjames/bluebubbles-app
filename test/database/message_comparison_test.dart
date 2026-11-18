import 'package:bluebubbles/database/io/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final old = DateTime.utc(2024);
  final recent = DateTime.utc(2025);
  final cases = <(String, Message, Message, bool)>[
    ('empty tie', Message(), Message(), false),
    ('date tie', Message(dateCreated: old), Message(dateCreated: old), false),
    ('newer creation', Message(dateCreated: recent), Message(dateCreated: old), true),
    ('older creation', Message(dateCreated: old), Message(dateCreated: recent), false),
    ('missing creation', Message(), Message(dateCreated: old), false),
    ('delivered beats newer creation', Message(dateCreated: old, isDelievered: true), Message(dateCreated: recent), true),
    ('undelivered loses to delivered', Message(dateCreated: recent), Message(dateCreated: old, isDelievered: true), false),
    ('other error beats delivery', Message(dateCreated: recent, isDelievered: true), Message(dateCreated: old, error: 1), false),
    ('own error does not break a tie', Message(dateCreated: old, error: 1), Message(dateCreated: old), false),
    ('read presence beats newer delivery', Message(dateCreated: old, dateDelivered: old, dateRead: old),
        Message(dateCreated: old, dateDelivered: recent), true),
    ('edited date takes precedence over creation', Message(dateCreated: recent, dateEdited: old),
        Message(dateCreated: old, dateEdited: recent), false),
    ('equal edit is a strict tie despite newer creation', Message(dateCreated: recent, dateEdited: old),
        Message(dateCreated: old, dateEdited: old), false),
  ];
  for (final (name, message, other, expected) in cases) {
    test(name, () => expect(message.isNewerThan(other), expected));
  }
}
