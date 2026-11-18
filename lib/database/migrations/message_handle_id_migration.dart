import 'package:bluebubbles/database/database.dart';
import 'package:collection/collection.dart';

class MessageHandleIdMigration {
  static void migrate() {
    final messages = Database.messages.getAll();
    if (messages.isEmpty) return;
    final handles = Database.handles.getAll();
    for (final message in messages) {
      if (message.isFromMe == true || message.handleId == 0 || message.handleId == null) continue;
      message.handleId = handles.firstWhereOrNull((handle) => handle.id == message.handleId)?.originalROWID ??
          message.handleId;
    }
    Database.messages.putMany(messages);
  }
}
